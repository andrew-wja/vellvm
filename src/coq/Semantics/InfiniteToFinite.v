From Coq Require Import
     Relations
     String
     List
     Lia
     ZArith
     Morphisms.

Require Import Coq.Logic.ProofIrrelevance.

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
     Semantics.InfiniteToFinite.Conversions.BaseConversions
     Semantics.InfiniteToFinite.Conversions.DvalueConversions
     Semantics.InfiniteToFinite.Conversions.EventConversions
     Semantics.InfiniteToFinite.Conversions.TreeConversions
     Semantics.InfiniteToFinite.LangRefine
     Syntax.DynamicTypes
     Theory.TopLevelRefinements
     Theory.ContainsUB
     Utils.Error
     Utils.Monads
     Utils.MapMonadExtra
     Utils.PropT
     Utils.InterpProp
     Utils.ListUtil
     Utils.Tactics
     Utils.OOMRutt
     Utils.OOMRuttProps
     Handlers.MemoryModules.FiniteAddresses
     Handlers.MemoryModules.InfiniteAddresses
     Handlers.MemoryModelImplementation.

From ExtLib Require Import
     Structures.Monads
     Structures.Functor.

From ITree Require Import
     ITree
     Basics
     Basics.HeterogeneousRelations
     Eq.Rutt
     Eq.RuttFacts
     Eq.Eqit
     Eq.EqAxiom.

Require Import Coq.Program.Equality.
Require Import Paco.paco.

Import InterpFacts.

Import MonadNotation.
Import ListNotations.

Notation LLVM_syntax :=
  (list (LLVMAst.toplevel_entity
              LLVMAst.typ
              (LLVMAst.block LLVMAst.typ * list (LLVMAst.block LLVMAst.typ)))).

Module InfiniteToFinite.
  (* Import FinInfLangRefine. (* Just planning on using this for L4_convert from finite to infinite events. *) *)
  Import InfFinLangRefine.

  From Vellvm Require Import InterpreterMCFG.

  Import MCFGTheoryBigIntptr.
  Import MCFGTheory64BitIntptr.

  Module TLR_INF := TopLevelRefinementsBigIntptr.
  Module TLR_FIN := TopLevelRefinements64BitIntptr.

  Hint Resolve interp_PropT__mono : paco.

  (* TODO: Move these refine_OOM_h lemmas? *)
  Import Morphisms.

  Import TC1.

  #[local] Notation E1 := (E1.ExternalCallE +' OOME +' UBE +' DebugE +' FailureE).
  #[local] Notation E2 := (E2.ExternalCallE +' OOME +' UBE +' DebugE +' FailureE).
  #[local] Notation OOM_h := (refine_OOM_handler).

  Module InfLLVM := Vellvm.Semantics.InterpretationStack.InterpreterStackBigIntptr.LLVM.
  Module FinLLVM := Vellvm.Semantics.InterpretationStack.InterpreterStack64BitIntptr.LLVM.
  Module InfFinTC := Vellvm.Semantics.InfiniteToFinite.LangRefine.InfFinLangRefine.TC1.
  (* Module FinInfTC := Vellvm.Semantics.InfiniteToFinite.LangRefine.FinInfLangRefine.TC1. *)

  Module EC1 := InfFinTC.EC.
  (* Module EC2 := FinInfTC.EC. *)

  Module InfMem := MemoryBigIntptr.
  Module FinMem := Memory64BitIntptr.

  Module InfMemMMSP := MemoryBigIntptr.MMEP.MMSP.
  Module FinMemMMSP := Memory64BitIntptr.MMEP.MMSP.

  Module InfMemInterp := MemoryBigIntptr.MEM_SPEC_INTERP.
  Module FinMemInterp := Memory64BitIntptr.MEM_SPEC_INTERP.

  (* Could not put with the other conversions, need to know what memory structures like MemState are *)
  Definition convert_SByte (sb1 : MemoryBigIntptr.MP.BYTE_IMPL.SByte) : OOM (Memory64BitIntptr.MP.BYTE_IMPL.SByte).
    destruct sb1.
    refine (uv' <- EC.DVC.uvalue_convert_strict uv;;
            idx' <- EC.DVC.uvalue_convert_strict idx;;
            ret (FiniteSizeof.mkUByte LLVMParams64BitIntptr.Events.DV.uvalue uv' dt idx' sid)).
  Defined.

  Definition convert_mem_byte (mb1 : InfMemMMSP.mem_byte) : OOM (FinMemMMSP.mem_byte).
    destruct mb1.
    refine (s' <- convert_SByte s;;
            ret _).

    constructor.
    apply s'.
    apply a.
  Defined.

  (* Slightly tricky.

     Both the infinite and finite memory have the same underlying
     structure --- a map from Z to mem_bytes.

     The Z indexes in the finite memory may need to be limited to the
     range of the address type, but it may not matter because trying
     to look these up in a program should cause OOM anyway.
   *)
  Definition convert_memory (mem : InfMemMMSP.memory) : OOM (FinMemMMSP.memory).
    refine (elems <- map_monad _ (IntMaps.IM.elements mem);;
            ret (IntMaps.IP.of_list elems)).

    refine (fun '(ix, mb) =>
              mb' <- convert_mem_byte mb;;
              ret (ix, mb')).
  Defined.

  Definition convert_Frame (f : InfMemMMSP.Frame) : OOM (FinMemMMSP.Frame).
    induction f.
    - exact (ret []).
    - refine (a' <- InfToFinAddrConvert.addr_convert a;;
              f' <- IHf;;
              ret (a' :: f')).
  Defined.

  Definition convert_FrameStack (fs : InfMemMMSP.FrameStack) : OOM (FinMemMMSP.FrameStack).
    induction fs.
    - refine (f' <- convert_Frame f;;
              ret (FinMemMMSP.Singleton f')).
    - refine (f' <- convert_Frame f;;
              fs' <- IHfs;;
              ret (FinMemMMSP.Snoc fs' f')).
  Defined.

  Definition convert_Block (b : InfMemMMSP.Block) : OOM (FinMemMMSP.Block)
    := map_monad InfToFinAddrConvert.addr_convert b.

  Definition convert_Heap (h : InfMemMMSP.Heap) : OOM (FinMemMMSP.Heap).
    refine (blocks <- map_monad _ (IntMaps.IM.elements h);;
            ret (IntMaps.IP.of_list blocks)).

    refine (fun '(ix, b) =>
              b' <- convert_Block b;;
              ret (ix, b')).
  Defined.

  Definition convert_memory_stack (ms1 : InfMemMMSP.memory_stack) : OOM (FinMemMMSP.memory_stack).
    destruct ms1 as [mem fs h].
    refine (mem' <- convert_memory mem;;
            fs' <- convert_FrameStack fs;;
            h' <- convert_Heap h;;
            ret _).

    constructor; auto.
  Defined.

  Definition convert_MemState (m1 : InfMem.MMEP.MMSP.MemState) : OOM (FinMem.MMEP.MMSP.MemState).
    destruct m1 as [ms pr].
    refine (ms' <- convert_memory_stack ms;;
            ret _).

    constructor; auto.
  Defined.

  Definition MemState_refine (m1 : InfMem.MMEP.MMSP.MemState) (m2 : FinMem.MMEP.MMSP.MemState) : Prop
    := convert_MemState m1 = NoOom m2.

  Lemma MemState_refine_initial :
    MemState_refine InfMemMMSP.initial_memory_state FinMemMMSP.initial_memory_state.
  Proof.
    reflexivity.
  Qed.

  Instance refine_OOM_h_eq_itree {E F T RR} : Proper (eq_itree eq ==> eq_itree eq ==> iff) (@refine_OOM_h E F T RR).
  repeat intro. rewrite H, H0.
  reflexivity.
  Qed.

  Lemma refine_OOM_h_bind :
    forall {T R E F} (x y : itree (E +' OOME +' F) T) (RR1 : relation T) (RR2 : relation R) k,
      (forall r1 r2, RR1 r1 r2 -> refine_OOM_h RR2 (k r1) (k r2)) ->
      refine_OOM_h RR1 x y ->
      refine_OOM_h RR2 (a <- x;; k a) (a <- y;; k a).
  Proof.
    intros T R E F.

    unfold refine_OOM_h, refine_OOM_h_flip.
    intros t1 t2 RR1 RR2.

    unfold bind, Monad_itree.
    revert t1 t2. pcofix CIH.
    intros t1 t2 k HK EQT.
    punfold EQT.
    red in EQT.

    assert (a <- t1 ;; k a =
              match observe t1 with
              | RetF r => k r
              | TauF t0 => Tau (ITree.bind t0 k)
              | @VisF _ _ _ X e ke => Vis e (fun x : X => ITree.bind (ke x) k)
              end).
    { apply bisimulation_is_eq; setoid_rewrite unfold_bind; reflexivity. }
    setoid_rewrite H; clear H.

    assert (a <- t2 ;; k a =
              match observe t2 with
              | RetF r => k r
              | TauF t0 => Tau (ITree.bind t0 k)
              | @VisF _ _ _ X e ke => Vis e (fun x : X => ITree.bind (ke x) k)
              end).
    { apply bisimulation_is_eq; setoid_rewrite unfold_bind; reflexivity. }
    setoid_rewrite H; clear H.

    pstep.
    induction EQT; eauto; pclearbot.
    - specialize (HK _ _ REL).
      punfold HK.
      eapply interp_PropTF_mono. eapply HK.
      intros. pclearbot. left.
      eapply paco2_mon; eauto.
      intros; contradiction.
    - constructor. right.
      eapply CIH; eauto.
    - econstructor; auto.
    - econstructor; auto.
    - eapply Interp_PropT_Vis_OOM with (e := e).
      punfold HT1; red in HT1. remember (observe (vis e k1)).
      hinduction HT1 before k; intros; inv Heqi; try inv CHECK.
      dependent destruction H1. unfold subevent.
      eapply eqit_Vis.
      Unshelve.
      intros. cbn.
      eapply eq_itree_clo_bind; pclearbot; eauto.
      apply REL.
      intros; subst; reflexivity.
    - eapply Interp_PropT_Vis; eauto.
      intros; eauto. right. eapply CIH; eauto.
      specialize (HK0 _ H1). pclearbot. eapply HK0; eauto.
      rewrite <- unfold_bind.
      setoid_rewrite <- Eqit.bind_bind.
      eapply eutt_clo_bind; eauto. intros; eauto.
      subst; reflexivity.
  Qed.

  (* If

    - ti2 is a refinement of ti1 tf2 refines ti2 tf1 refines tf2 at
    - finite level

    Not sure that this is true.

    If ti1 -i> ti2

    and ti2 -if> tf2

    And tf2 -f> tf1...

    Does it really follow that ti1 -if> tf1?

    In theory I can refine ti1 to ti2, and to tf1 through
    tf2... BUT... Does this mean I can refine ti1 directly to tf1?

    In theory ti2 has fewer behaviours than ti1, and so if I can
    refine it to tf2, then I can also refine ti1 to tf2.
   *)
  Lemma refine_E1E2_L6_strict_compose_inf_to_fin :
    forall tx ty tz,
      TLR_INF.R.refine_L6 tx ty ->
      refine_E1E2_L6_strict ty tz ->
      refine_E1E2_L6_strict tx tz.
  Proof.
    intros tx ty tz XY_INF YZ_FIN.

    unfold refine_E1E2_L6_strict in *.
    unfold TLR_INF.R.refine_L6 in *.
    unfold TLR_FIN.R.refine_L6 in *.

    intros rz TZ.
    specialize (YZ_FIN rz TZ).
    destruct YZ_FIN as (ry_fin & TY_FIN & YZ).

    unfold L6_convert_PropT_strict in TY_FIN.
    destruct TY_FIN as (ry_inf & TY_INF & ry_fin_inf).

    specialize (XY_INF ry_inf TY_INF).
    destruct XY_INF as (rx_inf & TX_INF & XY_INF).

    set (rx_fin := L4_convert_tree_strict' res_L6_convert_strict_unsafe rx_inf).
    exists rx_fin.
    split.
    - unfold L6_convert_PropT_strict, L4_convert_PropT_strict.
      exists rx_inf; split; auto.
      subst rx_fin.
      reflexivity.
    - rewrite <- YZ.
      rewrite <- ry_fin_inf.
      subst rx_fin.

      (* There's probably a more general lemma hiding here *)
      unfold L4_convert_tree_strict'.

      Unset Universe Checking.
      eapply refine_OOM_h_bind with (RR1:=TopLevelRefinementsBigIntptr.R.refine_res3).
      { intros r1 r2 H.
        unfold TLR_INF.R.refine_res3, TLR_INF.R.refine_res2, TLR_INF.R.refine_res1 in H.
        destruct r1 as [r1a [r1sid [[r1b1 r1b2] [r1c dv1]]]].
        destruct r2 as [r2a [r2sid [[r2b1 r2b2] [r2c dv2]]]].
        cbn.

        inversion H; subst.
        inversion snd_rel; subst.
        inversion snd_rel0; subst.
        inversion snd_rel1; subst.
        cbn in *; subst; reflexivity.
      }
      { apply refine_OOM_h_L6_convert_tree_strict; auto.
      }
  Qed.

  Lemma refine_E1E2_L6_strict_compose_fin_to_inf :
    forall tx ty tz,
      refine_E1E2_L6_strict tx ty ->
      TLR_FIN.R.refine_L6 ty tz ->
      refine_E1E2_L6_strict tx tz.
  Proof.
    intros tx ty tz XY_INF_TO_FIN YZ_FIN.

    unfold refine_E1E2_L6_strict in *.
    unfold TLR_INF.R.refine_L6 in *.
    unfold TLR_FIN.R.refine_L6 in *.

    intros rz TZ.
    specialize (YZ_FIN rz TZ).
    destruct YZ_FIN as (ry_fin & TY_FIN & YZ).

    specialize (XY_INF_TO_FIN ry_fin TY_FIN).
    destruct XY_INF_TO_FIN as (rx_fin & TX_FIN & refine_inf_fin_x).

    exists rx_fin.
    split; auto.
    rewrite refine_inf_fin_x; auto.
  Qed.

  Theorem refine_E1E2_L6_transitive :
    forall ti1 ti2 tf1 tf2,
      TLR_INF.R.refine_L6 ti1 ti2 ->
      refine_E1E2_L6_strict ti2 tf1 ->
      TLR_FIN.R.refine_L6 tf1 tf2 ->
      refine_E1E2_L6_strict ti1 tf2.
  Proof.
    intros ti1 ti2 tf1 tf2 RINF RITOF RFIN.

    eapply refine_E1E2_L6_strict_compose_fin_to_inf; eauto.
    eapply refine_E1E2_L6_strict_compose_inf_to_fin; eauto.
  Qed.

  (** Safe conversion lemmas *)
  (* TODO: These used the Fin to Inf LangRefine that no longer exists
     because we added safe conversion modules... See if I still need
     these *)
  (* Lemma infinite_to_finite_dvalue_convert_safe : *)
  (*   forall dv_i, *)
  (*   exists dv_f, *)
  (*     EC1.DVC.dvalue_convert_strict dv_i = NoOom dv_f /\ *)
  (*       EC2.DVC.dvalue_convert_strict dv_f = NoOom dv_i. *)
  (* Proof. *)
  (*   intros dv_i. *)

  (*   rewrite EC1.DVC.dvalue_convert_equation. *)
  (*   destruct dv_i. *)
  (*   - (* Addresses *) *)

  (*   setoid_rewrite EC2.DVC.dvalue_convert_equation. *)

  (*   (* TODO: Ugh, everything is opaque. Fix and prove. *) *)
  (* Admitted. *)

  (* Lemma L0_convert_safe : *)
  (*   forall t, *)
  (*     InfFinTC.L0_convert_tree' EC1.DVC.dvalue_convert *)
  (*       (FinInfTC.L0_convert_tree' EC2.DVC.dvalue_convert t) ≈ t. *)
  (* Proof. *)
  (*   intros t. *)
  (*   unfold InfFinTC.L0_convert_tree', InfFinTC.L0_convert_tree. *)
  (*   unfold FinInfTC.L0_convert_tree', FinInfTC.L0_convert_tree. *)
  (*   cbn. *)
  (*   setoid_rewrite interp_bind. *)
  (*   rewrite bind_bind. *)
  (*   rewrite interp_interp. *)


  (*   cbn. *)
  (*   red. *)
  (* Admitted. *)

  (** Refinement lemmas *)
  Lemma refine_E1E2_L0_strict_interp_intrinsics :
    forall t1 t2,
      refine_E1E2_L0_strict t1 t2 ->
      refine_E1E2_L0_strict (InfLLVM.Intrinsics.interp_intrinsics t1) (FinLLVM.Intrinsics.interp_intrinsics t2).
  Proof.
    intros t1 t2 RL0.
    red in RL0.
    destruct RL0 as [t1' [OOM_T1 RL0]].
    red in RL0.
    red.
    exists (FinInfTC.L0_convert_tree_strict' EC2.DVC.dvalue_convert (FinLLVM.Intrinsics.interp_intrinsics t2)).
    split.
    - assert ((FinInfTC.L0_convert_tree' EC2.DVC.dvalue_convert (FinLLVM.Intrinsics.interp_intrinsics t2)) ≈  (FinInfTC.L0_convert_tree' EC2.DVC.dvalue_convert (LLVM.Intrinsics.interp_intrinsics (InfFinTC.L0_convert_tree' EC1.DVC.dvalue_convert t1')))) as EQT2.
      { eapply @FinInfTC.L0_convert_tree'_eutt_proper with (RA:=eq).
        intros u1 u2 H; subst.
        reflexivity.

        rewrite RL0.
        reflexivity.
      }

      rewrite EQT2.

      eapply refine_OOM_h_transitive with (y:=(InfLLVM.Intrinsics.interp_intrinsics t1')); try typeclasses eauto.
      (* May hold... OOM_T1 *)
      admit.

      red.
      red.
      (* This might actually be provable by walking through t1'?

         The conversions may cause early OOM, but otherwise preserves
         the event structure.
       *)
      admit.
    - red.
      (* This can't hold unless I know converting from E2 -> E1 -> E2
         is "safe" and doesn't cause any OOM.

         This should be the case for the particular Inf / Fin case we
         care about, though.
       *)
      rewrite L0_convert_safe.
      reflexivity.
  Admitted.

  Lemma refine_E1E2_interp_global :
    forall t1 t2 g1 g2,
      refine_E1E2_L0 t1 t2 ->
      global_refine g1 g2 ->
      refine_E1E2_L1 (interp_global t1 g1) (interp_global t2 g2).
  Proof.
    intros t1 t2 g1 g2 RL0 GENVS.
    red in RL0.
    destruct RL0 as [t1' [OOM_T1 RL0]].
    red.

    (* Perhaps I need a lemma about L1_convert_tree and interp_global here? *)
  Admitted.

  Lemma refine_E1E2_interp_local_stack :
    forall t1 t2 ls1 ls2,
      refine_E1E2_L1 t1 t2 ->
      local_stack_refine ls1 ls2 ->
      refine_E1E2_L2 (interp_local_stack t1 ls1) (interp_local_stack t2 ls2).
  Proof.
  Admitted.

  (* Most of these are aliases of the above, but some levels of the interpreter interpret more than one event *)
  Lemma refine_E1E2_01 :
    forall t1 t2 g1 g2,
      refine_E1E2_L0 t1 t2 ->
      global_refine g1 g2 ->
      refine_E1E2_L1 (interp_global (InfLLVM.Intrinsics.interp_intrinsics t1) g1) (interp_global (FinLLVM.Intrinsics.interp_intrinsics t2) g2).
  Proof.
    intros t1 t2 g1 g2 RL0 GENVS.
    red in RL0.
    apply refine_E1E2_interp_global; auto.
    apply refine_E1E2_L0_interp_intrinsics; auto.
  Qed.

  Lemma refine_E1E2_12 :
    forall t1 t2 l1 l2,
      refine_E1E2_L1 t1 t2 ->
      local_stack_refine l1 l2 ->
      refine_E1E2_L2 (interp_local_stack t1 l1) (interp_local_stack t2 l2).
  Proof.
    intros t1 t2 g1 g2 RL1 GENVS.
    red in RL1.
    apply refine_E1E2_interp_local_stack; auto.
  Qed.

  Import InterpMemoryProp.
  Lemma refine_E1E2_23 :
    forall t1 t2 sid m1 m2,
      refine_E1E2_L2 t1 t2 ->
      MemState_refine m1 m2 ->
      refine_E1E2_L3 (InfMemInterp.interp_memory_prop eq t1 sid m1) (FinMemInterp.interp_memory_prop eq t2 sid m2).
  Proof.
    intros t1 t2 sid m1 m2 RL2.

  (*
    h1 and h2 are handlers

    (* h2 refines h1 *)
    (forall e,
    refine_E1E2_L3 (h1 e) (h2 e)) ->
    forall u : itree,
    refine_E1E2_L3 (interp_prop h1 u) (interp_prop h2 u)

    Need something a bit more general like rutt.

    (forall e1 e2,
    refine_events e1 e2 ->
    refine_E1E2_L3 (h1 e1) (h2 e2)) ->
    forall u1 u2 : itree,
    rutt refine_events refine_dvalue eq u1 u2 ->
    refine_E1E2_L3 (interp_prop h1 u1) (interp_prop h2 u2)


    (forall e1 e2,
    refine_events e1 e2 ->
    refine_E1E2_L4 (h1 e1) (h2 e2)) ->
    forall u1 u2 : itree,
    refine_E1E2_L3 u1 u2 ->
    refine_E1E2_L4 (interp_prop h1 u1) (interp_prop h2 u2)

   *)

    (* I'll probably need something about MemMonad_valid_state eventually... *)
  Admitted.

  Lemma refine_E1E2_34 :
    forall t1 t2,
      refine_E1E2_L3 t1 t2 ->
      refine_E1E2_L4 (InfLLVM.Pick.model_undef eq t1) (FinLLVM.Pick.model_undef eq t2).
  Proof.
    intros t1 t2 RL3.
    red.
  Admitted.

  Lemma refine_E1E2_45 :
    forall t1 t2,
      refine_E1E2_L4 t1 t2 ->
      refine_E1E2_L5 (model_UB t1) (model_UB t2).
  Proof.
    intros t1 t2 RL4.
    red.
  Admitted.

  Lemma refine_E1E2_56 :
    forall t1 t2,
      refine_E1E2_L5 t1 t2 ->
      refine_E1E2_L6 (refine_OOM eq t1) (refine_OOM eq t2).
  Proof.
    intros t1 t2 RL4.
    red.
  Admitted.


  From Vellvm Require Import Tactics.

  From ITree Require Import
        ITree
        Basics.Monad
        Events.StateFacts
        Eq.Eqit.

  Import TranslateFacts.
  Import TopLevelBigIntptr.
  Import TopLevel64BitIntptr.
  Import InterpreterStackBigIntptr.
  Import TopLevelRefinements64BitIntptr.

  Ltac force_rewrite H :=
    let HB := fresh "HB" in
    pose proof @H as HB; eapply bisimulation_is_eq in HB; rewrite HB; clear HB.

  Tactic Notation "force_rewrite" constr(H) "in" hyp(H') :=
    let HB := fresh "HB" in
    pose proof @H as HB; eapply bisimulation_is_eq in HB; rewrite HB in H'; clear HB.


  (* TODO: this is going to be a big one *)
  Theorem model_E1E2_L0_sound :
    forall (p : LLVM_syntax),
      model_E1E2_L0 p p.
  Proof.
    intros p.
    unfold model_E1E2_L0.
    red.
    unfold refine_L0.
    unfold L0_convert_tree'.
    unfold L0_convert_tree.

    exists (FinInfTC.L0_convert_tree' EC2.DVC.dvalue_convert
         (denote_vellvm (DynamicTypes.DTYPE_I 32) "main" main_args
            (TypToDtyp.convert_types (CFG.mcfg_of_tle p)))).

    split.
    - (* src' may have additional OOM *)
      (* I think this pretty much has to be by induction over the syntax? *)
      admit.
    - (* src' when converted agrees with target *)
      (* Target may just be OOM for all we know *)
      red.
      setoid_rewrite L0_convert_safe.
      reflexivity.
  Admitted.

  Theorem model_E1E2_L1_sound :
    forall (p : LLVM_syntax),
      model_E1E2_L1 p p.
  Proof.
    intros p.
    red.

  (* Maybe I need some lemmas akin to these:

    Lemma refine_34 : forall t1 t2,
        refine_L3 t1 t2 -> refine_L4 (model_undef refine_res3 t1) (model_undef refine_res3 t2).

    But for crossing the infinite / finite boundary...

   *)
    unfold model_oom_L1.
    unfold model_gen_oom_L1.
    unfold interp_mcfg1.

    apply refine_E1E2_01.
    { (* Still need to deal with interp_intrinsics... *)
      apply model_E1E2_L0_sound.
    }

    apply global_refine_empty.
  Qed.

  Theorem model_E1E2_L2_sound :
    forall (p : LLVM_syntax),
      model_E1E2_L2 p p.
  Proof.
    intros p.
    red.
    apply refine_E1E2_12; [| apply local_stack_refine_empty].
    apply model_E1E2_L1_sound.
  Qed.

  Theorem model_E1E2_L3_sound :
    forall (p : LLVM_syntax),
      model_E1E2_L3 p p.
  Proof.
    intros p.
    red.
    apply refine_E1E2_23; [| apply MemState_refine_initial].
    apply model_E1E2_L2_sound.
  Qed.

  Theorem model_E1E2_L4_sound :
    forall (p : LLVM_syntax),
      model_E1E2_L4 p p.
  Proof.
    intros p.
    red.
    apply refine_E1E2_34.
    apply model_E1E2_L3_sound.
  Qed.

  Theorem model_E1E2_L5_sound :
    forall (p : LLVM_syntax),
      model_E1E2_L5 p p.
  Proof.
    intros p.
    red.
    apply refine_E1E2_45.
    apply model_E1E2_L4_sound.
  Qed.

  Theorem model_E1E2_L6_sound :
    forall (p : LLVM_syntax),
      model_E1E2_L6 p p.
  Proof.
    intros p.
    red.
    apply refine_E1E2_56.
    apply model_E1E2_L5_sound.
  Qed.

End InfiniteToFinite.
