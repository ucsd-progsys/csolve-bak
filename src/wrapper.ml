module F  = Format
module SM = Misc.StringMap
module ST = Ssa_transform
module  A = Ast
module  C = Constraint
module Sy = A.Symbol
module So = A.Sort
module CI = CilInterface

open Misc.Ops
open Cil


(*******************************************************************)
(**************** Wrapper between LiquidC and Fixpoint *************)
(*******************************************************************)

type cilenv  = (Cil.varinfo * C.reft) SM.t

let ce_empty = 
  SM.empty

let ce_find v cenv = 
  SM.find v.vname cenv

let ce_add v r cenv = 
  SM.add v.vname (v, r) cenv

let ce_project cenv vs = 
  List.fold_left 
    (fun cenv' v -> SM.add v.vname (ce_find v cenv) cenv')
    ce_empty vs

let fresh_kvar = 
  let r = ref 0 in
  fun () -> r += 1 |> string_of_int |> (^) "k_" |> Sy.of_string

let fresh ty : C.reft =
  match ty with
  | TInt _ ->
      C.make_reft (Sy.value_variable So.Int) So.Int [C.Kvar ([], fresh_kvar ())]
  | _      -> 
      assertf "TBD: Consgen.fresh"

(* creating refinements *)

let t_single (e : Cil.exp) : C.reft =
  let ty = Cil.typeOf e in
  let so = CI.sort_of_typ ty in
  let vv = Sy.value_variable so in
  let p  = A.pAtom (A.eVar vv, A.Eq, CI.expr_of_cilexp e) in
  (vv, so, [(C.Conc p)])

let t_var (v : Cil.varinfo) : C.reft =
  t_single (Lval ((Var v), NoOffset))

let env_of_cilenv cenv = 
  SM.fold 
    (fun x (_,r) env -> Sy.SMap.add (Sy.of_string x) r env) 
    cenv
    Sy.SMap.empty

let make_ts env p lhsr rhsr loc = 
  [C.make_t (env_of_cilenv env) p lhsr rhsr None]

let make_wfs env r loc =
  let env = env_of_cilenv env in
  C.kvars_of_reft r 
  |> List.map (fun (_,k) -> C.make_wf env k None)

(*
let cstr_of_cilcstr sci p (cenv, ibs, r1, r2, _) =
  failwith "TBDNOW"
  let env = env_of_cilenv cenv in
  let gp  = expand_guard  sci.ST.ifs ibs in
  C.make_t env (A.pAnd [p; gp]) r1 r2 
  *)

let cstr_of_cilcstr _ = failwith "TBDNOW"

