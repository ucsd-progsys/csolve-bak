module M = Misc
module P = Pretty
module F = FixConstraint
module As = Ast.Symbol  
module Asm = Ast.Symbol.SMap
module Ac = Ast.Constant
  
open M.Ops

type class_bound = int option (* None = unbounded *)

let scale_bound x b =
  M.map_opt (( * ) x) b

let bound_offset x b =
  M.map_opt (( + ) x) b

let bound_plus b1 b2 = match b1, b2 with
  | Some n, Some m -> Some (m + n)
  | _              -> None

let lower_bound_le b1 b2 = match b1, b2 with
  | Some n, Some m -> n <= m
  | Some _, None   -> false
  | _              -> true

let upper_bound_le b1 b2 = match b1, b2 with
  | Some n, Some m -> n <= m
  | None, Some _   -> false
  | _              -> true

let bound_min le b1 b2 =
  if le b1 b2 then b1 else b2

let bound_max le b1 b2 =
  if le b1 b2 then b2 else b1

let lower_bound_min = bound_min lower_bound_le
let lower_bound_max = bound_max lower_bound_le
let upper_bound_min = bound_min upper_bound_le
let upper_bound_max = bound_max upper_bound_le

(* Describes the integers lb <= n <= ub s.t. n = c (mod m) *)
type bounded_congruence_class = {
  lb : class_bound; (* Lower bound; lb mod m = c *)
  ub : class_bound; (* Upper bound; ub mod m = c; lb < ub *)
  c  : int;         (* Remainder; 0 <= c < m *)
  m  : int;         (* Modulus; 0 < m <= ub - lb *)
}

type t =
  | IBot                                 (* Empty *)
  | IInt    of int                       (* Single integer *)
  | ICClass of bounded_congruence_class  (* Subset of congruence class *)

type tIndex = t

let top = ICClass {lb = None; ub = None; c = 0; m = 1}

let nonneg = ICClass {lb = Some 0; ub = None; c = 0; m = 1}

let d_index () = function
  | IBot                                         -> P.dprintf "_|_"
  | IInt n                                       -> P.num n
  | ICClass {lb = None; ub = None; c = c; m = m} -> P.dprintf "%d{%d}" c m
  | ICClass {lb = Some n; ub = None; m = m}      -> P.dprintf "%d[%d]" n m
  | ICClass {lb = Some l; ub = Some u; m = m}    -> P.dprintf "%d[%d < %d]" l m (u + m)
  | _                                            -> assert false

let repr_suffix = function
  | IBot                                     -> "B"
  | IInt n                                   -> string_of_int n
  | ICClass {lb = lb; ub = ub; m = m; c = c} ->
    let lbs = match lb with Some n -> string_of_int n | None -> "-" in
    let ubs = match ub with Some n -> string_of_int n | None -> "+" in
    lbs ^ "#c" ^ string_of_int c ^ "#m" ^ string_of_int m ^ "#" ^ ubs

let repr_prefix = "Ix#"

let repr i =
  repr_prefix ^ repr_suffix i

let compare i1 i2 = compare i1 i2

let of_int i =
  IInt i

let mk_sequence start period lbound ubound = match lbound, ubound with
  | Some m, Some n when m = n -> IInt n
  | _                         -> ICClass {lb = lbound; ub = ubound; m = period; c = start mod period}

let mk_geq n =
  ICClass {lb = Some n; ub = None; m = 1; c = 0}

let mk_leq n =
  ICClass {lb = None; ub = Some n; m = 1; c = 0}

let mk_eq_mod c m =
  ICClass {lb = None; ub = None; m = m; c = c}

let is_unbounded = function
  | ICClass {lb = None} | ICClass {ub = None} -> true
  | _                                         -> false

let period = function
  | ICClass {m = m} -> Some m
  | IInt _ | IBot   -> None

let is_periodic i =
  period i != None

let is_subindex i1 i2 = match i1, i2 with
  | IBot, _                                          -> true
  | _, IBot                                          -> false
  | IInt n, IInt m                                   -> n = m
  | ICClass _, IInt _                                -> false
  | IInt n, ICClass {lb = lb; ub = ub; c = c; m = m} ->
    lower_bound_le lb (Some n) && upper_bound_le (Some n) ub && ((n mod m) = c)
  | ICClass {lb = lb1; ub = ub1; c = c1; m = m1},
    ICClass {lb = lb2; ub = ub2; c = c2; m = m2} ->
    lower_bound_le lb2 lb1 && upper_bound_le ub1 ub2 && (m1 mod m2) = 0 && (c1 mod m2) = c2

let lub i1 i2 =
  if is_subindex i1 i2 then
    i2
  else if is_subindex i2 i1 then
    i1
  else match i1, i2 with
    | IBot, _ | _, IBot -> assert false
    | IInt m, IInt n    ->
      let d = abs (m - n) in
      ICClass {lb = Some (min m n); ub = Some (max m n); m = d; c = m mod d}
    | IInt n, ICClass {lb = lb; ub = ub; m = m; c = c}
    | ICClass {lb = lb; ub = ub; m = m; c = c}, IInt n ->
      let m = M.gcd m (abs (c - (n mod m))) in
      ICClass {lb = lower_bound_min lb (Some n);
               ub = upper_bound_max ub (Some n);
               m  = m;
               c  = c mod m}
    | ICClass {lb = lb1; ub = ub1; m = m1; c = c1},
      ICClass {lb = lb2; ub = ub2; m = m2; c = c2} ->
      let m = M.gcd m1 (M.gcd m2 (abs (c1 - c2))) in
      ICClass {lb = lower_bound_min lb1 lb2;
               ub = upper_bound_max ub1 ub2;
               m  = m;
               c  = c1 mod m}

(* pmr: There is surely a closed form for this, to be sought
        later. *)
let rec search_congruent c1 m1 c2 m2 n =
  if n < 0 then None else
    if (n mod m1) = c1 && (n mod m2) = c2 then
      Some n
    else
      search_congruent c1 m1 c2 m2 (n - 1)

let glb i1 i2 =
  if is_subindex i1 i2 then
    i1
  else if is_subindex i2 i1 then
    i2
  else match i1, i2 with
    | IBot, _ | _, IBot         -> assert false
    | IInt m, IInt n when m = n -> IInt m
    | IInt _, IInt _            -> IBot
    | IInt n, ICClass {lb = lb; ub = ub; m = m; c = c}
    | ICClass {lb = lb; ub = ub; m = m; c = c}, IInt n ->
      if lower_bound_le lb (Some n) &&
        upper_bound_le (Some n) ub &&
        (n mod m) = c then
        IInt n
      else IBot
    | ICClass {lb = lb1; ub = ub1; m = m1; c = c1},
        ICClass {lb = lb2; ub = ub2; m = m2; c = c2} ->
      let m = M.lcm m1 m2 in
      match search_congruent c1 m1 c2 m2 (m - 1) with
        | None   -> IBot
        | Some c ->
          let lb = lower_bound_max lb1 lb2 |> M.map_opt (fun l -> m * ((l + m - c - 1) / m) + c) in
          let ub = upper_bound_min ub1 ub2 |> M.map_opt (fun l -> m * ((l - c) / m) + c) in
          match lb, ub with
            | Some l, Some u when u = l -> IInt u
            | Some l, Some u when u < l -> IBot
            | _                         -> ICClass {lb = lb; ub = ub; m = m; c = c}

let overlaps i1 i2 =
  glb i1 i2 <> IBot

let widen i1 i2 =
  if is_subindex i1 i2 then
    i2
  else if is_subindex i2 i1 then
    i1
  else match i1, i2 with
    | IBot, _ | _, IBot -> assert false
    | IInt n, IInt m    ->
      let d = abs (n - m) in
      ICClass {lb = Some (min n m);
               ub = None;
               c  = n mod d;
               m  = d}
    | IInt n, ICClass {lb = lb; ub = ub; c = c; m = m}
    | ICClass {lb = lb; ub = ub; c = c; m = m}, IInt n ->
      ICClass {lb = lower_bound_min (Some n) lb;
               ub = upper_bound_max (Some n) ub;
               c  = 0;
               m  = M.gcd m (M.gcd c n)}
    | ICClass {lb = lb1; ub = ub1; c = c1; m = m1},
      ICClass {lb = lb2; ub = ub2; c = c2; m = m2} ->
      let m = M.gcd m1 (M.gcd m2 (abs (c1 - c2))) in
      ICClass {lb = if lb1 = lb2 then lb1 else None;
               ub = if ub1 = ub2 then ub1 else None;
               c  = c1 mod m;
               m  = m}

let offset n = function
  | IBot                                     -> IBot
  | IInt m                                   -> IInt (n + m)
  | ICClass {lb = lb; ub = ub; c = c; m = m} ->
    ICClass {lb = bound_offset n lb;
             ub = bound_offset n ub;
             c  = (c + n) mod m;
             m  = m}

let plus i1 i2 = match i1, i2 with
  | IBot, _ | _, IBot     -> IBot
  | IInt n, i | i, IInt n -> offset n i
  | ICClass {lb = lb1; ub = ub1; c = c1; m = m1},
    ICClass {lb = lb2; ub = ub2; c = c2; m = m2} ->
    ICClass {lb = bound_plus lb1 lb2;
             ub = bound_plus ub1 ub2;
             c  = 0;
             m  = M.gcd m1 (M.gcd m2 (M.gcd c1 c2))}

let minus i1 i2 = match i1, i2 with
  | IBot, _ | _, IBot                                                -> IBot
  | IInt n, IInt m                                                   -> IInt (n - m)
  | ICClass {lb = Some l; ub = ub; c = c; m = m}, IInt n when l >= n ->
    ICClass {lb = Some (l - n);
             ub = bound_offset (-n) ub;
             c = (c - n) mod m;
             m = m}
  | _ -> top

let scale x = function
  | IBot   -> IBot
  | IInt n -> IInt (n * x)
  | ICClass {lb = lb; ub = ub; c = c; m = m} ->
    ICClass {lb = scale_bound x lb;
             ub = scale_bound x ub;
             c = c;
             m = x * m}

let mult i1 i2 = match i1, i2 with
  | IBot, _ | _, IBot     -> IBot
  | IInt n, i | i, IInt n -> scale n i
  | _                     -> top

let constop op i1 i2 = match i1, i2 with
  | IBot, _ | _, IBot -> IBot
  | IInt n, IInt m    -> IInt (op n m)
  | _                 -> top

let div =
  constop (/)

let unsign i = match i with
  | IBot                              -> IBot
  | IInt n when n >= 0                -> i
  | ICClass {lb = Some n} when n >= 0 -> i
  | _                                 -> nonneg

module OrderedIndex = struct
  type t = tIndex

  let compare = compare
end

module IndexSet        = Set.Make (OrderedIndex)
module IndexSetPrinter = P.MakeSetPrinter (IndexSet)

let d_indexset () is =
  IndexSetPrinter.d_set ", " d_index () is

module AbstractDomain: Config.DOMAIN = struct
  (* All definitions below are placeholders *)
  (* First bit of TODO, just to get the solver to go all the way through
     without really doing anything:
       Define t, bind
       Define create, empty, and top as trivially as possible
         (map every kvar to bot)
       Define printing functions
       Define unsat to always return false
       Define refine to do nothing
  *)
  type bind = OrderedIndex.t
  type t    = OrderedIndex.t Asm.t

  let empty = Asm.empty

  let read sol =
    fun k -> 
      if Asm.mem k sol
      then
	match Asm.find k sol with
	  | IBot -> [Ast.pFalse]
	  | IInt i -> [Ast.pAtom (Ast.eVar k, Ast.Eq, Ast.eCon (Ac.Int i))]
	  | _ -> [Ast.pTrue]
      else
	[Ast.pFalse]

  let topIndex = top      

  let top sol xs =
    let xsTop = List.map (fun x -> x, topIndex) xs in
    let xsMap = Asm.of_list xsTop in
      Asm.extend sol xsMap

  let rec interpretPred env solution sym pred =
    match pred with
      | F.Kvar (_, k) -> if Asm.mem k solution then Asm.find k solution else IBot
      | F.Conc (p, i) ->
	  begin match p with
	    | Ast.True -> topIndex
	    | Ast.False -> IBot
	    | Ast.Atom ((Ast.Var nu, _),r,(e,_))
	    | Ast.Atom ((e,_),r,(Ast.Var nu, _)) when nu = sym ->
		begin match r with
		  | Ast.Eq -> interpretExpr env solution e
		  | _  -> topIndex
		end
	    | Ast.Bexp (e, _) ->
		begin match e with
		  | Ast.Con (Ac.Int n) -> of_int n
		  | _ -> topIndex
		end
	    | _ -> topIndex
	  end
  and interpretExpr env solution expr =
    match expr with
      | Ast.Con (Ast.Constant.Int n) ->
	  IInt n
      | Ast.Var sym ->
	  begin match F.lookup_env env sym with
	    | None -> IBot
	    | Some (sym, sort, refas) when Ast.Sort.is_int sort ->
		List.fold_left glb topIndex
		  (List.map (interpretPred env solution sym) refas)
	  end
      | Ast.Bin ((e1, t1), oper, (e2, t2)) ->
	  let e1v = interpretExpr env solution e1 in
	  let e2v = interpretExpr env solution e2 in
	    begin match oper with
	      | Ast.Plus  -> plus  e1v e2v
	      | Ast.Minus -> minus e1v e2v
	      | Ast.Times -> mult  e1v e2v
	      | Ast.Div   -> div  e1v e2v
	      | Ast.Mod   -> topIndex (* dunno *)
	    end
      | _ -> topIndex

  let index_of_reft env solution reft =
    match reft with
      | (v, t, preds) ->
	  List.fold_left glb topIndex (List.map (interpretPred env solution v) preds)
      | _ -> topIndex
		
  let refine sol c =
    let rhs = F.rhs_of_t c in
    let lhsVal = index_of_reft (F.env_of_t c) sol (F.lhs_of_t c) in
    let refineK sol k =
      let oldK = if Asm.mem k sol then Asm.find k sol else IBot in
      let newK = widen lhsVal oldK in
	if oldK = newK then (false, sol) else (true, Asm.add k newK sol)
    in
      List.fold_left
	begin fun p k -> match p,k with
	  | (_, sol), (_, sym) -> refineK sol sym
	  | _ -> (false, sol)
	end
	(false, sol) (F.kvars_of_reft rhs)

  let unsat sol c =
    (* Make sure that lhs <= k for each k in rhs *)
    let rhsKs = F.rhs_of_t c |> F.kvars_of_reft  in
    let lhsVal = index_of_reft (F.env_of_t c) sol (F.lhs_of_t c) in
    let onlyK v = match v with (* true if the constraint is unsatisfied *)
      | sub, sym ->
	  if Asm.mem sym sol then
	    not (is_subindex lhsVal (Asm.find sym sol))
	  else
	    true
    in
      List.map onlyK rhsKs |> List.fold_left (&&) true
	
  let create cfg =
    let replace v = IBot in
      Asm.map replace cfg.Config.bm
	
  let print ppf sol =
    let pf key value =
      Pretty.dprintf "%s |-> %a\n" (As.to_string key) d_index value in
    let _ = Asm.mapi pf sol in
      ()

  let print_stats ppf sol =
    ()

  let dump sol =
    let pf key value =
      Pretty.dprintf "%s |-> %a\n" (As.to_string key) d_index value in
    let _ = Asm.mapi pf sol in
      ()

  let mkbind qbnds = IBot
end
