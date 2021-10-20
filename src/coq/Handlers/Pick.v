(* begin hide *)
From Coq Require Import
     ZArith
     String
     List
     Lia.

From ExtLib Require Import
     Structures.Monads
     Structures.Maps.

From ITree Require Import
     ITree
     Eq.Eq
     Events.State.

From Vellvm Require Import
     Utils.Error
     Utils.Util
     Utils.PropT
     Syntax.LLVMAst
     Syntax.AstLib
     Syntax.DynamicTypes
     Syntax.DataLayout
     Semantics.DynamicValues
     Semantics.MemoryAddress
     Semantics.GepM
     Semantics.Memory.Sizeof
     Semantics.Memory.MemBytes
     Semantics.LLVMEvents
     Handlers.Serialization.

Require Import List.
Require Import Floats.

Set Implicit Arguments.
Set Contextual Implicit.

Import MonadNotation.
(* end hide *)

(** * Pick handler
  Definition of the propositional and executable handlers for the [Pick] event.
  - The propositional one capture in [Prop] all possible values
  - The executable one interprets [undef] as 0 at the type
*)

Module Make(A:MemoryAddress.ADDRESS)(IP:MemoryAddress.INTPTR)(SIZEOF: Sizeof)(LLVMIO: LLVM_INTERACTIONS(A)(IP)(SIZEOF))(PTOI:PTOI(A))(PROVENANCE:PROVENANCE(A))(ITOP:ITOP(A)(PROVENANCE))(GEP:GEPM(A)(IP)(SIZEOF)(LLVMIO))(BYTE_IMPL : ByteImpl(A)(IP)(SIZEOF)(LLVMIO)).

  Module Conc := Serialization.Make A IP SIZEOF LLVMIO PTOI PROVENANCE ITOP GEP BYTE_IMPL.
  Import Conc.
  Import LLVMIO.

  Section PickPropositional.

    (* The parameter [C] is currently not used *)
    Inductive Pick_handler {E} `{FE:FailureE -< E} `{FO:UBE -< E} `{OO: OOME -< E}: PickE ~> PropT E := 
    | PickD: forall uv C res t,  concretize_u uv res -> t ≈ (lift_err_ub_oom ret res) -> Pick_handler (pick uv C) t.

    Section PARAMS_MODEL.
      Variable (E F: Type -> Type).

      Definition E_trigger_prop : E ~> PropT (E +' F) :=
        fun R e => fun t => t = r <- trigger e ;; ret r.

      Definition F_trigger_prop : F ~> PropT (E +' F) :=
        fun R e => fun t => t = r <- trigger e ;; ret r.

      Definition model_undef `{FailureE -< E +' F} `{UBE -< E +' F} `{OOME -< E +' F} :
        forall (T:Type) (RR: T -> T -> Prop), itree (E +' PickE +' F) T -> PropT (E +' F) T :=
        interp_prop (case_ E_trigger_prop (case_ Pick_handler F_trigger_prop)).

    End PARAMS_MODEL.

  End PickPropositional.

  Section PickImplementation.

    Open Scope N_scope.

    Import MonadNotation.

   Transparent map_monad.
   Lemma concretize_u_concretize_uvalue : forall u, concretize_u u (concretize_uvalue u).
    Proof.
      (* intros u. *)
      (* induction u; try do_it. *)
      (* - (* cbn. *) (* destruct (default_dvalue_of_dtyp t) eqn: EQ. *) *)
    (*     econstructor. Unshelve. 3 : { exact DVALUE_None. } *)
    (*     intro. inv H. *)
    (*     apply Concretize_Undef. apply dvalue_default. symmetry. auto. *)
    (*   - cbn. induction fields. *)
    (*     + cbn. constructor. auto. *)
    (*     + rewrite list_cons_app. rewrite map_monad_app. cbn. *)
    (*       assert (IN: forall u : uvalue, In u fields -> concretize_u u (concretize_uvalue u)). *)
    (*       { intros. apply H. apply in_cons; auto. } specialize (IHfields IN). *)
    (*       specialize (H a). assert (In a (a :: fields)) by apply in_eq. specialize (H H0). *)
    (*       pose proof Concretize_Struct_Cons as CONS. *)
    (*       specialize (CONS _ _ _ _ H IHfields). cbn in CONS. *)
    (*       * destruct (unEitherT (concretize_uvalue a)). *)
    (*         -- auto. *)
    (*         -- destruct s; auto. *)
    (*            destruct (unEitherT (map_monad concretize_uvalue fields)); auto. *)
    (*            destruct s; auto. *)
    (*   - cbn. induction fields. *)
    (*     + cbn. constructor. auto. *)
    (*     + rewrite list_cons_app. rewrite map_monad_app. cbn. *)
    (*       assert (IN: forall u : uvalue, In u fields -> concretize_u u (concretize_uvalue u)). *)
    (*       { intros. apply H. apply in_cons; auto. } specialize (IHfields IN). *)
    (*       specialize (H a). assert (In a (a :: fields)) by apply in_eq. specialize (H H0). *)
    (*       pose proof Concretize_Packed_struct_Cons as CONS. *)
    (*       specialize (CONS _ _ _ _ H IHfields). cbn in CONS. *)
    (*       * destruct (unEitherT (concretize_uvalue a)). *)
    (*         -- auto. *)
    (*         -- destruct s; auto. *)
    (*            destruct (unEitherT (map_monad concretize_uvalue fields)); auto. *)
    (*            destruct s; auto. *)
    (*   - cbn. induction elts. *)
    (*     + cbn. constructor. auto. *)
    (*     + rewrite list_cons_app. rewrite map_monad_app. cbn. *)
    (*       assert (IN: forall u : uvalue, In u elts -> concretize_u u (concretize_uvalue u)). *)
    (*       { intros. apply H. apply in_cons; auto. } specialize (IHelts IN). *)
    (*       specialize (H a). assert (In a (a :: elts)) by apply in_eq. specialize (H H0). *)
    (*       pose proof Concretize_Array_Cons as CONS. *)
    (*       specialize (CONS _ _ _ _ H IHelts). cbn in CONS. *)
    (*       * destruct (unEitherT (concretize_uvalue a)). *)
    (*         -- auto. *)
    (*         -- destruct s; auto. *)
    (*            destruct (unEitherT (map_monad concretize_uvalue elts)); auto. *)
    (*            destruct s; auto. *)
    (*   - cbn. induction elts. *)
    (*     + cbn. constructor. auto. *)
    (*     + rewrite list_cons_app. rewrite map_monad_app. cbn. *)
    (*       assert (IN: forall u : uvalue, In u elts -> concretize_u u (concretize_uvalue u)). *)
    (*       { intros. apply H. apply in_cons; auto. } specialize (IHelts IN). *)
    (*       specialize (H a). assert (In a (a :: elts)) by apply in_eq. specialize (H H0). *)
    (*       pose proof Concretize_Vector_Cons as CONS. *)
    (*       specialize (CONS _ _ _ _ H IHelts). cbn in CONS. *)
    (*       * destruct (unEitherT (concretize_uvalue a)). *)
    (*         -- auto. *)
    (*         -- destruct s; auto. *)
    (*            destruct (unEitherT (map_monad concretize_uvalue elts)); auto. *)
    (*            destruct s; auto. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
    (*   - cbn; apply (Pick_fail (v := DVALUE_None)); intro H'; inv H'. *)
        (* Qed. *)
    Admitted.

    Definition concretize_picks {E} `{FailureE -< E} `{UBE -< E} `{OOME -< E} : PickE ~> itree E :=
      fun T p => match p with
              | pick u P => lift_err_ub_oom ret (concretize_uvalue u)
              end.

    Section PARAMS_INTERP.
      Variable (E F: Type -> Type).

      Definition E_trigger :  E ~> itree (E +' F) :=
        fun R e => r <- trigger e ;; ret r.

      Definition F_trigger : F ~> itree (E +' F) :=
        fun R e => r <- trigger e ;; ret r.

      Definition exec_undef `{FailureE -< E +' F} `{UBE -< E +' F} `{OOME -< E +' F} :
        itree (E +' PickE +' F) ~> itree (E +' F) :=
        interp (case_ E_trigger
               (case_ concretize_picks F_trigger)).

    End PARAMS_INTERP.

  End PickImplementation.

End Make.
