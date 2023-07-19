module LL = LLVMAst
open InterpretationStack.InterpreterStackBigIntptr.LP.Events
open QCheck
module Z = Camlcoq.Z
module G = QCheck.Gen
open MemoryModelImplementation
open MemoryAddress
module GA = GenAlive2.GEN_ALIVE2(MemoryModelImplementation.InfAddr)(MemoryModelImplementation.BigIP)(MemoryModelImplementation.FinSizeof)
module GL = GenAlive2.GenLow
open Buffer

let string_of_char_list : char list -> string = fun l ->
  let buf = Buffer.create (List.length l) in
  List.iter (Buffer.add_char buf) l;
  Buffer.contents buf


let small_gen =
  let open G in
  G.int_range 0 10000

let i8gen =
  let open G in
  G.int_range 0 255

let g_const : 'a. 'a -> 'a G.t = fun v _rs -> v

let g_i1 = G.map
             (fun v ->
               DV.UVALUE_I1 (if v then Z.one else Z.zero) ) G.bool
let g_si8 = G.map
                ( fun v -> DV.UVALUE_I8 (Z.of_sint v)) i8gen

let g_si32 = G.map
                 (fun v -> DV.UVALUE_I32 (Z.of_sint v)) small_gen

let g_si64 = G.map (fun v -> DV.UVALUE_I64 (Z.of_sint v)) small_gen

let gen_uvalue'' (t : LL.typ) : DV.uvalue GL.coq_G =
  let ran = GA.run_GenALIVE2 (GA.gen_uvalue t) in
  GL.bindGen
    (ran)
    (fun x ->
       begin match x with
         | GenAlive2.Inl a -> failwith (string_of_char_list a)
         | GenAlive2.Inr b -> GL.returnGen b
       end)

let gen_uvalue' (t : LL.typ) : DV.uvalue G.t =
  let uv = GL.run (gen_uvalue'' t) O GenAlive2.newRandomSeed in (* This needs to be edited. Cannot afford to have random seed everytime*)
  G.return uv

let gen_uvalue : LL.typ -> DV.uvalue G.t = gen_uvalue'

(* let rec gen_uvalue : LL.typ -> DV.uvalue G.t = function
 *   | LL.TYPE_I i ->
 *      begin match Camlcoq.N.to_int i with
 *      | 1 -> g_i1 | 8 -> g_si8 | 16 | 32 -> g_si32 | 64 -> g_si64
 *      | _ -> failwith "generating integer values of this type is not implemented"
 *      end
 *   | LL.TYPE_Void -> g_const DV.UVALUE_None
 *   | LL.TYPE_Vector (sz, ty) ->
 *      (\* print_endline "generating vector value"; *\)
 *      let open G in
 *      let gen_t = gen_uvalue ty in
 *      let list_ts = G.list_size (g_const (sz |> Camlcoq.N.to_int32 |> Int32.to_int)) gen_t in
 *      list_ts >>= (fun l -> G.return @@ DV.UVALUE_Vector l)
 *   | LL.TYPE_Array (sz, ty) ->  
 *      let open G in
 *      let gen_t = gen_uvalue ty in
 *      let list_ts = G.list_size (g_const (sz |> Camlcoq.N.to_int32 |> Int32.to_int)) gen_t in
 *      list_ts >>= (fun l -> G.return @@ DV.UVALUE_Vector l)
 *   | _ -> failwith "generating values of this type is not implemented" *)


let gen_args : LL.typ list -> (DV.uvalue) list G.t = fun ts -> ts |> List.map (fun t -> gen_uvalue t) |> G.flatten_l 

let generate_args : LL.typ list -> (LL.typ * DV.uvalue) list = fun t_args ->
  let vals = G.generate1 (gen_args t_args) in
  List.combine t_args vals

let generate_n_args : int -> LL.typ list -> (LL.typ * DV.uvalue) list list = fun n t_args ->
  let vals = G.generate ~n:n (gen_args t_args) in
  List.map (List.combine t_args) vals
