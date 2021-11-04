(* -------------------------------------------------------------------------- *
 *                     Vellvm - the Verified LLVM project                     *
 *                                                                            *
 *     Copyright (c) 2017 Steve Zdancewic <stevez@cis.upenn.edu>              *
 *                                                                            *
 *   This file is distributed under the terms of the GNU General Public       *
 *   License as published by the Free Software Foundation, either version     *
 *   3 of the License, or (at your option) any later version.                 *
 ---------------------------------------------------------------------------- *)

(* begin hide *)
From Coq Require Import
     ZArith
     List
     String
     Setoid
     Morphisms
     Omega
     Classes.RelationClasses.

From ExtLib Require Import
     Core.RelDec
     Programming.Eqv
     Structures.Monads
     Data.Monads.EitherMonad
     Data.Monads.IdentityMonad.

From ITree Require Import
     ITree
     Events.Exception.

From Vellvm Require Import
     Utilities
     Syntax
     Semantics.MemoryAddress
     Semantics.Memory.Sizeof
     Semantics.DynamicValues.

Import ITreeNotations.
(* end hide *)

(****************************** LLVM Events *******************************)
(**
   Vellvm's semantics relies on _Interaction Trees_, a generic data-structure allowing to model
   effectful computations.
   This file defined the interface provided to the interaction trees, that is the set of
   events that a LLVM program can trigger.
   These events are then concretely interpreted as a succession of handler, as defined in the
   _Handlers_ folder.
   The possible events are:
   * Function calls                                                          [CallE]
   * External function calls                                                 [ExternalCallE]
   * Calls to intrinsics whose implementation _do not_ depends on the memory [IntrinsicE]
   * Interactions with the global environment                                [GlobalE]
   * Interactions with the local environment                                 [LocalE]
   * Manipulation of the frame stack for local environments                  [StackE]
   * Interactions with the memory                                            [MemoryE]
   * Concretization of a under-defined value                                 [PickE]
   * Undefined behaviour                                                     [UBE]
   * Failure                                                                 [FailureE]
   * Debugging messages                                                      [DebugE]
*)

Set Implicit Arguments.
Set Contextual Implicit.

 (* Interactions with global variables for the LLVM IR *)
 (* Note: Globals are read-only, except for the initialization. We could want to reflect this in the events themselves. *)
  Variant GlobalE (k v:Type) : Type -> Type :=
  | GlobalWrite (id: k) (dv: v): GlobalE k v unit
  | GlobalRead  (id: k): GlobalE k v v.

  (* Interactions with local variables for the LLVM IR *)
  Variant LocalE (k v:Type) : Type -> Type :=
  | LocalWrite (id: k) (dv: v): LocalE k v unit
  | LocalRead  (id: k): LocalE k v v.

  Variant StackE (k v:Type) : Type -> Type :=
  | StackPush (args: list (k * v)) : StackE k v unit (* Pushes a fresh environment during a call *)
  | StackPop : StackE k v unit. (* Pops it back during a ret *)

  (* Undefined behaviour carries a string. *)
  Variant UBE : Type -> Type :=
  | ThrowUB : string -> UBE void.

  (** Since the output type of [ThrowUB] is [void], we can make it an action
    with any return type. *)
  Definition raiseUB {E : Type -> Type} `{UBE -< E} {X}
             (e : string)
    : itree E X 
    := v <- trigger (ThrowUB e);; match v: void with end.

  (* Out of memory / abort. Carries a string for a message. *)
  Variant OOME : Type -> Type :=
  | ThrowOOM : string -> OOME void.

  (* Out of memory / abort. Differs from OOME in that there is no message string. *)
  Variant OOME_NOMSG : Type -> Type :=
  | ThrowOOM_NOMSG : OOME_NOMSG void.

  (** Since the output type of [ThrowUB] is [void], we can make it an action
    with any return type. *)
  Definition raiseOOM {E : Type -> Type} `{OOME -< E} {X}
             (e : string)
    : itree E X 
    := v <- trigger (ThrowOOM e);; match v: void with end.

  (* Debug is identical to the "Trace" effect from the itrees library,
   but debug is probably a less confusing name for us. *)
  Variant DebugE : Type -> Type :=
  | Debug : string -> DebugE unit.
  (* Utilities to conveniently trigger debug events *)
  Definition debug {E} `{DebugE -< E} (msg : string) : itree E unit :=
    trigger (Debug msg).

  Definition FailureE := exceptE unit.

  (* This function can be replaced with print_string during extraction
     to print the error messages of Throw and (indirectly) ThrowUB. *)
  Definition print_msg (msg : string) : unit := tt.

  Definition raise {E} {A} `{FailureE -< E} (msg : string) : itree E A :=
    v <- trigger (Throw _ (print_msg msg));; match v: void with end.
    
  Definition lift_err {A B} {E} `{FailureE -< E} (f : A -> itree E B) (m:err A) : itree E B :=
    match m with
    | inl x => raise x
    | inr x => f x
    end.

  Definition lift_pure_err {A} {E} `{FailureE -< E} (m:err A) : itree E A :=
    lift_err ret m.

  Definition lift_err_ub_oom {A B} {E} `{FailureE -< E} `{UBE -< E} `{OOME -< E} (f : A -> itree E B) (m:err_ub_oom A) : itree E B :=
    match m with
    | ERR_UB_OOM (mkEitherT (mkEitherT (mkEitherT (mkIdent m)))) =>
        match m with
        | inl (OOM_message x) => raiseOOM x
        | inr (inl (UB_message x)) => raiseUB x
        | inr (inr (inl (ERR_message x))) => raise x
        | inr (inr (inr x)) => f x
      end
    end.


(* TODO: decouple these definitions from the instance of DVALUE and DTYP by using polymorphism not functors. *)
Module Type LLVM_INTERACTIONS (ADDR : MemoryAddress.ADDRESS) (IP:MemoryAddress.INTPTR) (SIZEOF : Sizeof).

  #[global] Instance eq_dec_addr : RelDec (@eq ADDR.addr) := RelDec_from_dec _ ADDR.eq_dec.
  #[global] Instance Eqv_addr : Eqv ADDR.addr := (@eq ADDR.addr).

  Module DV := DynamicValues.DVALUE(ADDR)(IP)(SIZEOF).
  Export DV.

  Section Events.
    Variable memory : Type.

    (* Generic calls, refined by [denote_mcfg] *)
    Variant CallE : Type -> Type :=
    | Call        : forall (t:dtyp) (f:uvalue) (args:list uvalue), CallE uvalue.

    Variant ExternalCallE : Type -> Type :=
    | ExternalCall        : forall (t:dtyp) (f:uvalue) (args:list dvalue), ExternalCallE dvalue.

    (* Call to an intrinsic whose implementation do not rely on the implementation of the memory model *)
    Variant IntrinsicE : Type -> Type :=
    | Intrinsic : forall (t:dtyp) (f:string) (args:list dvalue), IntrinsicE dvalue.

    (* Interactions with the memory *)
    Variant MemoryE : Type -> Type :=
    | MemPush : MemoryE unit
    | MemPop  : MemoryE unit
    | Alloca  : forall (t:dtyp),                               (MemoryE dvalue)
    | Load    : forall (t:dtyp) (a:dvalue),                    (MemoryE uvalue)
    (* Store address should be unique... *)
    | Store   : forall (t:dtyp) (a:dvalue) (v:uvalue),         (MemoryE unit)
    | GEP     : forall (t:dtyp) (v:uvalue) (vs:list uvalue),   (MemoryE uvalue)
    | ItoP    : forall (t:dtyp) (i:uvalue),                    (MemoryE uvalue)
    | PtoI    : forall (t:dtyp) (a:uvalue),                    (MemoryE uvalue)
  .

  (* An event resolving the non-determinism induced by undef. The argument _P_
   is intended to be a predicate over the set of dvalues _u_ can take such that
   if it is not satisfied, the only possible execution is to raise _UB_.
   *)
  Variant PickE : Type -> Type :=
  | pick (u:uvalue) (P : Prop) : PickE dvalue.
  (* Need to change handler to actually use prop, need to parameterize... *)

  (* Variant PickE (X : Type) : Type := *)
  (* | pick (x:X) (P : X -> Prop) : PickE dvalue. *)


  (* Variant PickE (X Y : Type) : Type := *)
  (* | pick (x:X) (P : X -> Y -> Prop) : PickE X Y. *)

  (* Variant PickE (X Y : Type) : Type := *)
  (* | pick (x:X) (concrete_handler : X -> Y) (pick_handler : X -> Y -> Prop) : PickE X Y. *)

  (* Variant PickE (X Y : Type) : Type := *)
  (* | pick (x:X) : PickE X Y. (* Predicate is just part of handler?  Different pick event for each kind of choice we make... *) *)

  (*
  X = uvalue / memory
  Y = dvalue / address
   *)

  Definition unique_prop (uv : uvalue) : Prop
    := True.

  Definition pickAll (p : uvalue -> PickE dvalue) := map_monad (fun uv => trigger (p uv)).

  (* The signatures for computations that we will use during the successive stages of the interpretation of LLVM programs *)
  (* TODO: The events and handlers are parameterized by the types of key and value.
     It's weird for it to be the case if the events are concretely instantiated right here.
     At least TODO: remove these prefixes that are inconsistent with other names.
   *)
  Definition LLVMGEnvE := (GlobalE raw_id dvalue).
  Definition LLVMEnvE := (LocalE raw_id uvalue).
  Definition LLVMStackE := (StackE raw_id uvalue).

  Definition conv_E := MemoryE +' PickE +' OOME +' UBE +' DebugE +' FailureE.
  Definition lookup_E := LLVMGEnvE +' LLVMEnvE.
  Definition exp_E := LLVMGEnvE +' LLVMEnvE +' MemoryE +' PickE +' OOME +' UBE +' DebugE +' FailureE.

  Definition LU_to_exp : lookup_E ~> exp_E :=
    fun T e =>
      match e with
      | inl1 e => inl1 e
      | inr1 e => inr1 (inl1 e)
      end.

  Definition conv_to_exp : conv_E ~> exp_E :=
    fun T e => inr1 (inr1 e).

  Definition instr_E := CallE +' IntrinsicE +' exp_E.
  Definition exp_to_instr : exp_E ~> instr_E :=
    fun T e => inr1 (inr1 e).

  (* Core effects. *)
  Definition L0' := CallE +' ExternalCallE +' IntrinsicE +' LLVMGEnvE +' (LLVMEnvE +' LLVMStackE) +' MemoryE +' PickE +' OOME +' UBE +' DebugE +' FailureE.

  Definition instr_to_L0' : instr_E ~> L0' :=
    fun T e =>
      match e with
      | inl1 e => inl1 e
      | inr1 (inl1 e) => inr1 (inr1 (inl1 e))
      | inr1 (inr1 (inl1 e)) => inr1 (inr1 (inr1 (inl1 e)))
      | inr1 (inr1 (inr1 (inl1 e))) => inr1 (inr1 (inr1 (inr1 (inl1 (inl1 e)))))
      | inr1 (inr1 (inr1 (inr1 e))) => inr1 (inr1 (inr1 (inr1 (inr1 e))))
      end.

  Definition exp_to_L0' : exp_E ~> L0' :=
    fun T e => instr_to_L0' (exp_to_instr e).

  Definition FUB_to_exp : (FailureE +' UBE) ~> exp_E :=
    fun T e =>
      match e with
      | inl1 x => inr1 (inr1 (inr1 (inr1 (inr1 (inr1 (inr1 x))))))
      | inr1 x => inr1 (inr1 (inr1 (inr1 (inr1 (inl1 x)))))
      end.

  Definition FUBO_to_exp : (FailureE +' UBE +' OOME) ~> exp_E :=
    fun T e =>
      match e with
      | inl1 x => inr1 (inr1 (inr1 (inr1 (inr1 (inr1 (inr1 x))))))
      | inr1 (inl1 x) => inr1 (inr1 (inr1 (inr1 (inr1 (inl1 x)))))
      | inr1 (inr1 x) => inr1 (inr1 (inr1 (inr1 (inl1 x))))
      end.

  Definition L0 := ExternalCallE +' IntrinsicE +' LLVMGEnvE +' (LLVMEnvE +' LLVMStackE) +' MemoryE +' PickE +' OOME +' UBE +' DebugE +' FailureE.

  Definition exp_to_L0 : exp_E ~> L0 :=
    fun T e =>
      match e with
      | inl1 e => inr1 (inr1 (inl1 e))
      | inr1 (inl1 e) => inr1 (inr1 (inr1 (inl1 (inl1 e))))
      | inr1 (inr1 e) => inr1 (inr1 (inr1 (inr1 e)))
      end.

  (* For multiple CFG, after interpreting [GlobalE] *)
  Definition L1 := ExternalCallE +' IntrinsicE +' (LLVMEnvE +' LLVMStackE) +' MemoryE +' PickE +' OOME +' UBE +' DebugE +' FailureE.

  (* For multiple CFG, after interpreting [LocalE] *)
  Definition L2 := ExternalCallE +' IntrinsicE +' MemoryE +' PickE +' OOME +' UBE +' DebugE +' FailureE.

  (* For multiple CFG, after interpreting [LocalE] and [MemoryE] and [IntrinsicE] that are memory intrinsics *)
  Definition L3 := ExternalCallE +' PickE +' OOME +' UBE +' DebugE +' FailureE.

  (* For multiple CFG, after interpreting [LocalE] and [MemoryE] and [IntrinsicE] that are memory intrinsics and [PickE]*)
  Definition L4 := ExternalCallE +' OOME +' UBE +' DebugE +' FailureE.

  Definition L5 := ExternalCallE +' OOME_NOMSG +' UBE +' DebugE +' FailureE.

  Definition L5_exec := ExternalCallE +' UBE +' DebugE +' FailureE.

  Definition L6 := ExternalCallE +' OOME_NOMSG +' DebugE +' FailureE.

  Definition L6_exec := ExternalCallE +' DebugE +' FailureE.

  Definition FUBO_to_L4 : (FailureE +' UBE +' OOME) ~> L4:=
    fun T e =>
      match e with
      | inl1 x => inr1 (inr1 (inr1 (inr1 x)))
      | inr1 (inl1 x) => inr1 (inr1 (inl1 x))
      | inr1 (inr1 x) => inr1 (inl1 x)
      end
    .

  End Events.

  #[export] Hint Unfold L0 L0' L1 L2 L3 L4 L5 : core.

End LLVM_INTERACTIONS.

Module Make(ADDR : MemoryAddress.ADDRESS)(IP:MemoryAddress.INTPTR)(SIZEOF : Sizeof) <: LLVM_INTERACTIONS(ADDR)(IP)(SIZEOF).
Include LLVM_INTERACTIONS(ADDR)(IP)(SIZEOF).
End Make.
