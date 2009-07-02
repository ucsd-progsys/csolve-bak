(* translation of constraints to latex *)

module C  = FixConstraint
open Misc.Ops

(* print linebreak after each connective in constraint *)
let c_linebreak = ref true

let sort_to_latex = Ast.Sort.to_string 
let symbol_to_latex s = 
  Ast.Symbol.to_string s
  |> Str.global_replace (Str.regexp "_") "\\_"
let constant_to_latex = Ast.Constant.to_string

let bop_to_latex = function 
  | Ast.Plus  -> "+"
  | Ast.Minus -> "-"
  | Ast.Times -> ""
  | Ast.Div   -> "/"
let brel_to_latex = function 
  | Ast.Eq -> "="
  | Ast.Ne -> "!="
  | Ast.Gt -> ">"
  | Ast.Ge -> "\\geq"
  | Ast.Lt -> "<"
  | Ast.Le -> "\\leq"
let bind_to_latex (s, t) = 
  Printf.sprintf "%s:%s" (symbol_to_latex s) (sort_to_latex t)
let rec expr_to_latex (e, _) = 
  match e with
    | Ast.Con c -> constant_to_latex c
    | Ast.Var s -> symbol_to_latex s
    | Ast.App (s, es) ->
	Printf.sprintf "%s([%s])" 
	  (symbol_to_latex s) (List.map expr_to_latex es |> String.concat " ")
    | Ast.Bin (e1, op, e2) ->
	Printf.sprintf "(%s %s %s)" 
	  (expr_to_latex e1) (bop_to_latex op) (expr_to_latex e2)
    | Ast.Ite (ip, te, ee) -> 
	Printf.sprintf "%s ? %s : %s" 
	  (pred_to_latex ip) (expr_to_latex te) (expr_to_latex ee)
    | Ast.Fld (s, e) -> 
	Printf.sprintf "%s.%s" (expr_to_latex e) (symbol_to_latex s)
	  
and pred_to_latex (p, _) = 
  match p with
    | Ast.True -> "\\ltrue"
    | Ast.False -> "\\lfalse"
    | Ast.Bexp e -> expr_to_latex e
    | Ast.Not p -> Printf.sprintf "\\neg (%s)" (pred_to_latex p) 
    | Ast.Imp (p1, p2) -> 
	Printf.sprintf "(%s \\limp %s)" (pred_to_latex p1) (pred_to_latex p2)
    | Ast.And ps -> List.map pred_to_latex ps |> String.concat " \\land "
    | Ast.Or ps -> List.map pred_to_latex ps |> String.concat " \\lor "
    | Ast.Atom (e1, r, e2) ->
	Printf.sprintf "(%s %s %s)" 
          (expr_to_latex e1) (brel_to_latex r) (expr_to_latex e2)
    | Ast.Forall (qs,p) -> 
	Printf.sprintf "\\forall %s: %s" 
          (List.map bind_to_latex qs |> String.concat ", ") (pred_to_latex p)

(*
let expr_to_latex e = Ast.Expression.to_string e
let pred_to_latex p = Ast.Predicate.to_string p
*)
let subst_to_latex (s, e) = 
  Printf.sprintf "[%s/%s]" (expr_to_latex e) (symbol_to_latex s)
let refa_to_latex refa =
  match refa with 
    | C.Conc pred -> pred_to_latex pred
    | C.Kvar (subs, sym) -> 
	Printf.sprintf "%s%s" 
	  (symbol_to_latex sym)
	  (List.map subst_to_latex subs |> String.concat "")
  
let reft_to_latex (v, b, r) = 
  Printf.sprintf "\\{ %s:%s \\mid %s \\}"
    (symbol_to_latex v) (sort_to_latex b) 
    (if r = [] then "\\ltrue" else
       (List.map refa_to_latex r |> String.concat " \\land "))

let envt_to_latex envt = 
  if Ast.Symbol.SMap.is_empty envt then
    "\\ltrue;\\ "
  else
    Ast.Symbol.SMap.fold 
      (fun sym reft sofar -> 
	 Printf.sprintf "%s:%s;%s%s" 
	   (symbol_to_latex sym) (reft_to_latex reft) 
	   (if !c_linebreak then "\\\\\n" else "\\ ")
	   sofar) envt ""

let c_to_latex out c = 
  Printf.fprintf out 
"\\begin{footnotesize}
  \\begin{verbatim}
%s
  \\end{verbatim}
\\end{footnotesize}
" (C.to_string c);
(* Andrey: old: aligned array ... *)
(*   \\begin{array}[t]{l@{}l@{;\\ \\deriv\\ }c@{\\ <:\\ }l@{\\qquad}c} *)
(*   %% envt & A.pred & reft & reft & (tag option) *)
(*  Printf.fprintf out "  %s & %s & %s & %s & %s \\\\[\\jot]\n" *)
  Printf.fprintf out
"\\begin{displaymath}
  \\begin{array}[t]{l}
  %s %s\\ \\deriv\\\\ %s\\ <:\\\\ %s\\qquad %s
  \\end{array}
\\end{displaymath}
\\hrule
" 
    (C.env_of_t c |> envt_to_latex) 
    (C.grd_of_t c |> pred_to_latex)
    (C.lhs_of_t c |> reft_to_latex) 
    (C.rhs_of_t c |> reft_to_latex)
    (try string_of_int (C.id_of_t c) with _ -> "")
      

let to_latex out cs ws = 
  Printf.printf "Translating to latex %d cs and %d ws.\n" 
    (List.length cs) (List.length ws);
  Printf.fprintf out 
"\\documentclass[10pt]{llncs}
\\pagestyle{plain}
\\usepackage{amsmath}
\\newcommand{\\ltrue}{\\mathit{true}}
\\newcommand{\\lfalse}{\\mathit{false}}
\\newcommand{\\limp}{\\rightarrow}
\\newcommand{\\deriv}{\\vdash}
\\begin{document}
";
  List.iter (c_to_latex out) cs;
  Printf.fprintf out 
"\\end{document}
%%%%%% Local Variables: 
%%%%%% mode: latex
%%%%%% TeX-master: t
%%%%%% End: 
"