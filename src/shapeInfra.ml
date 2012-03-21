(*
 * Copyright © 1990-2009 The Regents of the University of California. All rights reserved. 
 *
 * Permission is hereby granted, without written agreement and without 
 * license or royalty fees, to use, copy, modify, and distribute this 
 * software and its documentation for any purpose, provided that the 
 * above copyright notice and the following two paragraphs appear in 
 * all copies of this software. 
 * 
 * IN NO EVENT SHALL THE UNIVERSITY OF CALIFORNIA BE LIABLE TO ANY PARTY 
 * FOR DIRECT, INDIRECT, SPECIAL, INCIDENTAL, OR CONSEQUENTIAL DAMAGES 
 * ARISING OUT OF THE USE OF THIS SOFTWARE AND ITS DOCUMENTATION, EVEN 
 * IF THE UNIVERSITY OF CALIFORNIA HAS BEEN ADVISED OF THE POSSIBILITY 
 * OF SUCH DAMAGE. 
 * 
 * THE UNIVERSITY OF CALIFORNIA SPECIFICALLY DISCLAIMS ANY WARRANTIES, 
 * INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY 
 * AND FITNESS FOR A PARTICULAR PURPOSE. THE SOFTWARE PROVIDED HEREUNDER IS 
 * ON AN "AS IS" BASIS, AND THE UNIVERSITY OF CALIFORNIA HAS NO OBLIGATION 
 * TO PROVIDE MAINTENANCE, SUPPORT, UPDATES, ENHANCEMENTS, OR MODIFICATIONS.
 *
 *)

open Ctypes
module Misc = FixMisc open Misc.Ops

module C  = Cil
module E  = Errormsg
module CM = CilMisc
module VM = CM.VarMap
module Cs = Constants
module S  = Sloc
module N  = Index
module Ct = I.CType
module FI = FixInterface
module FA = FixAstInterface
module FC = FixConstraint
module A  = Ast
module Sy = A.Symbol

let rec typealias_attrs: C.typ -> C.attributes = function
  | C.TNamed (ti, a) -> a @ typealias_attrs ti.C.ttype
  | _                -> []

(* Note that int refinements always have to include the constant index
   0.  This is because we need to account for the fact that malloc
   allocates a block of zeroes - it would be tedious to account for
   this separately at all malloc call sites, so we just always ensure
   whatever int shape is on the heap always includes 0, which is
   sufficient and unproblematic so far. *)
let fresh_heaptype (t: C.typ): ctype =
  let ats1 = typealias_attrs t in
    match C.unrollType t with
      | C.TInt (ik, _)           -> Int (C.bytesSizeOfInt ik, N.top)
      | C.TEnum (ei, _)          -> Int (C.bytesSizeOfInt ei.C.ekind, N.top)
      | C.TFloat _               -> Int (CM.typ_width t, N.top)
      | C.TVoid _                -> void_ctype
      | C.TPtr (C.TFun _ as f,_) ->
        let fspec = Typespec.preRefcfunOfType f in
          Ctypes.FRef (Ctypes.RefCTypes.CFun.map
                         (Ctypes.RefCTypes.CType.map fst) fspec,
                       Index.of_int 0)
      | C.TPtr (tb, ats) | C.TArray (tb, _, ats) as t ->
           Typespec.ptrReftypeOfSlocAttrs (S.fresh_abstract [CM.srcinfo_of_type t None]) tb ats
        |> Ctypes.ctype_of_refctype
      | _ -> halt <| C.bug "Unimplemented fresh_heaptype: %a@!@!" C.d_type t

let rec base_ctype_of_binop_result = function
  | C.PlusA | C.MinusA | C.Mult | C.Div                     -> base_ctype_of_arith_result
  | C.PlusPI | C.IndexPI | C.MinusPI                        -> base_ctype_of_ptrarith_result
  | C.MinusPP                                               -> base_ctype_of_ptrminus_result
  | C.Lt | C.Gt | C.Le | C.Ge | C.Eq | C.Ne                 -> base_ctype_of_rel_result
  | C.LAnd | C.LOr                                          -> base_ctype_of_logical_result
  | C.Mod | C.BAnd | C.BOr | C.BXor | C.Shiftlt | C.Shiftrt -> base_ctype_of_bitop_result
  | bop -> E.s <| C.bug "Unimplemented base_ctype_of_binop_result: %a@!@!" C.d_binop bop

and base_ctype_of_arith_result rt _ _ =
  Int (CM.typ_width rt, Index.top)

and base_ctype_of_ptrarith_result pt ctv1 ctv2 = match C.unrollType pt, ctv1, ctv2 with
  | C.TPtr _, Ref (s, _), Int (n, _) when n = CM.int_width -> Ref (s, Index.top)
  | _ -> E.s <| C.bug "Type mismatch in base_ctype_of_ptrarith_result@!@!"

and base_ctype_of_ptrminus_result _ _ _ =
  Int (CM.typ_width !C.upointType, Index.top)

and base_ctype_of_rel_result _ _ _ =
  Int (CM.int_width, Index.nonneg)

and base_ctype_of_logical_result _ _ _ =
  Int (CM.int_width, Index.nonneg)

and base_ctype_of_bitop_result rt _ _ =
  Int (CM.typ_width rt, Index.top)

and base_ctype_of_unop_result rt = function
  | C.BNot | C.Neg -> Int (CM.typ_width rt, Index.top)
  | C.LNot         -> Int (CM.typ_width rt, Index.nonneg)

let reft_of_ctype ct =
  let vv, p = ScalarCtypes.non_null_pred_of_ctype ct in
    FC.make_reft vv (FI.sort_of_prectype ct) [FC.Conc p]

let fixenv_of_ctypeenv ve =
  VM.fold
    (fun v ct fe -> Sy.SMap.add (Sy.of_string v.C.vname) (reft_of_ctype ct) fe)
    ve Sy.SMap.empty

class exprTyper (ve,fe) = object (self)
  val tbl = Hashtbl.create 17
  val fe  = ref fe
  val fce = fixenv_of_ctypeenv ve

  method ctype_of_exp e =
    Misc.do_memo tbl self#ctype_of_exp_aux e e

  (* pmr: major refactoring todo - this is basically recomputing the index
     solution, which we should just be able to get as a map from the index
     solver *)
  method private ctype_of_exp_aux e =
    let ct = self#base_ctype_of_exp e in
      match e with
        | C.Lval _ -> ct
        | _        ->
          let so   = FI.sort_of_prectype ct in
          let vv   = Sy.value_variable so in
          let p    = e |> CilInterface.reft_of_cilexp vv |> snd in
          let reft = FC.make_reft vv so [FC.Conc p] in
          let idx  = N.glb (Ct.refinement ct) (N.index_of_reft fce (fun _ -> assert false) reft) in
            let res = Ct.map (const idx) ct in
            let _ = Pretty.printf "EXPRESSION %a@!Type: %a@!Pred: %s@!Index: %a@!@!"
                      C.d_exp e Ct.d_ctype ct (A.Predicate.to_string p) Index.d_index idx in
              res

  method private base_ctype_of_exp = function
    | C.Const c                     -> Ct.of_const c
    | C.Lval lv | C.StartOf lv      -> self#base_ctype_of_raw_lval lv
    | C.UnOp (uop, e, t)            -> base_ctype_of_unop_result t uop
    | C.BinOp (bop, e1, e2, t)      -> base_ctype_of_binop_result bop t (self#ctype_of_exp e1) (self#ctype_of_exp e2)
    | C.CastE (C.TPtr (C.TFun _ as f,_), C.Const c) ->
      self#base_ctype_of_constfptr f c
    | C.CastE (C.TPtr _, C.Const c) -> self#base_ctype_of_constptr c
    | C.CastE (ct, e)               -> self#base_ctype_of_cast ct e
    | C.SizeOf t                    -> Int (CM.int_width, Index.IInt (CM.typ_width t))
    | C.AddrOf lv                   -> self#base_ctype_of_addrof lv
    | e                             -> E.s <| C.error "Unimplemented base_ctype_of_exp: %a@!@!" C.d_exp e

  method private base_ctype_of_constfptr f c = match c with
    | C.CInt64 (v, ik, so)
        when v = Int64.zero ->
        let fspec = Typespec.preRefcfunOfType f in
          Ctypes.FRef (Ctypes.RefCTypes.CFun.map
                         (Ctypes.RefCTypes.CType.map fst) fspec,
                       Index.IBot)

  method private base_ctype_of_constptr c = match c with
    | C.CStr _ ->
        let s = S.fresh_abstract [CM.srcinfo_of_constant c None] in 
        Ref (s, Index.IInt 0)
    | C.CInt64 (v, ik, so) 
      when v = Int64.zero ->
        let s = S.fresh_abstract [CM.srcinfo_of_constant c None] in 
        Ref (s, Index.IBot)
    | _ -> 
        E.s <| C.error "Cannot cast non-zero, non-string constant %a to pointer@!@!" C.d_const c

  method private base_ctype_of_raw_lval = function
    | C.Var v, C.NoOffset         -> asserti (VM.mem v ve) "Cannot_find: %s" v.C.vname; VM.find v ve
    | (C.Mem e, C.NoOffset) as lv -> lv |> C.typeOfLval |> fresh_heaptype
    | lv                          -> E.s <| C.bug "base_ctype_of_lval got lval with offset: %a@!@!" C.d_lval lv

  method ctype_of_lval lv =
    self#ctype_of_exp (C.Lval lv)

  method private base_ctype_of_addrof = function
    | C.Var v, C.NoOffset when CM.is_fun v ->
      let fspec,_ = VM.find v !fe in
      FRef (fspec, Index.IInt 0)
    | lv -> 
        E.s <| C.error "Unimplemented base_ctype_of_addrof: %a@!@!" C.d_lval lv

  method private base_ctype_of_cast ct e =
    let ctv = self#base_ctype_of_exp e in
      match C.unrollType ct, C.unrollType <| C.typeOf e with
        | C.TInt (ik, _), C.TPtr _   -> Int (C.bytesSizeOfInt ik, Index.nonneg)
        | C.TInt (ik, _), C.TFloat _ -> Int (C.bytesSizeOfInt ik, Index.top)
        | C.TFloat (fk, _), _        -> Int (CM.bytesSizeOfFloat fk, Index.top)
        | C.TInt (ik, _), C.TInt _   ->
          begin match ctv with
            | Int (n, ie) ->
              let iec =
                if n <= C.bytesSizeOfInt ik then
                (* pmr: what about the sign bit?  this may not always be safe *)
                  if C.isSigned ik then ie else Index.unsign ie
                else if not !Cs.safe then begin
                  C.warn "Unsoundly assuming cast is lossless@!@!" |> ignore;
                  if C.isSigned ik then ie else Index.unsign ie
                end else
                  Index.top
              in Int (C.bytesSizeOfInt ik, iec)
            | _ -> E.s <| C.error "Got bogus type in int-int cast@!@!"
          end
        | _ -> ctv
end
