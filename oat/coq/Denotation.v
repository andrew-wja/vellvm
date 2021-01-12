Require Import List.

From Coq Require Import
     ZArith
     List
     String
     Setoid
     Morphisms
     Omega
     Classes.RelationClasses
     Init.Datatypes
     Program.Basics
.

From ITree Require Import
     ITree
     ITreeFacts
     Interp
     Interp.Recursion
     Events.MapDefault
     Events.StateFacts
     Events.Exception
.

From ExtLib Require Import
     Core.RelDec
     Programming.Eqv
     Structures.Monads
     Structures.Maps
     Data.Map.FMapAList
     Data.String
.

From Vellvm Require Import Util Error.
From Oat Require Import
     Ast
     DynamicValues
     OatEvents
     Handlers.

Import MonadNotation.
Local Open Scope monad_scope.
Local Open Scope string_scope.
Local Open Scope program_scope.
Module Int64 := Integers.Int64.
Definition int64 := Int64.int.

(******************************* Oat Semantics *******************************)
(**
   We'll finally start writing down how OAT should work! To begin, we'll
   write down OAT semantics in terms of itrees / how an OAT program should
   be interpreted.
*)

Set Implicit Arguments.
Set Contextual Implicit.
Definition expr := Oat.Ast.exp.
Definition stmt := Oat.Ast.stmt.
Definition unop := Oat.Ast.unop.
Definition binop := Oat.Ast.binop.
Definition vdecl := Oat.Ast.vdecl.

(* Denote the semantics for binary operations *)

Definition neq (x y : int64) : bool :=
  negb (Int64.eq x y).

Definition lte (x y : int64) : bool :=
  Int64.eq x y || Int64.lt x y.

Definition gt (x y : int64) : bool :=
  negb (lte x y).

Definition gte (x y : int64) : bool :=
  negb (Int64.lt x y).


Definition denote_uop (u: unop) (v: ovalue) : itree OatE ovalue :=
  match u,v with
  | Neg,    OVALUE_Int i => ret (OVALUE_Int (Int64.neg i))
  | Lognot, OVALUE_Bool b => ret (OVALUE_Bool (negb b))
  | Bitnot, OVALUE_Int i => ret (OVALUE_Int (Int64.not i))
  | _, _ => raise "err: incompatible types for unary operand"
  end.


(* Denote basic bop and uop *)
Definition denote_bop (op: binop) (v1 v2 : ovalue) : itree OatE ovalue :=
  match op, v1, v2 with
  (* Integer arithmetic *)
  | Oat.Ast.Add, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int (Int64.add l r))
  | Sub, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int(Int64.sub l r))
  | Mul, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int(Int64.mul l r))
  (* Integer comparison *)
  | Eq, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Bool (Int64.eq l r))
  | Neq, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Bool (neq l r))
  | Lt, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Bool (Int64.lt l r))
  | Lte, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Bool (lte l r))
  | Gt, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Bool (gt l r))
  | Gte, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Bool (gte l r))
  (* Integer bitwise arithmetic *)
  | IAnd, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int (Int64.and l r))
  | IOr, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int (Int64.or l r))
  | Shl, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int (Int64.shl l r))
  | Shr, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int (Int64.shru l r))
  | Sar, OVALUE_Int l, OVALUE_Int r => ret (OVALUE_Int (Int64.shr l r))
  (* Boolean operations *)
  | And, OVALUE_Bool l, OVALUE_Bool r => ret (OVALUE_Bool (l && r))
  | Or, OVALUE_Bool l, OVALUE_Bool r => ret (OVALUE_Bool (l || r))
  | _, _, _ => raise "err: incompatible types for binary operand"
 end.

Definition fcall_return_or_fail (id: expr) (args: list ovalue) : itree OatE ovalue :=
  match id with
  | Id i => trigger (OCall i args)
  | _ => raise "err: can't call a thing that's not a func!"
  end.

(* Now we can give an ITree semantics for the expressions in oat *)
Check map_monad.
Check Z.to_nat.
Check Z.of_nat.
About Int64.
Print Int64.
About Int64.signed.

Definition default_initialization (t : ty) : ovalue :=
  match t with
  | TBool => OVALUE_Bool true
  | TInt => OVALUE_Int (Int64.repr (0%Z))
  | TRef _ 
  (** VV: TODO - what behaviour should default initializing a non-null ref array have? *)
  | TNotNullRef _ => OVALUE_Ref (REF_Null)
  end.

Fixpoint denote_expr (e: expr) : itree OatE ovalue :=
  match e with
  (** Initialization of values *)
  | CNull _ => ret (OVALUE_Ref (REF_Null))
  | CBool b => ret (OVALUE_Bool b)
  | CInt i => ret (OVALUE_Int i)
  | CStr s => ret (OVALUE_Str s)
  | CArr ts init =>
    args <- map_monad (fun e => denote_expr (elt expr e)) init ;;
    ret (OVALUE_Ref (REF_Array args))
  | CStruct id init =>   
    args <- map_monad
              (fun '(fieldName, e) => (v <- denote_expr (elt expr e) ;; ret (fieldName, v))) init ;;
    ret (OVALUE_Ref (REF_Struct id args))
  | NewArr t n =>
    length_val <- denote_expr (elt expr n) ;;
    match length_val with
      | OVALUE_Int i =>
        if lte i Int64.zero then raise "err: Cannot initialize array of length < 0"
        else 
          let idx := Z.to_nat (Int64.signed i ) in
          let def_v := default_initialization t in
          ret (OVALUE_Ref (REF_Array (List.repeat def_v idx) ))
      | _ => raise "err: Cannot use non-integer value as a length initialization argument"
    end   
      
  (** Lookup of values *)
  | Id i => trigger (OEnvRead i)
                    
  (** Binary operators *)
  | Uop op n =>
    let e' := elt_of n in
    v <- denote_expr e' ;;
    denote_uop op v
  | Bop op l_exp r_exp =>
    let l := elt_of l_exp in
    let r := elt_of r_exp in
    l' <- denote_expr l;;
    r' <- denote_expr r;;
    denote_bop op l' r' 
               
  (** Function calls *)
  | Call f args =>
    let f_id := elt expr f in
    args' <- map_monad ( fun e => denote_expr (elt expr e)) args ;;
    f_ret <- fcall_return_or_fail f_id args';;
    match f_ret with
    | OVALUE_Void => raise "err: using a void function call in an expression"
    | _ => ret f_ret
    end

  (** Projection out of a struct: e_struct.fieldName *)
  | Proj e_struct fieldName =>
    struct' <- denote_expr (elt expr e_struct) ;;
    match struct' with
    | OVALUE_Ref (REF_Struct structType elts) =>
      match Maps.lookup fieldName elts with
        | None => raise ("err: Cannot find field " ++ fieldName ++ " in struct type " ++ structType)
        | Some v => ret v
      end
    | _ => raise "err: Cannot project a field out of a non-struct"
    end
      
  (** Indexing into an array: n_arr[n_idx]*)
  | Index n_arr n_idx =>
    e_arr <- denote_expr (elt expr n_arr) ;;
    e_idx <- denote_expr (elt expr n_idx) ;;
    match e_arr with
    | OVALUE_Ref (REF_Array elts) =>
      match e_idx with
      | OVALUE_Int i =>
        let nat_idx := Z.to_nat (Int64.signed i) in
        match List.nth_error elts nat_idx with
          | None => raise "err: Array Index Out of Bounds Exception"
          | Some v => ret v
        end
      | _ => raise "err: Cannot use non-integer as an index"
      end
    | _ => raise "err: Cannot index into a non-array value"
    end

  (** Length of an array: n_arr.length *)
  | Length n_arr =>
    e_arr <- denote_expr (elt expr n_arr) ;;
    match e_arr with
    | OVALUE_Ref (REF_Array elts) =>
      ret (OVALUE_Int
             (Int64.repr (Z.of_nat (List.length elts)))
          )
    | _ => raise "err: Cannot take the length of a non-array value" 
    end
  end.

(** I'll define some convenient helpers for common things like looping and sequencing here *)
Definition seq {T : Type } (l : list (node stmt)) (f : stmt -> itree OatE (unit + T)) : itree OatE (unit + T) :=
  let base : itree OatE (unit + T) := ret (inl tt) in
  let combine : itree OatE (unit + T)
                -> node stmt
                -> itree OatE (unit + T)
      := fun acc hd =>
           v <- f (elt stmt hd) ;;
           ( match v with | inl _ => acc | inr v => ret (inr v) end )
  in 
  List.fold_left (combine) (l) (base).

Definition stmt_t : Type := unit + ovalue.
Definition cont_stmt : Type := unit + stmt_t.

Definition while (step : itree OatE (unit + stmt_t)) : itree OatE stmt_t :=
  iter (C := Kleisli _) (fun _ => step) (tt).

(* while combinator: inl unit *)

Definition end_loop : itree OatE (unit + stmt_t) := ret (inr (inl tt)).
Definition cont_loop_silent : itree OatE (unit + stmt_t) := ret (inl tt). 
Definition cont_loop_end : ovalue -> itree OatE (unit + stmt_t)
  := fun v => ret (inr (inr v)).

 Definition for_loop_pre (decl: list vdecl) : itree OatE unit :=
  _ <- (map_monad (fun vdec =>
                     let e := denote_expr (elt expr (snd vdec)) in
                     v <- e ;;
                     trigger (OLocalWrite (fst vdec) v) ) decl) ;;
  ret tt.

(** Finally, we can start to denote the meaning of Oat statements *)
About inl.
Definition lift_eff {T} (t: itree OatE T) : itree OatE (unit + T) :=
 t' <- t ;; ret (inr t').   

Fixpoint denote_stmt (s : stmt) : itree OatE (unit + ovalue) :=
  match s with
  | Assn target source =>
    let tgt := elt_of target in
    let src := elt_of source in
    match tgt with
    | Id i =>
      v <- denote_expr src ;;
      trigger (OLocalWrite i v) ;;
      ret (inl tt)
    | _ => raise "err: assignment to a non variable target"
    end
  | Return e =>
    match e with
    | None => ret (inr OVALUE_Void)
    | Some r =>
      rv <- denote_expr (elt expr r) ;;
      ret (inr rv)
    end
  | Decl (id, node) =>
    let src := elt_of node in
    v <- denote_expr src ;;
    trigger (OLocalWrite id v) ;;
    ret (inl tt)
  | If cond p f =>
    (* Local function  *)
    let e_cond := elt expr cond in
    exp <- denote_expr e_cond ;;
    match exp with
      | OVALUE_Bool bv => 
        if bv then seq p denote_stmt else seq f denote_stmt
      | _ => raise "err"
    end
  | While cond stmts =>
    while (
        x <- denote_expr (elt expr cond) ;;
        match x with
        | OVALUE_Bool bv =>
          if bv then lift_eff (seq stmts denote_stmt) else end_loop
        | _ => raise "err"
        end)
  | SCall invoke args => 
    let f_id := elt expr invoke in
    args' <- map_monad ( fun e => denote_expr (elt expr e)) args ;;
    _ <- fcall_return_or_fail f_id args';;
    ret (inl tt)
  | Cast rt bound possibly_null p f =>
    e_pn <- denote_expr (elt expr possibly_null) ;;
    match e_pn with
    | OVALUE_Ref (REF_Null) =>
      seq f denote_stmt
    | OVALUE_Ref _ => 
    (* Otherwise, the value is non-null - add it to the environment and then run the 
       success block
     *)
      trigger (OLocalWrite bound e_pn) ;;
      seq p denote_stmt
    | _ => raise "err: Cannot perform checked downcast on a non-reference type"
    end
  | _ => raise "unimplemented"
  end.

(** VV: Enforcing the fact that a block must terminate in either a void(OVALUE_Void) | concrete return type *) 

(**
   Without any fancy analysis the block:
   stmt1;
   stmt2;
   return 3;
   stmt_4;
   stmt_5;
   ....
   could either be interpreted as an early return statement, where the
   denotation of later blocks stops | denote everything.
   | with some basic analysis we could enforce one terminator only and raise an error ow...
*)
(* Todo - rewrite with fold_left *)
Fixpoint denote_block_acc
         (denoted: itree OatE (unit + ovalue))
         (blk: block) : itree OatE ovalue :=
  match blk with
  | nil =>
    v <- denoted ;;
    match v with
    | inl _ =>
    (* denoting the block was a unit - implicitly insert a void return *)
      ret (OVALUE_Void)
    | inr v => ret v
    end
  | h :: t => denote_block_acc (denoted ;; denote_stmt (elt stmt h)) t
  end.


Definition denote_block (b : block) : itree OatE ovalue
  := denote_block_acc (ret (inl tt)) b.

(** Globals! *)
Check map_monad.
Check undef_or_err.
Print undef_or_err.
Print eitherT.
About eitherT.
About map_monad.
Definition denote_gdecl (decl: Ast.gdecl) : itree OatE unit
  :=
    let id := name decl in
    let e : Ast.exp := elt expr (init decl) in
    match e with
    | CNull _ => trigger (OGlobalWrite id (OVALUE_Ref REF_Null))
    | CBool b => trigger (OGlobalWrite id (OVALUE_Bool b))
    | CInt i => trigger (OGlobalWrite id (OVALUE_Int i))
    | CStr s => trigger (OGlobalWrite id (OVALUE_Str s))
    | Id i =>
      v <- denote_expr e ;;
      trigger (OGlobalWrite id v)
    | CArr ts init =>
      v <- denote_expr e ;;
      trigger (OGlobalWrite id v)
    | CStruct id init =>   
      v <- denote_expr e ;;
      trigger (OGlobalWrite id v)
    | _ => raise "err: Not a valid global initializer"
    end.

Definition translate_gdecl_OatE' {V} (dec : itree OatE V) : _ :=
  interp_mrec (fun T call => raise "Should not be invoking functions as global inits")
              (D := OCallE)
              (E := OatE') dec.

Definition fdecl_denotation : Type :=
  list ovalue -> itree OatE ovalue. 

Fixpoint combine_lists_err
         {A B : Type}
         (l1 : list A)
         (l2 : list B) : err (list (A * B)) :=
  match l1, l2 with
  | nil, nil => ret nil
  | cons x xs, cons y ys =>
    l <- combine_lists_err xs ys ;;
    ret (cons (x,y) l)
  | _, _ => ret []
  end.

(** Same tactic as from src/coq/Semantics/Denotation.v *)
Definition function_denotation : Type :=
  list ovalue -> itree OatE ovalue.

Definition denote_fdecl (df : fdecl) : function_denotation :=
  fun (arg: list ovalue) => 
    let a : err (list (id * ovalue)) := combine_lists_err (List.map snd (args df)) arg in
    let b : list (id * ovalue) -> itree OatE (list (id * ovalue)) := ret in 
    let c : itree OatE (list (id * ovalue)) := lift_err b a in
    let d : ovalue -> itree OatE ovalue := fun v => ret v in
    let f : (list (id * ovalue)) -> itree OatE unit :=
        fun bs => trigger (OStackPush ( bs ) ) in
    let f' : (list (id * ovalue)) -> itree OatE unit := fun args => trigger (OStackPop args) in
    bs <- c ;;
    trigger (OStackPush bs);;
    rv <- denote_block (body df) ;;
    trigger (OStackPop bs) ;;
    ret rv.
 
(*
  lookups for fname

*)

About Ast.fdecl.

Fixpoint lookup {T} (id: Ast.id) (fdecls: list (Ast.id * T)) : option T :=
  match fdecls with
  | nil => None
  | h :: t => if eqb (fst h) (id) then Some (snd h) else lookup id t
  end.
Definition interp_away_calls (fdecls : list (id * function_denotation)) (id: string) (args: list ovalue) : _ :=
  @mrec OCallE (OatE')
        (fun T call =>
           match call with
             | OCall id args => 
               match lookup id fdecls with
               | None => (* call not found *)
                 raise "error: function call not in context"
               | Some fdecl =>
                 fdecl args
               end
           end
        ) _ (OCall id args).



(* Start denoting the toplevel program - e.g. what happens when you want to run a function *)
Definition denote_gdecls (p: Ast.prog) : itree OatE' unit :=
  _ <- map_monad (fun dec =>
               match dec with
               | Gvdecl dec => translate_gdecl_OatE' (denote_gdecl (elt Ast.gdecl dec))
               | _ => ret tt
               end
               ) p ;; ret tt.

Definition denote_oat
           (retty : Oat.Ast.ret_ty)
           (entry : string)
           (args : list ovalue)
           (prog : prog) : itree OatE' ovalue :=
  (* Handle global variable declarations *)
  denote_gdecls prog ;;
  (* Denote functions now *)
  let fdeclsOnly := List.filter (fun e => match e with | Gfdecl _ => true | _ => false end) prog in
  denoted_fdecls <- map_monad (fun decl =>
                    match decl with
                    | Gfdecl {| elt := dec; loc := _ |} =>
                      ret (fname dec , denote_fdecl dec)
                    | _ => raise "impossible"
                    end
                      ) fdeclsOnly ;;
  (** Now that we have denoted the various function declarations,
      we can interpret away the calls ...
   *)
  interp_away_calls denoted_fdecls entry args.

(* Finally, here is the function that will interpret an oat programs events (excluding the failure events ! *)
Definition interp_oat_failure {R} (t: itree OatE' R)
           (l: FMapAList.alist var value * FMapAList.alist var value * Handlers.stack) :=
  let env := FMapAList.alist var value in
  let inst := FMapAList.Map_alist RelDec_string value in
  let trace := Oat.Handlers.interp_env_stack handle_env t l
                                                    (map := env)
  in
  trace.
Check interp_oat_failure.


(** Top level section *)
Check denote_oat.
Definition interp_user
           (retty : Oat.Ast.ret_ty)
           (entry : string)
           (args : list ovalue)
           (prog : prog) :=
  let t : itree OatE' ovalue := denote_oat retty entry args prog in
  interp_oat_failure t ([], [], []).  
           
