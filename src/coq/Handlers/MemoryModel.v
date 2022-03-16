From Vellvm.Syntax Require Import
     DataLayout
     DynamicTypes.

From Vellvm.Semantics Require Import
     MemoryAddress
     MemoryParams
     LLVMParams
     LLVMEvents.

From Vellvm.Utils Require Import
     Error
     PropT.

From ExtLib Require Import
     Structures.Monads
     Structures.Functor.

From ITree Require Import
     ITree
     Basics.Basics
     Events.Exception
     Eq.Eq
     Events.StateFacts
     Events.State.

From Coq Require Import
     ZArith.

Import Basics.Basics.Monads.
Import MonadNotation.
Open Scope monad_scope.

(* Move this ? *)
Definition store_id := N.
Class MonadStoreID (M : Type -> Type) : Type :=
  { fresh_sid : M store_id;
    get_sid : M store_id;
    put_sid : store_id -> M unit;
  }.

Class MonadMemState (MemState : Type) (M : Type -> Type) : Type :=
  { get_mem_state : M MemState;
    put_mem_state : MemState -> M unit;
  }.

Definition modify_mem_state {M MemState} `{Monad M} `{MonadMemState MemState M} (f : MemState -> MemState) : M MemState :=
  ms <- get_mem_state;;
  put_mem_state (f ms);;
  ret ms.

(* TODO: Add RAISE_PICK or something... May need to be in a module *)
Class MemMonad (MemState : Type) (Provenance : Type) (M : Type -> Type)
      `{Monad M}
      `{MonadProvenance Provenance M} `{MonadStoreID M} `{MonadMemState MemState M}
      `{RAISE_ERROR M} `{RAISE_UB M} `{RAISE_OOM M} : Type
  :=
  {
    MemMonad_runs_to_prop {A} (ma : M A) (ms : MemState) (res : OOM (MemState * A)) : Prop;
    MemMonad_runs_to {A} (ma : M A) (ms : MemState) : option (MemState * A);
    MemMonad_lift_stateT
      {E} `{FailureE -< E} `{UBE -< E} `{OOME -< E} {A}
      (ma : M A) : stateT MemState (itree E) A;
  }.

(* Module types for memory models to allow different memory models to be plugged in. *)
Module Type MemoryModel (LP : LLVMParams) (MP : MemoryParams LP).
  Import LP.Events.
  Import LP.ADDR.
  Import LP.SIZEOF.

  Import LP.PROV.
  (* TODO: Should DataLayout be here?

     It might make sense to move DataLayout to another module, some of
     the parameters in the DataLayout may be relevant to other
     modules, and we could enforce that everything agrees.

     For instance alignment may impact Sizeof, and there's also some
     stuff about pointer sizes in the DataLayout structure.
   *)
  (* Parameter datalayout : DataLayout. *)

  (** Datatype for the state of memory *)
  Parameter MemState : Type.
  Parameter initial_memory_state : MemState.

  Definition MemStateT := stateT MemState.

  Instance MemStateT_MonadProvenance {M} :
    MonadProvenance Provenance (MemStateT M).
  Proof.
  Admitted.

  Instance MemStateT_MonadStoreID {M} :
    MonadStoreID (MemStateT M).
  Proof.
  Admitted.

  Instance MemStateT_MonadMemState {M} :
    MonadMemState MemState (MemStateT M).
  Proof.
    split.
    eapply (MonadState.get).
    eapply (MonadState.put).
  Admitted.

  Parameter free_concrete_space :
    forall (ms : MemState) (phys_addr : Z) (sz : N), bool.

  Definition concrete_memory_pick_post
             (st : MemState * (addr * dtyp)) (phys_addr : Z) : Prop
    := match st with
       | (ms, (a, dt)) =>
           free_concrete_space ms phys_addr (sizeof_dtyp dt) = true
       end.

  Definition PickConcreteMemoryE :=
    @PickE (MemState * (addr * dtyp)) Z concrete_memory_pick_post.

  (* Not sure if we need this yet *)
  Parameter free_logical_space :
    forall (ms : MemState) (ptr : addr) (sz : N), bool.

  Definition PickLogicalMemoryE :=
    @PickE (MemState * dtyp) addr
           (fun '(ms, dt) ptr =>
              free_logical_space ms ptr (sizeof_dtyp dt) = true).

  Instance MemStateT_itree_MemMonad
           {E} `{FailureE -< E} `{UBE -< E} `{OOME -< E} `{PickConcreteMemoryE -< E}
    : MemMonad MemState Provenance (MemStateT (itree E)).
  Admitted.

  (* (** MemMonad *) *)
  (* Parameter MemMonad : Type -> Type. *)

  (* (** Extra monad classes *) *)
  (* Parameter MemMonad_MonadStoreID : MonadStoreID MemMonad. *)
  (* Parameter MemMonad_MonadProvenance : MonadProvenance Provenance MemMonad. *)
  (* Parameter MemMonad_MonadMemState : MonadMemState MemState MemMonad. *)

  (* Parameter MemMonad_RAISE_ERROR : RAISE_ERROR MemMonad. *)
  (* Parameter MemMonad_RAISE_UB : RAISE_UB MemMonad. *)
  (* Parameter MemMonad_RAISE_OOM : RAISE_OOM MemMonad. *)
  (* Parameter MemMonad_RAISE_PICK : RAISE_PICK MemMonad. *)

  (* (* Hack to make typeclass resolution work... *) *)
  (* Hint Resolve MemMonad_MonadStoreID : typeclass_instances. *)
  (* Hint Resolve MemMonad_MonadProvenance : typeclass_instances. *)
  (* Hint Resolve MemMonad_MonadMemState : typeclass_instances. *)
  (* Hint Resolve MemMonad_RAISE_ERROR : typeclass_instances. *)
  (* Hint Resolve MemMonad_RAISE_UB : typeclass_instances. *)
  (* Hint Resolve MemMonad_RAISE_OOM : typeclass_instances. *)
  (* Hint Resolve MemMonad_RAISE_PICK : typeclass_instances. *)

  (* Parameter MemMonad_runs_to : forall {A} (ma : MemMonad A) (ms : MemState), option (MemState * A). *)
  (* Parameter MemMonad_lift_stateT :  *)
  (*   forall {E} `{FailureE -< E} `{UBE -< E} `{OOME -< E} `{PickE -< E} {A} *)
  (*     (ma : MemMonad A), stateT MemState (itree E) A. *)

  (** Basic operations on the state of logical memory. *)
  Parameter allocate :
    forall {M} `{MemMonad MemState Provenance M} (dt : dtyp),
      M addr.

  Parameter allocated :
    forall {M} `{MemMonad MemState Provenance M} (ptr : addr),
      M bool.

  Parameter read :
    forall {M} `{MemMonad MemState Provenance M} (ptr : addr) (t : dtyp), M uvalue.

  Parameter write :
    forall {M} `{MemMonad MemState Provenance M}
      (ptr : addr) (v : uvalue) (t : dtyp),
      M unit.

  (** Operations for interacting with the concrete layout of memory. *)
  Parameter reserve_block : MemState -> LP.IP.intptr -> N -> option MemState.

  Section Handlers.
    (* TODO: Should we generalize the return type? *)
    Parameter handle_memory :
      forall {M} `{MemMonad MemState Provenance M},
      MemoryE ~> M.

    Parameter handle_intrinsic :
      forall {M} `{MemMonad MemState Provenance M},
      IntrinsicE ~> M.
   End Handlers.
End MemoryModel.

Module MemoryModelSpec (LP : LLVMParams) (MP : MemoryParams LP).
  Import LP.Events.
  Import LP.ADDR.
  Import LP.SIZEOF.
  Import LP.PROV.

  Require Import MemBytes.
  Module MemByte := Byte LP.ADDR LP.IP LP.SIZEOF LP.Events MP.BYTE_IMPL.
  Import MemByte.
  Import LP.SIZEOF.

  Parameter MemState : Type.
  Definition MemPropT (X: Type): Type :=
    MemState -> err (OOM (MemState * X)%type) -> Prop.

  Instance MemPropT_Monad : Monad MemPropT.
  Proof.
    split.
    - (* ret *)
      intros T x.
      unfold MemPropT.
      intros ms [err_msg | [[ms' res] | oom_msg]].
      + exact False. (* error is not a valid behavior here *)
      + exact (ms = ms' /\ x = res).
      + exact True. (* Allow OOM to refine anything *)
    - (* bind *)
      intros A B ma amb.
      unfold MemPropT in *.

      intros ms [err_msg | [[ms'' b] | oom_msg]].
      + (* an error is valid when ma errors, or the continuation errors... *)
        refine
          ((exists err, ma ms (inl err)) \/
           (exists ms' a,
               ma ms (inr (NoOom (ms', a))) ->
               (exists err, amb a ms' (inl err)))).
      + (* No errors, no OOM *)
        refine
          (exists ms' a k,
              ma ms (inr (NoOom (ms', a))) ->
              amb a ms' (inr (NoOom (ms'', k a)))).
      + (* OOM is always valid *)
        exact True.
  Defined.

  Instance MemPropT_MonadMemState : MonadMemState MemState MemPropT.
  Proof.
    split.
    - (* get_mem_state *)
      unfold MemPropT.
      intros ms [err_msg | [[ms' a] | oom_msg]].
      + exact True.
      + exact (ms = ms' /\ a = ms).
      + exact True.
    - (* put_mem_state *)
      unfold MemPropT.
      intros ms_to_put ms [err_msg | [[ms' t] | oom_msg]].
      + exact True.
      + exact (ms_to_put = ms').
      + exact True.
  Defined.

  Instance MemPropT_RAISE_OOM : RAISE_OOM MemPropT.
  Proof.
    split.
    - intros A msg.
      unfold MemPropT.
      intros ms [err | [_ | oom]].
      + exact False. (* Must run out of memory, can't error *)
      + exact False. (* Must run out of memory *)
      + exact True. (* Don't care about message *)
  Defined.

  Instance MemPropT_RAISE_ERROR : RAISE_ERROR MemPropT.
  Proof.
    split.
    - intros A msg.
      unfold MemPropT.
      intros ms [err | [_ | oom]].
      + exact True. (* Any error will do *)
      + exact False. (* Must error *)
      + exact False. (* Must error *)
  Defined.

  Definition MemPropT_assert {X} (assertion : Prop) : MemPropT X
    := fun ms ms'x =>
         match ms'x with
         | inl _ =>
             assertion
         | inr (NoOom (ms', x)) =>
             ms = ms' /\ assertion
         | inr (Oom s) =>
             assertion
         end.

  Definition MemPropT_assert_post {X} (Post : X -> Prop) : MemPropT X
    := fun ms ms'x =>
         match ms'x with
         | inl _ =>
             True
         | inr (NoOom (ms', x)) =>
             ms = ms' /\ Post x
         | inr (Oom s) =>
             True
         end.

  Section Handlers.
    Variable (E F: Type -> Type).
    Context `{FailureE -< E}.

    Variable MemM : Type -> Type.
    Context `{MemM_MemMonad : MemMonad MemState Provenance MemM}.

    Parameter write_byte_allowed : MemState -> addr -> Prop.
    Parameter write_byte_prop : MemState -> addr -> SByte -> MemState -> Prop.

    (* Parameters of the memory state module *)
    Parameter read_byte_MemPropT : addr -> MemPropT SByte.
    Definition read_byte_prop (ms : MemState) (ptr : addr) (byte : SByte) : Prop
      := read_byte_MemPropT ptr ms (inr (NoOom (ms, byte))).

    Parameter addr_allocated_prop : addr -> MemPropT bool.

    Definition byte_allocated_MemPropT (ptr : addr) : MemPropT unit :=
      m <- get_mem_state;;
      b <- addr_allocated_prop ptr;;
      MemPropT_assert (b = true).

    Definition byte_allocated (ms : MemState) (ptr : addr) : Prop
      := byte_allocated_MemPropT ptr ms (inr (NoOom (ms, tt))).

    Definition allocations_preserved (m1 m2 : MemState) : Prop :=
      forall ptr, byte_allocated m1 ptr <-> byte_allocated m2 ptr.

    Parameter disjoint_ptr_byte : addr -> addr -> Prop.

    Parameter Frame : Type.
    Parameter ptr_in_frame : Frame -> addr -> Prop.

    Parameter FrameStack : Type.
    Parameter peek_frame_stack : FrameStack -> Frame -> Prop.
    Parameter pop_frame_stack : FrameStack -> FrameStack -> Prop.
    (* Parameter push_frame_stack : FrameStack -> Frame -> FrameStack -> Prop. *)

    Parameter mem_state_frame_stack : MemState -> FrameStack -> Prop.

    (*** Reading from memory *)
    Record read_byte_spec (ms : MemState) (ptr : addr) (byte : SByte) : Prop :=
      { read_byte_allocated : byte_allocated ms ptr;
        read_byte_value : read_byte_prop ms ptr byte;
      }.

    Definition read_byte_spec_MemPropT (ptr : addr) : MemPropT SByte:=
      fun m1 res =>
           match res with
           | inr (NoOom (m2, byte)) => m1 = m2 /\ read_byte_spec m1 ptr byte
           | _ => True (* Allowed to run out of memory or fail *)
           end.

    (*** Framestack operations *)
    Definition empty_frame (f : Frame) : Prop :=
      forall ptr, ~ ptr_in_frame f ptr.

    Record add_ptr_to_frame (f1 : Frame) (ptr : addr) (f2 : Frame) : Prop :=
      {
        old_frame_lu : forall ptr', ptr_in_frame f1 ptr' -> ptr_in_frame f2 ptr';
        new_frame_lu : ptr_in_frame f2 ptr;
      }.

    Record empty_frame_stack (fs : FrameStack) : Prop :=
      {
        no_pop : (forall f, ~ pop_frame_stack fs f);
        empty_fs_empty_frame : forall f, peek_frame_stack fs f -> empty_frame f;
      }.

    Record push_frame_stack_spec (fs1 : FrameStack) (f : Frame) (fs2 : FrameStack) : Prop :=
      {
        can_pop : pop_frame_stack fs2 fs1;
        new_frame : peek_frame_stack fs2 f;
      }.

    Definition ptr_in_current_frame (ms : MemState) (ptr : addr) : Prop
      := forall fs, mem_state_frame_stack ms fs ->
               forall f, peek_frame_stack fs f ->
                    ptr_in_frame f ptr.

    (** mempush *)
    Record mempush_spec (m1 : MemState) (m2 : MemState) : Prop :=
      {
        (* All allocations are preserved *)
        mempush_allocations :
        allocations_preserved m1 m2;

        (* All reads are preserved *)
        mempush_lu : forall ptr byte,
          read_byte_spec m1 ptr byte <->
            read_byte_spec m2 ptr byte;

        fresh_frame :
        forall fs1 fs2 f,
          mem_state_frame_stack m1 fs1 ->
          empty_frame f ->
          push_frame_stack_spec fs1 f fs2 ->
          mem_state_frame_stack m2 fs2;
      }.

    Definition mempush_spec_MemPropT : MemPropT unit :=
      fun m1 res =>
        match res with
        | inr (NoOom (m2, _)) => mempush_spec m1 m2
        | _ => True (* Allowed to run out of memory or fail *)
        end.

    (** mempop *)
    Record mempop_spec (m1 : MemState) (m2 : MemState) : Prop :=
      {
        (* all bytes in popped frame are freed. *)
        bytes_freed :
        forall ptr,
          ptr_in_current_frame m1 ptr ->
          ~byte_allocated m2 ptr;

        (* Bytes not allocated in the current frame have the same allocation status as before *)
        non_frame_bytes_preserved :
        forall ptr,
          (~ ptr_in_current_frame m1 ptr) ->
          byte_allocated m1 ptr <-> byte_allocated m2 ptr;

        non_frame_bytes_read :
        forall ptr byte,
          (~ ptr_in_current_frame m1 ptr) ->
          read_byte_spec m1 ptr byte <-> read_byte_spec m2 ptr byte;

        pop_frame :
        forall fs1 fs2,
          mem_state_frame_stack m1 fs1 ->
          pop_frame_stack fs1 fs2 ->
          mem_state_frame_stack m2 fs2;
      }.

    Definition mempop_spec_MemPropT : MemPropT unit :=
      fun m1 res =>
        match res with
        | inr (NoOom (m2, _)) => mempop_spec m1 m2
        | _ => True (* Allowed to run out of memory or fail *)
        end.

    (* Add a pointer onto the current frame in the frame stack *)
    Definition add_ptr_to_frame_stack (fs1 : FrameStack) (ptr : addr) (fs2 : FrameStack) : Prop :=
      forall f f' fs1_pop,
        peek_frame_stack fs1 f ->
        add_ptr_to_frame f ptr f' ->
        pop_frame_stack fs1 fs1_pop ->
        push_frame_stack_spec fs1_pop f' fs2.

    Definition frame_stack_preserved (m1 m2 : MemState) : Prop
      := forall fs,
        mem_state_frame_stack m1 fs <-> mem_state_frame_stack m2 fs.

    (*** Writing to memory *)
    Record set_byte_memory (m1 : MemState) (ptr : addr) (byte : SByte) (m2 : MemState) : Prop :=
      {
        new_lu : read_byte_spec m2 ptr byte;
        old_lu : forall ptr' byte',
          disjoint_ptr_byte ptr ptr' ->
          (read_byte_spec m1 ptr' byte' <-> read_byte_spec m2 ptr' byte');
      }.

    (* I'll need something like this? *)
    Parameter write_byte_allowed_allocated :
      forall m ptr, write_byte_allowed m ptr -> byte_allocated m ptr.

    Record write_byte_spec (m1 : MemState) (ptr : addr) (byte : SByte) (m2 : MemState) : Prop :=
      {
        byte_write_succeeds : write_byte_allowed m1 ptr;
        byte_written : set_byte_memory m1 ptr byte m2;

        write_byte_preserves_allocations : allocations_preserved m1 m2;
        write_byte_preserves_frame_stack : frame_stack_preserved m1 m2;
      }.

    Definition write_byte_spec_MemPropT (ptr : addr) (byte : SByte) : MemPropT unit
      := fun m1 res =>
           match res with
           | inr (NoOom (m2, _)) => write_byte_spec m1 ptr byte m2
           | _ => True (* Allowed to run out of memory or fail *)
           end.

    (*** Allocating bytes in memory *)

    (* This spec could be wrong... 

       What if I can 
     *)
    Record allocate_byte_succeeds_spec (m1 : MemState) (t : dtyp) (init_byte : SByte) (m2 : MemState) (ptr : addr) : Prop :=
      {
        was_fresh_byte : ~ byte_allocated m1 ptr;
        now_byte_allocated : byte_allocated m2 ptr;
        init_byte_written : set_byte_memory m1 ptr init_byte m2;
        old_allocations_preserved :
        forall ptr',
          disjoint_ptr_byte ptr ptr' ->
          (byte_allocated m1 ptr' <-> byte_allocated m2 ptr');

        add_to_frame :
        forall fs1 fs2,
          mem_state_frame_stack m1 fs1 ->
          add_ptr_to_frame_stack fs1 ptr fs2 ->
          mem_state_frame_stack m2 fs2;
      }.

    Definition allocate_byte_spec_MemPropT (t : dtyp) (init_byte : SByte) : MemPropT addr
      := fun m1 res =>
           match res with
           | inr (NoOom (m2, ptr)) =>
               allocate_byte_succeeds_spec m1 t init_byte m2 ptr
           | _ => True (* Allowed to run out of memory or fail *)
           end.

    (*** Aggregate things *)

    Import MP.GEP.
    Require Import List.
    Import ListNotations.
    Import LP.
    Import ListUtil.
    Import Utils.Monads.

    (* TODO: Move this? *)
    Definition intptr_seq (start : Z) (len : nat) : OOM (list IP.intptr)
      := Util.map_monad (IP.from_Z) (Zseq start len).

    Definition get_consecutive_ptrs (ptr : addr) (len : nat) : MemPropT (list addr) :=
      ixs <- lift_OOM (intptr_seq 0 len);;
      lift_err_RAISE_ERROR
        (Util.map_monad
           (fun ix => handle_gep_addr (DTYPE_I 8) ptr [DVALUE_IPTR ix])
           ixs).

    Definition write_bytes_spec (ptr : addr) (bytes : list SByte) : MemPropT unit :=
      ptrs <- get_consecutive_ptrs ptr (length bytes);;
      let ptr_bytes := zip ptrs bytes in

      (* Actually perform writes *)
      Util.map_monad_ (fun '(ptr, byte) => write_byte_spec_MemPropT ptr byte) ptr_bytes.

    Definition read_bytes_spec (ptr : addr) (len : nat) : MemPropT (list SByte) :=
      ptrs <- get_consecutive_ptrs ptr len;;

      (* Actually perform reads *)
      Util.map_monad (fun ptr => read_byte_spec_MemPropT ptr) ptrs.

    (* TODO: double check that this is correct.

       A little worried about how the assert works out + possible
       get_consecutive_ptrs failures.
     *)
    Definition allocate_bytes_spec (t : dtyp) (init_bytes : list SByte) : MemPropT addr :=
      match init_bytes with
      | nil =>
          fun m1 res =>
            match res with
            | inr (NoOom (m2, ptr)) =>
                m1 = m2
            | _ => True (* Allowed to run out of memory or fail *)
            end
      | _ =>
          ptrs <- Util.map_monad (allocate_byte_spec_MemPropT t) init_bytes;;

          match ptrs with
          | nil => fun m1 res => True (* Bogus case, shouldn't happen *)
          | (ptr::_) =>
              consec_ptrs <- get_consecutive_ptrs ptr (length ptrs);;
              MemPropT_assert (ptrs = consec_ptrs)
          end
      end.

    (* Need to make sure MemPropT has provenance and sids to generate the bytes. *)
    Definition allocate_dtyp_spec (t : dtyp) : MemPropT addr.
    Admitted.

    Definition handle_memory_prop : MemoryE ~> MemPropT
      := fun T m =>
           match m with
           (* Unimplemented *)
           | MemPush =>
               mempush_spec_MemPropT
           | MemPop =>
               mempop_spec_MemPropT
           | Alloca t =>
               allocate_dtyp_spec t
           | Load t a =>
               (* TODO: make sure this checks provenance *)
               read_uvalue_spec t a
           | Store t a v =>
               (* TODO: should use write_allowed, but make sure this respects provenance + store ids *)
               write_uvalue_spec t a v
           end.
  End Handlers.
End MemoryModelSpec.
