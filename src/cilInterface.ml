module F  = Format
module A  = Ast
module E  = A.Expression
module P  = A.Predicate
module Sy = A.Symbol
module So = A.Sort

open Misc.Ops

(****************************************************************)
(********************* Sorts ************************************)
(****************************************************************)

let sort_of_typ = function
  | Cil.TInt _ -> 
      So.Int
  | _ -> 
      assertf "TBD: Wrapper.sort_of_typ"

(****************************************************************)
(********************* Constants ********************************)
(****************************************************************)

let con_of_cilcon = function
  | Cil.CInt64 (i, _, _) -> 
      A.Constant.Int (Int64.to_int i)
  | _ -> 
      assertf "TBD: Wrapper.con_of_cilcon unhandled"
(*  | Cil.CStr _        -> Constant.String str
    | Cil.CChr _        -> Constant.Int (int_of_char c) 
    | Cil.CReal (_,_,_) -> Constant.Float f
    | Cil.CWStr _ -> failwith "CIL: Wide character constant not handled yet"
*)

(****************************************************************)
(********************* Expressions ******************************)
(****************************************************************)

type op = Bop of A.bop | Brl of A.brel 

(* 
let unop_of_cilUOp = function
  | Cil.Neg ->  A.UnaryMinus
  | Cil.BNot -> A.BitNot
  | Cil.LNot -> A.Not
*)

let op_of_cilBOp = function
  | Cil.PlusA   -> Bop A.Plus    
  | Cil.PlusPI  -> Bop A.Plus     
  | Cil.MinusA  -> Bop A.Minus    
  | Cil.MinusPI -> Bop A.Minus   
  | Cil.MinusPP -> Bop A.Minus  
  | Cil.Mult    -> Bop A.Times
  | Cil.Div     -> Bop A.Div     
  | Cil.Lt      -> Brl A.Lt  
  | Cil.Gt      -> Brl A.Gt  
  | Cil.Le      -> Brl A.Le  
  | Cil.Ge      -> Brl A.Ge  
  | Cil.Eq      -> Brl A.Eq
  | Cil.Ne      -> Brl A.Ne 
  | Cil.IndexPI    
  | Cil.Mod       
  | Cil.Shiftlt   
  | Cil.Shiftrt   
  | Cil.BAnd                         
  | Cil.BXor                         
  | Cil.BOr                          
  | Cil.LOr    
  | Cil.LAnd    -> assertf "TBD: op_of_cilBop"

let expr_of_var v = 
  v.Cil.vname |> Sy.of_string |> A.eVar

let expr_of_lval (lh, _) = match lh with
  | Cil.Var v -> 
      v.Cil.vname |> Sy.of_string |> Ast.eVar
  | _ -> 
      assertf "TBD: Wrapper.expr_of_lval" 

let expr_of_cilexp = function
  | Cil.Const c -> 
      Ast.eCon (con_of_cilcon c)
  | Cil.Lval lv -> 
      expr_of_lval lv  
  | _ -> 
      assertf "TBD: Wrapper.expr_of_cilexp"

(****************************************************************)
(********************* Predicates *******************************)
(****************************************************************)
let pred_of_cilexp = assertf "TBDNOW: Wrapper.pred_of_cilexp"

(* 
let rec convertCilExpToPred e =
  let rec convertExpToPred exp =
    match exp with
        Expression.Binary (bop, e1, e2) ->
          if (Expression.isRelOp bop) then
            Predicate.Atom exp
          else 
            Predicate.Atom (Expression.Binary(Expression.Ne,
                                              exp,
                                              Expression.Constant (Constant.Int 0)))
      | Expression.Unary (uop, e1) ->
          begin
            match uop with
                Expression.Not ->
                  Predicate.negate (convertExpToPred e1)
              | _ ->
                  Predicate.Atom (Expression.Binary(Expression.Ne,
                                                    exp,
                                                    Expression.Constant (Constant.Int 0)))
          end
      | _ ->
          Predicate.Atom (Expression.Binary(Expression.Ne,
                                            exp,
                                            Expression.Constant (Constant.Int 0)))
  in
  convertExpToPred (convertCilExp e)
*)

(* {{{
let rec convertCilLval (lb, off) =
  let rec genOffset lvalue o =
    match o with
    | Cil.NoOffset -> lvalue
    | Cil.Field (fid, o1) ->
	begin
	  let ee = Expression.Access (Expression.Dot, Expression.Lval lvalue, fid.Cil.fname) in
	  genOffset ee o1
	end
    | Cil.Index (e, o1) ->
	begin
	  let iexp = convertCilExp e in
	  let ee = Expression.Indexed (Expression.Lval lvalue, iexp) in
	  genOffset ee o1
	end
  in
  match lb with
    Cil.Var vinfo -> 
      begin
	let m = Expression.Symbol vinfo.Cil.vname in
	genOffset m off
      end
  | Cil.Mem m ->
      begin
	let _lval_mem_worker m off =
	  match off with
	    Cil.NoOffset -> Expression.Dereference m
	  | Cil.Field (finfo, offset) -> 
	      begin
                (* Have only Dot's, no Arrow's *)
	  if Cil.hasAttribute "lock" finfo.Cil.fattr then
	    Message.msg_string Message.Normal ("Lock found! "^finfo.Cil.fname) ;
                let e = Expression.Access 
		    (Expression.Dot, Expression.Lval (Expression.Dereference m), finfo.Cil.fname) in 
		genOffset e offset
	      end
	  | Cil.Index (exp, offset) -> 
	      begin
		let e = (Expression.Indexed (m, convertCilExp exp)) in
		genOffset e offset
	      end
	in
	let m = convertCilExp m
	in
	_lval_mem_worker m off
      end

and convertCilExp e =
  match e with
    Cil.Const const ->
      Expression.Constant (convertCilConst const)
  | Cil.Lval (lb,loff) ->
      begin
	Expression.Lval (convertCilLval (lb,loff))
      end
  | Cil.SizeOf t -> 
    begin
    try
      Expression.Constant 
	(Constant.Int 
	   (Int32.to_int (Int32.shift_left (Int32.of_int (Cil.bitsSizeOf t))  3))) (* size in bytes *)
    with Cil.SizeOfError(s,_) -> 
      Message.msg_string Message.Error ("Cil SizeofError: "^s); Expression.Constant (Constant.Int 4 )
    end
  | Cil.SizeOfE exp ->
    begin
    try
      Expression.Constant
      (Constant.Int
         (Int32.to_int (Int32.shift_left (Int32.of_int (Cil.bitsSizeOf (Cil.typeOf exp)))  3))) (* size in bytes *)
    with Cil.SizeOfError(s, i) -> failwith ("Cil Sizeoferror: "^s) 
    end
  | Cil.AlignOf t -> failwith "convertCilExp: align not handled"
  | Cil.AlignOfE e -> failwith "convertCilExp: AlignOfE not handled"
  | Cil.UnOp (op, exp, _) ->
      let uop = cilUOptoUnaryOp op in
      let e   = convertCilExp exp in
      Expression.Unary(uop, e)
  | Cil.BinOp (op, e1,e2,_) ->
      let bop = cilBOptoBinaryOp op in
      let (ex1, ex2) = (convertCilExp e1, convertCilExp e2) in
      Expression.Binary(bop, ex1, ex2)
  | Cil.CastE (t, e) -> convertCilExp e (* drop casts for now *)
  | Cil.AddrOf lval -> 
      let l = convertCilLval lval in
      Expression.addressOf (Expression.Lval l)
  | Cil.StartOf lv -> Expression.Lval (convertCilLval lv)
  | Cil.SizeOfStr s -> Expression.Constant (Constant.Int (String.length s))


let convertCilAttrToExpList a : (string * (Expression.expression list)) =
  let rec convertCilAttrparam ap =
    match ap with
      Cil.AInt i -> Expression.Constant (Constant.Int i)
    | Cil.AStr s -> Message.msg_string Message.Debug ("In AStr, string is "^s); (Expression.Lval (Expression.Symbol s))
    | Cil.ACons (s,aplist) -> Message.msg_string Message.Debug ("In ACons, string is "^s); 
	if (aplist = []) then (Expression.Lval (Expression.Symbol s)) else
	begin
	match s with
          "sel" -> Expression.Lval (Expression.Dereference (convertCilAttrparam (List.hd aplist)))
	| "at" -> 
	    begin
	      let s1 = convertCilAttrparam (List.nth aplist 0) and 
		  s2 = convertCilAttrparam (List.nth aplist 1) in
	      match (s1, s2) with
		(Expression.Lval (Expression.Symbol s), Expression.Lval (Expression.Symbol s'))  ->
		  Expression.Lval (Expression.Symbol (s^"@"^s'))
	      |	_ -> failwith "convertCilAttrparam : problem in at"
	    end
	| "arrow" ->
	    begin 
	      let s1 = convertCilAttrparam (List.nth aplist 0) and
		  s2 = convertCilAttrparam (List.nth aplist 1) in
	      match s2 with
		Expression.Lval (Expression.Symbol s) ->
		  Expression.Lval (Expression.Access (Expression.Arrow, s1, s))
	      | _ -> failwith "convertCilAttrparam : problem in arrow"	
	    end
	| "dot" ->
	    begin 
	      let s1 = convertCilAttrparam (List.nth aplist 0) and
		  s2 = convertCilAttrparam (List.nth aplist 1) in
	      match s2 with
		Expression.Lval (Expression.Symbol s) ->
		  Expression.Lval (Expression.Access (Expression.Dot, s1, s))
	      | _ -> failwith "convertCilAttrparam : problem in arrow"	
	    end
          | _ -> 
	      begin
		Message.msg_string Message.Error ("Error in parsing attributes: Strange function call "^s) ;
		Expression.FunctionCall (Expression.Lval (Expression.Symbol s), List.map convertCilAttrparam aplist)
	      end 
	end
    | Cil.ASizeOf _ -> failwith "convertCilAttrparam: SizeOf not handled"
    | Cil.ASizeOfE _ -> failwith "convertCilAttrparam: SizeOfE not handled"
    | Cil.ASizeOfS _ -> failwith "convertCilAttrparam: SizeOfE not handled"
    | Cil.AAlignOf _ | Cil.AAlignOfE _ | Cil.AAlignOfS _ -> failwith "Alignof not handled in attr"
    | Cil.AUnOp (uop, at) -> Expression.Unary (cilUOptoUnaryOp uop, convertCilAttrparam at)
    | Cil.ABinOp (bop, at1, at2) -> Expression.Binary (cilBOptoBinaryOp bop, convertCilAttrparam at1, convertCilAttrparam at2)
    | Cil.ADot (aparam, s) -> failwith "HERE"
  in
  match a with
    Cil.Attr (name, alist) -> 
      Message.msg_string Message.Debug ("Name of attribute is "^name) ; 
      (name, List.map convertCilAttrparam alist)


(*******************************************************************************)


class oneret_visitor = object
  inherit Cil.nopCilVisitor 
  method vfunc f =
    Oneret.oneret f ; Cil.SkipChildren
end


(* [Greg] This is very dirty, but it's the only way to know whether Frontc
   encountered an error *)

exception FrontcError of Cil.location

class frontc_error_detection_visitor = object
  inherit Cil.nopCilVisitor 
  method vinst i =
    match i with
        (* Check the Asm to see wether frontc encountered an error *)
        Cil.Asm (_, templates, _, _, _, loc) ->
          begin
            if ((List.length templates) == 1) then
              if (Misc.is_prefix "booo_exp(" (List.hd templates)) then
                raise (FrontcError loc)
          end ;
          Cil.SkipChildren
      | _ ->
          Cil.SkipChildren
end

let rename_locals f =
  Cil.iterGlobals f (fun g -> match g with
    Cil.GFun(fd,_) -> 
  let fnName = fd.Cil.svar.Cil.vname in
  let locals = List.map (fun var -> (var.Cil.vname <- (var.Cil.vname^"@"^fnName));var) fd.Cil.slocals
  and formals = List.map (fun var -> (var.Cil.vname <- (var.Cil.vname^"@"^fnName));var) fd.Cil.sformals
  in
  fd.Cil.slocals <- locals ;
  fd.Cil.sformals <- formals
  | _ -> ())

let make_cfg f =
    Cil.iterGlobals f 
    (fun glob -> match glob with
      Cil.GFun(fd,_) ->
	Cil.prepareCFG fd ; Cil.computeCFGInfo fd false 
    | _ -> ())


let junk_location = {Cil.line = 0; Cil.file = ""; Cil.byte = 0; }
let diverge = Cil.Loop ({Cil.bstmts = []; Cil.battrs = []}, junk_location, None, None)

module VarSet = Set.Make(struct
  type t = Cil.varinfo
  let compare v1 v2 = compare v1.Cil.vid v2.Cil.vid
end)

class add_symbolic_constants file =
(* globals are collected but never used! Commenting out. Rupak.
  let folder globals global =
    match global with
      Cil.GVar (v, _, _) -> VarSet.add v globals
    | Cil.GVarDecl (v, _) -> VarSet.add v globals
    | _ -> globals in
  let globals = Cil.foldGlobals file folder VarSet.empty in
  let globals = VarSet.elements globals in
*)    
  object
    inherit Cil.nopCilVisitor
	
    method vfunc fundec =
      let mk_symbolic formal =
	let name = formal.Cil.vname ^ "#" in
	Cil.makeLocalVar fundec name formal.Cil.vtype in
      Cil.SkipChildren
  end


let inits = ref []
class initGlobals =
  object
    inherit Cil.nopCilVisitor

    method vglob global =
      let rec init_one_offset lvalu offset initval loc =
         match initval with 
           Cil.SingleInit e -> 
		inits := (Cil.Set ((Cil.addOffsetLval offset lvalu), e, loc)) :: !inits
         | Cil.CompoundInit (t, offset_init_list) ->  
             compound_init (Cil.addOffsetLval offset lvalu) t offset_init_list loc
      and
      compound_init lvalu ty offset_init_list loc =
        match ty with
          Cil.TArray _ 
        | Cil.TComp _ -> 
           begin
             List.iter (fun (offset, initval) -> init_one_offset lvalu offset initval loc) 
                offset_init_list 
           end
        | Cil.TNamed (tinfo,_) ->
           begin
             let t = Cil.unrollType ty in compound_init lvalu t offset_init_list loc
           end 
        | Cil.TPtr _ -> Message.msg_string Message.Error "Compound initializer for TPtr not propagated"
        | Cil.TFun _ -> Message.msg_string Message.Error "Compound initializer for TFun not propagated"
        | _ -> Message.msg_string Message.Error "Compound initializer not propagated"
      in
      (match global with
	Cil.GVar (vinfo, init, location) ->
	  begin
           match init.Cil.init with
	    Some (Cil.SingleInit e) -> inits := Cil.Set ((Cil.Var vinfo, Cil.NoOffset), e, location) :: !inits
	  | Some (Cil.CompoundInit (t, offset_init_list)) -> 
              if (Options.getValueOfBool "initialize") then 
                compound_init (Cil.Var vinfo, Cil.NoOffset) t offset_init_list location
	  | None -> ()
          end
      |	_ -> ());
      Cil.SkipChildren
  end


(** add all global initializations as a function __BLAST_initialize () *)

(** if there are several input files, then each file would have
    an initializer. In this case, we generate
    unique names for the initializers by appending the file name.
 
    We maintain all the initializers in a set, and call_initializer
    calls all initializers from main.
	PROBLEM : CAN THERE BE DEPENDENCIES BETWEEN INITIALIZERS?
	We assume there is no dependency between initializers in
	different files... this is sound
*)
let __initializers = ref [] (* VarSet.empty  *)

let call_initializers cil_file = 
  let get_fundec file name =
    let rec search = function
	[] -> raise (Failure "Function declaration not found")
      | (Cil.GFun (fundec, _))::rest ->
	  if compare (fundec.Cil.svar.Cil.vname) name == 0 then
	    fundec
	else
	    search rest
      | _::rest -> search rest
    in search file.Cil.globals
  in
  (try 
    let main = get_fundec cil_file (List.hd (Options.getValueOfStringList "main")) in
    let nullLocation = { Cil.line = 0 ; Cil.file = cil_file.Cil.fileName ; Cil.byte = 0; } in
    let newstmts = List.fold_left (fun listsofar -> fun elt ->
               (Cil.Call (None, Cil.Lval (Cil.Var elt, Cil.NoOffset), [], nullLocation)) :: listsofar)
             [] !__initializers 
    in
    __initializers := [] ;
    main.Cil.sbody <- {main.Cil.sbody with
                       Cil.bstmts = Cil.mkStmt (Cil.Instr newstmts) :: main.Cil.sbody.Cil.bstmts} ;
    Cil.prepareCFG main ; Cil.computeCFGInfo main false 
  with _ -> ()) ;
  cil_file

let put_in_initializer cil_file =
  let nullLocation = { Cil.line = 0 ; Cil.file = cil_file.Cil.fileName ; Cil.byte = 0; } in
  let initer = Cil.emptyFunction ("__BLAST_initialize_"^cil_file.Cil.fileName) in
  cil_file.Cil.globals <- Cil.GVarDecl (initer.Cil.svar, nullLocation) :: 
    (cil_file.Cil.globals @ [ Cil.GFun (initer, nullLocation) ]) ;
  inits := [] ;
  let ig = new initGlobals 
  in
  let cil_file = Cil.visitCilFile ig cil_file in
  initer.Cil.sbody <- {Cil.battrs = []; Cil.bstmts = [Cil.mkStmt (Cil.Instr (List.rev (!inits )))]};
  inits := [] ;
  Message.msg_string Message.Normal ("Putting in initializer "^(initer.Cil.svar.Cil.vname)) ;
  __initializers := initer.Cil.svar :: !__initializers ;
  cil_file 
    
    
(***************************************************************************)
(* The following visitor and the function simplify changes the use of      *)
(* booleans as integers in C                                               *)
(* programs. For example, it changes code like:                            *)
(* x = (y < 0);                                                            *)
(* to if (y<0) x = 1; else x = 0;                                          *)
(* and if ((a<0) + !f >= ...) ... to                                       *)
(* if .. *)
(* ignoring to ask why anyone would write this?                            *)
(*                                                                         *)
(* CAUTION: This calls CIL's Simplify, don't know what can of worms that   *)
(*          will open!                                                     *)
(***************************************************************************)

class changeBoolVisitor =
  object (self)
   inherit Cil.nopCilVisitor
   
   method vinst _ = Cil.SkipChildren
   
   method vstmt stmt =
   begin
   let rewrite = function
     | Cil.Set (result, (Cil.UnOp (Cil.LNot, _, _) as pred), location)
     | Cil.Set (result, (Cil.BinOp (Cil.Lt, _, _, _) as pred), location)
     | Cil.Set (result, (Cil.BinOp (Cil.Gt, _, _, _) as pred), location)
     | Cil.Set (result, (Cil.BinOp (Cil.Le, _, _, _) as pred), location)
     | Cil.Set (result, (Cil.BinOp (Cil.Ge, _, _, _) as pred), location)
     | Cil.Set (result, (Cil.BinOp (Cil.Eq, _, _, _) as pred), location)
     | Cil.Set (result, (Cil.BinOp (Cil.Ne, _, _, _) as pred), location) ->
       let assign value =
         Cil.mkBlock [Cil.mkStmtOneInstr (Cil.Set (result, value, location))]
       in
       (true, Cil.If (pred, assign Cil.one, assign Cil.zero, location))
     | other -> (false, Cil.Instr [other])
   in
   let rewrite_return e location =
     match e with
     | Cil.UnOp (Cil.LNot, _, _) 
     | Cil.BinOp (Cil.Lt, _, _, _) 
     | Cil.BinOp (Cil.Le, _, _, _) 
     | Cil.BinOp (Cil.Gt, _, _, _) 
     | Cil.BinOp (Cil.Ge, _, _, _) 
     | Cil.BinOp (Cil.Eq, _, _, _) 
     | Cil.BinOp (Cil.Ne, _, _, _) -> 
        let ret value =
         Cil.mkBlock [Cil.mkStmt (Cil.Return (Some value, location))]
       in
       Cil.If (e, ret Cil.one, ret Cil.zero, location)
     | _ -> Cil.Return (Some e, location)
   in
   match stmt.Cil.skind with
   | Cil.Instr [instruction] ->
      stmt.Cil.skind <- snd (rewrite instruction)
   | Cil.Instr instructions ->
      let  flag_stmts = List.map 
        (fun inst -> let (f,s) = rewrite inst in (f, Cil.mkStmt s)) instructions in
      if List.exists (fun (a, _) -> a= true) flag_stmts then
        stmt.Cil.skind <- Cil.Block (Cil.mkBlock (List.map (fun (a,b) -> b) flag_stmts) )
   | Cil.Return (Some e, l) ->
      stmt.Cil.skind <- rewrite_return e l
   | _ -> ()
   end;
   Cil.DoChildren
end



let simplify file =
  let visitGlobal = function
   | Cil.GFun _ as fundec ->
     if Options.getValueOfBool "simplify" then begin
       Simplify.doGlobal fundec;
     end else ();
       ignore (Cil.visitCilGlobal (new changeBoolVisitor) fundec)
   | _ -> ()
  in
  Cil.iterGlobals file visitGlobal
;;
(* End of simplification of booleans used as integers               *)
(********************************************************************)

let make_cil_file file_name =
  let cil_file = (Frontc.parse file_name) ()
  in
  begin
    try
      let _ = Cil.visitCilFile (new frontc_error_detection_visitor) cil_file in
      ()
    with FrontcError loc ->
      failwith (loc.Cil.file ^ ":" ^ (string_of_int loc.Cil.line) ^
                ": " ^ "error: frontc reported an error --- see messages above.")
  end ;
  let simplified_cil_file = 
    if Options.getValueOfBool "simplemem" then 
      VampyreStats.time "simplemem" Simplemem.simplemem cil_file 
    else cil_file in
   VampyreStats.time "simplify" simplify simplified_cil_file ;
   VampyreStats.time "rmtmps" Rmtmps.removeUnusedTemps simplified_cil_file ;
   
   if (Options.getValueOfBool "initialize") then
      VampyreStats.time "put in initializer" put_in_initializer simplified_cil_file ;

   (* NO LONGER SUPPORTED 
    VampyreStats.time "make cfg" Cfg.make_cfg simplified_cil_file ;

    if (Options.getValueOfInt "O" >= 1 or Options.getValueOfBool "pe") then begin
      let _ = partiallyEvaluate simplified_cil_file in ()
    end;
*)
   let _ = VampyreStats.time "one ret" (Cil.visitCilFileSameGlobals (new oneret_visitor)) cil_file in
    VampyreStats.time "make cfg" make_cfg simplified_cil_file ;
    VampyreStats.time "rename locals" rename_locals simplified_cil_file; 

(* NO LONGER SUPPORTED
    if (Options.getValueOfInt "O" >= 2) then ignore (Panalysis.t_simplify simplified_cil_file []);
    if (Options.getValueOfInt "O" >= 1) then ignore (Panalysis.slice simplified_cil_file);
*)

    simplified_cil_file
      
let cil_varinfo_to_symbol v = v.Cil.vname

}}} *)

