From Coq Require Import
     Relations
     String
     List
     Lia.

From Vellvm Require Import
     Semantics.InterpretationStack
     Semantics.LLVMEvents
     Semantics.Denotation
     Semantics.MemoryAddress
     Semantics.Memory.Sizeof
     Semantics.Lang
     Semantics.InterpretationStack
     Semantics.TopLevel
     Semantics.DynamicValues
     Semantics.LLVMParams
     Theory.TopLevelRefinements
     Utils.Error
     Utils.Monads
     Utils.PropT
     Utils.ListUtil.

From ExtLib Require Import
     Structures.Monads
     Structures.Functor.

From ITree Require Import
     ITree
     Basics.Basics.

Import MonadNotation.
Import ListNotations.

Module Type AddrConvert (ADDR1 : ADDRESS) (ADDR2 : ADDRESS).
  Parameter addr_convert : ADDR1.addr -> OOM ADDR2.addr.
End AddrConvert.

Module FinAddrConvert : AddrConvert FiniteMemory.Addr FiniteMemory.Addr.
  Definition addr_convert (a : FiniteMemory.Addr.addr) : OOM FiniteMemory.Addr.addr := ret a.
End FinAddrConvert.

Module Type DVConvert (LP1 : LLVMParams) (LP2 : LLVMParams) (AC : AddrConvert LP1.ADDR LP2.ADDR) (Events1 : LLVM_INTERACTIONS LP1.ADDR LP1.IP LP1.SIZEOF) (Events2 : LLVM_INTERACTIONS LP2.ADDR LP2.IP LP2.SIZEOF).
  Parameter dvalue_convert : Events1.DV.dvalue -> OOM Events2.DV.dvalue.
  Parameter uvalue_convert : Events1.DV.uvalue -> OOM Events2.DV.uvalue.
End DVConvert.

Module DVConvertMake (LP1 : LLVMParams) (LP2 : LLVMParams) (AC : AddrConvert LP1.ADDR LP2.ADDR) (Events1 : LLVM_INTERACTIONS LP1.ADDR LP1.IP LP1.SIZEOF) (Events2 : LLVM_INTERACTIONS LP2.ADDR LP2.IP LP2.SIZEOF) : DVConvert LP1 LP2 AC Events1 Events2.
  Import AC.

  Module DV1 := Events1.DV.
  Module DV2 := Events2.DV.

  Obligation Tactic := try Tactics.program_simpl; try solve [cbn; try lia | DV1.solve_dvalue_measure | DV1.solve_uvalue_measure].

  Program Fixpoint dvalue_convert (dv1 : DV1.dvalue) {measure (DV1.dvalue_measure dv1)} : OOM DV2.dvalue
    := match dv1 with
       | DV1.DVALUE_Addr a =>
           a' <- addr_convert a;;
           ret (DV2.DVALUE_Addr a')
       | DV1.DVALUE_I1 x  => ret (DV2.DVALUE_I1 x)
       | DV1.DVALUE_I8 x  => ret (DV2.DVALUE_I8 x)
       | DV1.DVALUE_I32 x => ret (DV2.DVALUE_I32 x)
       | DV1.DVALUE_I64 x => ret (DV2.DVALUE_I64 x)
       | DV1.DVALUE_IPTR x =>
           let xz := LP1.IP.to_Z x in
           x' <- LP2.IP.from_Z xz;;
           ret (DV2.DVALUE_IPTR x')
       | DV1.DVALUE_Double x => ret (DV2.DVALUE_Double x)
       | DV1.DVALUE_Float x => ret (DV2.DVALUE_Float x)
       | DV1.DVALUE_Poison t => ret (DV2.DVALUE_Poison t)
       | DV1.DVALUE_None => ret DV2.DVALUE_None
       | DV1.DVALUE_Struct fields =>
           fields' <- map_monad_In fields (fun elt Hin => dvalue_convert elt);;
           ret (DV2.DVALUE_Struct fields')
       | DV1.DVALUE_Packed_struct fields =>
           fields' <- map_monad_In fields (fun elt Hin => dvalue_convert elt);;
           ret (DV2.DVALUE_Packed_struct fields')
       | DV1.DVALUE_Array elts =>
           elts' <- map_monad_In elts (fun elt Hin => dvalue_convert elt);;
           ret (DV2.DVALUE_Array elts')
       | DV1.DVALUE_Vector elts =>
           elts' <- map_monad_In elts (fun elt Hin => dvalue_convert elt);;
           ret (DV2.DVALUE_Vector elts')
       end.

  Program Fixpoint uvalue_convert (uv1 : DV1.uvalue) {measure (DV1.uvalue_measure uv1)} : OOM DV2.uvalue
    := match uv1 with
       | DV1.UVALUE_Addr a =>
           a' <- addr_convert a;;
           ret (DV2.UVALUE_Addr a')
       | DV1.UVALUE_I1 x  => ret (DV2.UVALUE_I1 x)
       | DV1.UVALUE_I8 x  => ret (DV2.UVALUE_I8 x)
       | DV1.UVALUE_I32 x => ret (DV2.UVALUE_I32 x)
       | DV1.UVALUE_I64 x => ret (DV2.UVALUE_I64 x)
       | DV1.UVALUE_IPTR x =>
           let xz := LP1.IP.to_Z x in
           x' <- LP2.IP.from_Z xz;;
           ret (DV2.UVALUE_IPTR x')
       | DV1.UVALUE_Double x => ret (DV2.UVALUE_Double x)
       | DV1.UVALUE_Float x => ret (DV2.UVALUE_Float x)
       | DV1.UVALUE_Poison t => ret (DV2.UVALUE_Poison t)
       | DV1.UVALUE_None => ret DV2.UVALUE_None
       | DV1.UVALUE_Struct fields =>
           fields' <- map_monad_In fields (fun elt Hin => uvalue_convert elt);;
           ret (DV2.UVALUE_Struct fields')
       | DV1.UVALUE_Packed_struct fields =>
           fields' <- map_monad_In fields (fun elt Hin => uvalue_convert elt);;
           ret (DV2.UVALUE_Packed_struct fields')
       | DV1.UVALUE_Array elts =>
           elts' <- map_monad_In elts (fun elt Hin => uvalue_convert elt);;
           ret (DV2.UVALUE_Array elts')
       | DV1.UVALUE_Vector elts =>
           elts' <- map_monad_In elts (fun elt Hin => uvalue_convert elt);;
           ret (DV2.UVALUE_Vector elts')
       | DV1.UVALUE_Undef dt =>
           (* Could be a bit odd with intptr *)
           ret (DV2.UVALUE_Undef dt)
       | DV1.UVALUE_IBinop iop v1 v2 =>
           v1' <- uvalue_convert v1;;
           v2' <- uvalue_convert v2;;
           ret (DV2.UVALUE_IBinop iop v1' v2')
       | DV1.UVALUE_ICmp cmp v1 v2 =>
           v1' <- uvalue_convert v1;;
           v2' <- uvalue_convert v2;;
           ret (DV2.UVALUE_ICmp cmp v1' v2')
       | DV1.UVALUE_FBinop fop fm v1 v2 =>
           v1' <- uvalue_convert v1;;
           v2' <- uvalue_convert v2;;
           ret (DV2.UVALUE_FBinop fop fm v1' v2')
       | DV1.UVALUE_FCmp cmp v1 v2 =>
           v1' <- uvalue_convert v1;;
           v2' <- uvalue_convert v2;;
           ret (DV2.UVALUE_FCmp cmp v1' v2')
       | DV1.UVALUE_Conversion conv t_from v t_to =>
           v' <- uvalue_convert v;;
           ret (DV2.UVALUE_Conversion conv t_from v' t_to)
       | DV1.UVALUE_GetElementPtr t ptrval idxs =>
           ptrval' <- uvalue_convert ptrval;;
           idxs' <- map_monad_In idxs (fun elt Hin => uvalue_convert elt);;
           ret (DV2.UVALUE_GetElementPtr t ptrval' idxs')
       | DV1.UVALUE_ExtractElement vec idx =>
           vec' <- uvalue_convert vec;;
           idx' <- uvalue_convert idx;;
           ret (DV2.UVALUE_ExtractElement vec' idx')
       | DV1.UVALUE_InsertElement vec elt idx =>
           vec' <- uvalue_convert vec;;
           elt' <- uvalue_convert elt;;
           idx' <- uvalue_convert idx;;
           ret (DV2.UVALUE_InsertElement vec' elt' idx')
       | DV1.UVALUE_ShuffleVector vec1 vec2 idxmask =>
           vec1' <- uvalue_convert vec1;;
           vec2' <- uvalue_convert vec2;;
           idxmask' <- uvalue_convert idxmask;;
           ret (DV2.UVALUE_ShuffleVector vec1' vec2' idxmask')
       | DV1.UVALUE_ExtractValue vec idxs =>
           vec' <- uvalue_convert vec;;
           ret (DV2.UVALUE_ExtractValue vec' idxs)
       | DV1.UVALUE_InsertValue vec elt idxs =>
           vec' <- uvalue_convert vec;;
           elt' <- uvalue_convert elt;;
           ret (DV2.UVALUE_InsertValue vec' elt' idxs)
       | DV1.UVALUE_Select cnd v1 v2 =>
           cnd' <- uvalue_convert cnd;;
           v1' <- uvalue_convert v1;;
           v2' <- uvalue_convert v2;;
           ret (DV2.UVALUE_Select cnd' v1' v2')
       | DV1.UVALUE_ExtractByte uv dt idx sid =>
           uv' <- uvalue_convert uv;;
           idx' <- uvalue_convert idx;;
           ret (DV2.UVALUE_ExtractByte uv' dt idx' sid)
       | DV1.UVALUE_ConcatBytes uvs dt =>
           uvs' <- map_monad_In uvs (fun elt Hin => uvalue_convert elt);;
           ret (DV2.UVALUE_ConcatBytes uvs' dt)
       end.

End DVConvertMake.

Module EventConvert (LP1 : LLVMParams) (LP2 : LLVMParams) (AC : AddrConvert LP1.ADDR LP2.ADDR) (AC2 : AddrConvert LP2.ADDR LP1.ADDR) (E1 : LLVM_INTERACTIONS LP1.ADDR LP1.IP LP1.SIZEOF) (E2 : LLVM_INTERACTIONS LP2.ADDR LP2.IP LP2.SIZEOF).
  (* TODO: should this be a parameter? *)
  Module DVC := DVConvertMake LP1 LP2 AC E1 E2.
  Module DVCrev := DVConvertMake LP2 LP1 AC2 E2 E1.
  Import DVC.

  Require Import String.

  Definition L4_convert : Handler E1.L4 E2.L4.
  Proof.
    refine (fun A e => _).

    refine (match e with
            | inl1 (E1.ExternalCall dt f args) =>
                _
            | inr1 (inl1 e0) =>
                raise_oom ""
            | inr1 (inr1 (inl1 e0)) =>
                _ (* UBE *)
            | inr1 (inr1 (inr1 (inl1 e0))) =>
                _ (* DebugE *)
            | inr1 (inr1 (inr1 (inr1 e0))) =>
                _ (* FailureE *)
            end).

    (* External Calls *)
    refine (f' <- lift_OOM (uvalue_convert f);;
            args' <- lift_OOM (map_monad_In args (fun elt Hin => dvalue_convert elt));;
            dv <- trigger (E2.ExternalCall dt f' args');;
            _).

    inversion e0.
    apply (lift_OOM (DVCrev.dvalue_convert dv)).

    (* UBE *)
    inversion e0.
    apply (raise_ub "").

    (* DebugE *)
    inversion e0.
    apply (debug H).

    (* FailureE *)
    inversion e0.
    unfold FailureE in e0.
    apply (raise_error "").
  Defined.

  Definition L5_convert : Handler E1.L5 E2.L5.
  Proof.
    refine (fun A e => _).

    refine (match e with
            | inl1 (E1.ExternalCall dt f args) =>
                _
            | inr1 (inl1 e0) =>
                raise_oom ""
            | inr1 (inr1 (inl1 e0)) =>
                _
            | inr1 (inr1 (inr1 e0)) =>
                _
            end).

    (* External Calls *)
    refine (f' <- lift_OOM (uvalue_convert f);;
            args' <- lift_OOM (map_monad_In args (fun elt Hin => dvalue_convert elt));;
            dv <- trigger (E2.ExternalCall dt f' args');;
            _).

    inversion e0.
    apply (lift_OOM (DVCrev.dvalue_convert dv)).

    (* DebugE *)
    inversion e0.
    apply (debug H).

    (* FailureE *)
    inversion e0.
    unfold FailureE in e0.
    apply (raise_error "").
  Defined.

  Definition L6_convert : Handler E1.L6 E2.L6.
  Proof.
    refine (fun A e => _).

    refine (match e with
            | inl1 (E1.ExternalCall dt f args) =>
                _
            | inr1 (inl1 e0) =>
                raise_oom ""
            | inr1 (inr1 (inl1 e0)) =>
                _
            | inr1 (inr1 (inr1 e0)) =>
                _
            end).

    (* External Calls *)
    refine (f' <- lift_OOM (uvalue_convert f);;
            args' <- lift_OOM (map_monad_In args (fun elt Hin => dvalue_convert elt));;
            dv <- trigger (E2.ExternalCall dt f' args');;
            _).

    inversion e0.
    apply (lift_OOM (DVCrev.dvalue_convert dv)).

    (* DebugE *)
    inversion e0.
    apply (debug H).

    (* FailureE *)
    inversion e0.
    unfold FailureE in e0.
    apply (raise_error "").
  Defined.
End EventConvert.

Module Type LangRefine (IS1 : InterpreterStack) (IS2 : InterpreterStack) (AC1 : AddrConvert IS1.LP.ADDR IS2.LP.ADDR) (AC2 : AddrConvert IS2.LP.ADDR IS1.LP.ADDR) (LLVM1 : LLVMTopLevel IS1) (LLVM2 : LLVMTopLevel IS2) (TLR : TopLevelRefinements IS2 LLVM2).
  Module E1 := IS1.LLVM.Events.
  Module E2 := IS2.LLVM.Events.

  Module EC := EventConvert IS1.LP IS2.LP AC1 AC2 IS1.LLVM.Events E2.
  Import EC.
  Import EC.DVC.

  (* TODO: move this? *)
  Definition L4_convert_tree {T} (t : itree E1.L4 T) : itree E2.L4 T := interp L4_convert t.
  Definition L5_convert_tree {T} (t : itree E1.L5 T) : itree E2.L5 T := interp L5_convert t.
  Definition L6_convert_tree {T} (t : itree E1.L6 T) : itree E2.L6 T := interp L6_convert t.

  (* Relate trees at L4 with proper refinement relation... *)
  Import LLVM2.
  Import TLR.
  Import TLR.R.

  Definition L4_convert_PropT {A B} (f : A -> OOM B) (ts : PropT IS1.LLVM.Events.L4 A) : PropT E2.L4 B
    := fun t_e2 => exists t_e1,
           ts t_e1 /\ t_e2 = L4_convert_tree (uv <- t_e1;; lift_OOM (f uv)).

  (* Ideally we would convert memstates / local envs / local stacks /
     global envs... But for now we can get away with placeholders for
     these because the refine_res3 relation used by refine_L6 ignores
     these.
   *)
  Definition res_L4_convert_unsafe (res : LLVM1.res_L4) : OOM LLVM2.res_L4
    := match res with
       | (ms, ((lenv, lstack), (genv, uv))) =>
           uv' <- uvalue_convert uv;;
           ret (IS2.LLVM.MEM.emptyMemState, (([], []), ([], uv')))
       end.
 
  Definition refine_E1E2_L6 (srcs : PropT IS1.LLVM.Events.L4 LLVM1.res_L4) (tgts : PropT E2.L4 LLVM2.res_L4) : Prop
    :=
    (* res_L4_convert_unsafe should be fine here because refine_L6
       ignores all of the placeholder values *)
    refine_L6 (L4_convert_PropT res_L4_convert_unsafe srcs) tgts.

  (* TODO: not sure about name... *)
  Definition model_E1E2_L6
             (p1 p2 : list
                        (LLVMAst.toplevel_entity
                           LLVMAst.typ
                           (LLVMAst.block LLVMAst.typ * list (LLVMAst.block LLVMAst.typ))))
    : Prop :=
    refine_E1E2_L6 (LLVM1.model p1) (LLVM2.model p2).

End LangRefine.

Module InfiniteToFinite : LangRefine InterpreterStackBigIntptr InterpreterStack64BitIntptr FinAddrConvert FinAddrConvert TopLevelBigIntptr TopLevel64BitIntptr TopLevelRefinements64BitIntptr.
  Include LangRefine InterpreterStackBigIntptr InterpreterStack64BitIntptr FinAddrConvert FinAddrConvert TopLevelBigIntptr TopLevel64BitIntptr TopLevelRefinements64BitIntptr.

  From Vellvm Require Import InterpreterMCFG.

  Import MCFGTheoryBigIntptr.
  Import MCFGTheory64BitIntptr.

  Module TLR_INF := TopLevelRefinementsBigIntptr.
  Module TLR_FIN := TopLevelRefinements64BitIntptr.

  Lemma refine_E1E2_L6_compose :
    forall ti1 ti2 tf2 tf1,
      TLR_INF.R.refine_L6 ti1 ti2 ->
      refine_E1E2_L6 ti2 tf2 ->
      TLR_FIN.R.refine_L6 tf2 tf1 ->
      refine_E1E2_L6 ti1 tf1.
  Proof.
    intros ti1 ti2 tf2 tf1 RINF RITOF RFIN.

    unfold refine_E1E2_L6 in *.
    Require Import Coq.Classes.RelationClasses.

  Qed.

  Lemma model_E1E2_L6_sound :
    forall (p : list
             (LLVMAst.toplevel_entity
                LLVMAst.typ
                (LLVMAst.block LLVMAst.typ * list (LLVMAst.block LLVMAst.typ)))),
      model_E1E2_L6 p p.
  Proof.
    intros p.
    unfold model_E1E2_L6.
    intros t' m_fin.
    exists t'.
    split.
    - unfold L4_convert_PropT.
      (* t_e1 is a tree in the model of the program in the infinite
         semantics, and t_e1 "agrees" with the behavior (t') in the
         finite semantics.

         "Agrees" in this context means that t' is equivalent to t_e1
         with the events converted, and the resulting uvalue converted.
       *)
      induction p.
      + unfold TopLevelBigIntptr.model, TopLevelBigIntptr.model_gen.
        cbn.
        From Vellvm Require Import Tactics.
        eexists.

        From ITree Require Import
             ITree
             Basics.Monad
             Events.StateFacts
             Eq.Eq.

        (* This rewrite is taking forever... wtf. *)
        rewrite bind_ret_l.
        repeat rewrite bind_ret_l.
        
        MCFGTheoryBigIntptr.MCFGTactics.go.
    - right.
      apply eutt_refine_oom_h; try typeclasses eauto.
      reflexivity.
  Qed.
End InfiniteToFinite.
