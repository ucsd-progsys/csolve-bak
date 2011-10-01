(* AbstractDomain : Config.DOMAIN
  with type bind = Index.t *)
include Config.DOMAIN
 with type bind = Index.t

(*val index_of_refa: FixConstraint.envt -> Index.t Ast.Symbol.SMap.t -> Ast.Symbol.t -> Ast.Sort.t -> FixConstraint.refa -> Index.t
val index_of_preds: FixConstraint.envt -> Index.t Ast.Symbol.SMap.t -> Ast.Symbol.t -> Ast.Sort.t -> Ast.pred list -> Index.t  *)
(*
type t
type bind = Index.t
val empty        : t 
  (* val meet         : t -> t -> t *)
val read         : t -> FixConstraint.soln
val read_bind    : t -> Ast.Symbol.t -> bind
val top          : t -> Ast.Symbol.t list -> t
val refine       : t -> FixConstraint.t -> (bool * t)
val unsat        : t -> FixConstraint.t -> bool
val create       : bind Config.cfg -> t
val print        : Format.formatter -> t -> unit
val print_stats  : Format.formatter -> t -> unit
val dump         : t -> unit
val mkbind       : Config.qbind -> bind
*)
