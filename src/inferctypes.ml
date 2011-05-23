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

module M   = Misc
module P   = Pretty
module C   = Cil
module Cs  = Constants
module E   = Errormsg
module ST  = Ssa_transform
module RA  = Refanno
module S   = Sloc
module SLM = S.SlocMap
module CM  = CilMisc
module VM  = CM.VarMap
module SM  = M.StringMap
module FI  = FixInterface
module Sh  = Shape
module FF  = FinalFields

open Ctypes
open ShapeInfra
open M.Ops

module LDesc = I.LDesc
module Store = I.Store
module Ct    = I.CType
module CFun  = I.CFun
module Field = I.Field
module CSpec = I.Spec 

(******************************************************************************)
(******************************** Environments ********************************)
(******************************************************************************)

module IM = M.IntMap

type ctvenv = ctype VM.t

type funenv = (cfun * ctvenv) VM.t

let funenv_entry_of_cfun cf =
  (cf, VM.empty)

let ctenv_of_funenv fe =
  VM.map fst fe

let funenv_of_ctenv env =
  VM.fold (fun f cf fe -> VM.add f (funenv_entry_of_cfun cf) fe) env VM.empty

type env = funenv * ctvenv

type ctvemap = I.ctemap

(******************************************************************************)
(***************************** Constraint Solving *****************************)
(******************************************************************************)

exception Unify of ctype * ctype

let store_add_absent loc l i ctv sto =
  SLM.add l (LDesc.add loc i (Field.create Ctypes.Final ctv) (Store.find_or_empty l sto)) sto

let rec unify_ctypes loc ct1 ct2 sub sto = match Ct.subs sub ct1, Ct.subs sub ct2 with
  | _, _                     when ct1 = ct2  -> (sub, sto)
  | Ref (s1, _), Ref (s2, _) when S.eq s1 s2 -> (sub, sto)
  | Int (n1, _), Int (n2, _) when n1 = n2    -> (sub, sto)
  | Ref (s1, _), Ref (s2, _)                 -> unify_locations loc s1 s2 sub sto
  | _                                        -> raise (Unify (ct1, ct2))

and unify_locations loc s1 s2 sub sto =
  let sub = S.Subst.extend s1 s2 sub in
  let ld1 = sto |> Store.find_or_empty s1 |> LDesc.subs sub in
  let sto = Store.remove sto s1 |> SLM.add s2 (Store.find_or_empty s2 sto) |> Store.subs sub in
    LDesc.fold (fun (sub, sto) i f -> store_add loc s2 i (Field.type_of f) sub sto) (sub, sto) ld1

and store_add loc s i ct sub sto =
  let s  = S.Subst.apply sub s in
  let ct = Ct.subs sub ct in
  try match i with
    | Index.IBot                     -> (sub, sto)
    | Index.ICClass _ | Index.IInt _ ->
      let ld = Store.find_or_empty s sto in
        match LDesc.find i ld with
          | []   -> (sub, store_add_absent loc s i ct sto)
          | flds ->
            let cts      = List.map (snd <+> Field.type_of) flds in
            let sub, sto = List.fold_left (fun (sub, sto) ct2 -> unify_ctypes loc ct ct2 sub sto) (sub, sto) cts in
              if List.exists (fun (i2, _) -> Index.is_subindex i i2) flds then
                (* If this sequence is included in an existing one, there's nothing left to do *)
                (sub, sto)
              else
                (* Otherwise, remove overlapping elements and add one at the LUB of all indices. *)
                let ld = List.fold_left (fun ld (i2, _) -> LDesc.remove i2 ld) ld flds in
                let i  = List.fold_left (fun i (i2, _) -> Index.lub i i2) i flds in
                let ld = LDesc.add loc i (Field.create Ctypes.Final ct) ld in
                  (sub, SLM.add s ld sto)
  with e ->
    C.errorLoc loc "store_add: Can't fit %a: %a in location %a |-> %a"
      Index.d_index i Ct.d_ctype ct S.d_sloc s LDesc.d_ldesc (Store.find_or_empty s sto) |> ignore;
    raise e

(******************************************************************************)
(***************************** CIL Types to CTypes ****************************)
(******************************************************************************)

let _DEBUG_print_ve s ve =
  P.printf "%s START " s;
  VM.iter begin fun v ct ->
    ignore <| P.printf "[v=%s, ct=%a]" v.Cil.vname Ct.d_ctype ct
  end ve; 
  P.printf " END\n"

let constrain_lval et sub sto = function
  | (C.Var v, C.NoOffset)       -> (sub, sto)
  | (C.Mem e, C.NoOffset) as lv ->
    begin match et#ctype_of_exp e with
      | Ref (s, i) -> store_add !C.currentLoc s i (et#ctype_of_lval lv) sub sto
      | _          -> E.s <| C.bug "constraining ref lval gave back non-ref type in constrain_lval@!@!"
    end
  | lv -> E.s <| C.bug "constrain_lval got lval with offset: %a@!@!" C.d_lval lv

class exprConstraintVisitor (et, sub, sto) = object (self)
  inherit C.nopCilVisitor

  val sto = ref sto
  val sub = ref sub

  method get_sub_sto = (!sub, !sto)

  method private set_sub_sto (sub', sto') =
    sub := sub';
    sto := sto'

  method vexpr e =
    self#constrain_exp e;
    C.DoChildren

  method private constrain_constptr e = function
    | C.CInt64 _ -> ()
    | C.CStr _   ->
      begin match et#ctype_of_exp e with
        | Ref (s, _) -> self#set_sub_sto <| store_add !C.currentLoc s Index.nonneg (Int (1, Index.nonneg)) !sub !sto
        | _          -> assert false
      end
    | c -> E.s <| C.error "Cannot cast non-zero, non-string constant %a to pointer@!@!" C.d_const c

  method private constrain_exp = function
    | C.Const c                          -> ()
    | C.Lval lv | C.StartOf lv           -> let _ = P.printf "in constrain_exp lval@!@!" in self#set_sub_sto (constrain_lval et !sub !sto lv)
    | C.UnOp (uop, e, t)                 -> ()
    | C.BinOp (bop, e1, e2, t)           -> ()
    | C.CastE (C.TPtr _, C.Const c) as e -> self#constrain_constptr e c
    | C.CastE (ct, e)                    -> ()
    | C.SizeOf t                         -> ()
    | C.AddrOf lv                        -> ()
    | e                                  -> E.s <| C.error "Unimplemented constrain_exp_aux: %a@!@!" C.d_exp e
end

let constrain_exp et sub sto e =
  let ecv = new exprConstraintVisitor (et, sub, sto) in
  let _   = C.visitCilExpr (ecv :> C.cilVisitor) e in
    ecv#get_sub_sto

let constrain_args et sub sto es =
  List.fold_right begin fun e (cts, sub, sto) ->
    let sub, sto = constrain_exp et sub sto e in
      (et#ctype_of_exp e :: cts, sub, sto)
  end es ([], sub, sto)

let constrain_app (fs, _) et f sub sto lvo args =
  let cts, sub, sto = constrain_args et sub sto args in
  let cf, _         = VM.find f fs in
  let instslocs     = List.map (fun _ -> S.fresh_abstract ()) cf.qlocs in
  let annot         = List.map2 (fun sfrom sto -> RA.New (sfrom, sto)) cf.qlocs instslocs in
  let isub          = List.combine cf.qlocs instslocs in
  let ctfs          = List.map (Ct.subs isub <.> snd) cf.args in
  let ostore        = Store.subs isub cf.sto_out in
  let sub, sto      = Store.fold begin fun (sub, sto) s i fld ->
    store_add !C.currentLoc s i (Field.type_of fld) sub sto
  end (sub, sto) ostore in
  let sub, sto      = List.fold_left2 begin fun (sub, sto) cta ctf ->
    unify_ctypes !C.currentLoc cta ctf sub sto
  end (sub, sto) cts ctfs in
  let sto          = List.fold_left (fun sto s -> SLM.add s (Store.find_or_empty s sto) sto) sto (Store.domain ostore) in
    match lvo with
      | None    -> (annot, sub, sto)
      | Some lv ->
        let ctlv     = et#ctype_of_lval lv in
        let sub, sto = constrain_lval et sub sto lv in
        let sub, sto = unify_ctypes !C.currentLoc (Ct.subs isub cf.ret) ctlv sub sto in
          (annot, sub, sto)

let constrain_return et sub sto rtv = function
    | None   -> if Ct.is_void rtv then ([], sub, sto) else (C.error "Returning void value for non-void function\n\n" |> ignore; assert false)
    | Some e ->
      let sub, sto = constrain_exp et sub sto e in
      let sub, sto = unify_ctypes !C.currentLoc (et#ctype_of_exp e) rtv sub sto in
        ([], sub, sto)

let constrain_instr_aux env et (bas, sub, sto) i =
  let loc = i |> C.get_instrLoc >> (:=) C.currentLoc in
  match i with
  | C.Set (lv, e, _) ->
      let sub, sto = constrain_lval et sub sto lv in
      let sub, sto = constrain_exp et sub sto e in
      let ct1      = et#ctype_of_lval lv in
      let ct2      = et#ctype_of_exp e in
      let sub, sto = unify_ctypes loc ct1 ct2 sub sto in
        ([] :: bas, sub, sto)
  | C.Call (None, C.Lval (C.Var f, C.NoOffset), args, _) when CM.isVararg f.C.vtype ->
      let _ = CM.g_errorLoc !Cs.safe loc "constrain_instr cannot handle vararg call: %a@!@!" CM.d_var f |> CM.g_halt !Cs.safe in
      let _, sub, sto = constrain_args et sub sto args in
        ([] :: bas, sub, sto)
  | C.Call (lvo, C.Lval (C.Var f, C.NoOffset), args, _) ->
      let ba, sub, sto = constrain_app env et f sub sto lvo args in
        (ba :: bas, sub, sto)
  | C.Call (lvo, C.Lval (C.Mem _, _), args, _) ->
      let _ = CM.g_errorLoc !Cs.safe loc "constrain_instr cannot handle funptr call: %a@!@!" Cil.d_instr i |> CM.g_halt !Cs.safe in
      let _, sub, sto = constrain_args et sub sto args in
        ([] :: bas, sub, sto)
  | i -> E.s <| C.bug "Unimplemented constrain_instr: %a@!@!" C.dn_instr i

let constrain_instr env et is sub sto =
  let bas, sub, sto = List.fold_left (constrain_instr_aux env et) ([], sub, sto) is in
    (List.rev ([] :: bas), sub, sto)

let constrain_stmt env et rtv s sub sto =
  let _ = C.currentLoc := C.get_stmtLoc s.C.skind in
    match s.C.skind with
      | C.Instr is          -> constrain_instr env et is sub sto
      | C.If (e, _, _, _)   -> let sub, sto = constrain_exp et sub sto e in ([], sub, sto)
      | C.Break _           -> ([], sub, sto)
      | C.Continue _        -> ([], sub, sto)
      | C.Goto _            -> ([], sub, sto)
      | C.Block _           -> ([], sub, sto)       (* we'll visit this later as we iterate through blocks *)
      | C.Loop (_, _, _, _) -> ([], sub, sto)       (* ditto *)
      | C.Return (rexp, _)  -> constrain_return et sub sto rtv rexp
      | _                   -> E.s <| C.bug "Unimplemented constrain_stmt: %a@!@!" C.dn_stmt s

let constrain_phi_defs ve (sub, sto) (vphi, vdefs) =
  let loc = vphi.C.vdecl >> (:=) C.currentLoc in
    List.fold_left begin fun (sub, sto) (_, vdef) ->
      unify_ctypes loc (VM.find vdef ve) (VM.find vphi ve) sub sto
    end (sub, sto) vdefs

let constrain_phis ve phis sub sto =
  Array.to_list phis |> List.flatten |> List.fold_left (constrain_phi_defs ve) (sub, sto)

class exprMapVisitor (et) = object (self)
  inherit C.nopCilVisitor

  val em: ctemap ref = ref I.ExpMap.empty

  method get_em = !em

  method vexpr e =
    begin match e |> C.typeOf |> C.unrollType with
      | C.TFun _ -> () (* pmr: revisit - begging for an assert false here? *)
      | _        -> em := I.ExpMap.add e (et#ctype_of_exp e) !em
    end;
    C.DoChildren

  method vlval lv =
    self#vexpr (C.Lval lv) |> ignore;
    C.DoChildren
end

let constrain_fun fs cf ve sto {ST.fdec = fd; ST.phis = phis; ST.cfg = cfg} =
  let loc          = fd.C.svar.C.vdecl >> (:=) C.currentLoc in
  let sub, sto     = List.fold_left2 begin fun (sub, sto) (_, fct) bv ->
    unify_ctypes loc fct (VM.find bv ve) sub sto
  end (S.Subst.empty, sto) cf.args fd.C.sformals in
  let sub, sto     = constrain_phis ve phis sub sto in
  let et           = new exprTyper (ve) in
  let blocks       = cfg.Ssa.blocks in
  let bas          = Array.make (Array.length blocks) [] in
  let sub, sto     =
    M.array_fold_lefti begin fun i (sub, sto) b ->
      let ba, sub, sto = constrain_stmt (fs, ve) et cf.ret b.Ssa.bstmt sub sto in
        Array.set bas i ba;
        (sub, sto)
    end (sub, sto) blocks
  in
  let emv = new exprMapVisitor (et) in
  let _   = C.visitCilFunction (emv :> C.cilVisitor) fd in
  (emv#get_em, bas, sub, sto)

(******************************************************************************)
(**************************** Local Shape Inference ***************************)
(******************************************************************************)

let check_out_store_complete sto_out_formal sto_out_actual =
  Store.fold begin fun ok l i fld ->
    if SLM.mem l sto_out_formal && Store.find_index l i sto_out_formal = [] then begin
      C.error "Actual store has binding %a |-> %a: %a, missing from spec for %a\n\n" 
        S.d_sloc l Index.d_index i Field.d_field fld S.d_sloc l |> ignore;
      false
    end else
      ok
  end true sto_out_actual

let check_slocs_distinct error sub slocs =
  try
    let s1, s2 = Misc.find_pair (fun s1 s2 -> M.map_pair (S.Subst.apply sub) (s1, s2) |> M.uncurry S.eq) slocs in
      halt <| C.error "%a\n\n" error (s1, s2)
  with Not_found -> ()

(* pmr: should be obsoleted by same shape check *)

let revert_spec_names subaway st =
     st
  |> Store.domain
  |> List.fold_left (fun sub s -> S.Subst.extend (S.Subst.apply subaway s) s sub) []

type soln = store * ctype VM.t * ctvemap * RA.block_annotation array

let global_alias_error () (s1, s2) =
  C.error "Global locations %a and %a get unified in function body" S.d_sloc s1 S.d_sloc s2

let quantification_error () (s1, s2) =
  C.error "Quantified locations %a and %a get unified in function body" S.d_sloc s1 S.d_sloc s2

let global_quantification_error () (s1, s2) =
  C.error "Global and quantified locations get unified in function body (%a, %a)" S.d_sloc s1 S.d_sloc s2

let unified_instantiation_error () (s1, s2) =
  C.error "Call unifies locations which are separate in callee (%a, %a)" S.d_sloc s1 S.d_sloc s2

let check_annots_wf sub bas =
  Array.iter begin fun ba ->
    List.iter begin fun annots ->
         annots
      |> List.filter (function RA.New _ -> true | _ -> false)
      |> List.map (function RA.New (_, s) -> s | _ -> assert false)
      |> check_slocs_distinct unified_instantiation_error sub
    end ba
  end bas

let add_loc_if_missing sto s =
  SLM.add s (Store.find_or_empty s sto) sto

let check_sol cf vars gst em bas sub sto =
  let whole_store = Store.upd cf.sto_out gst in
  let _           = check_slocs_distinct global_alias_error sub (Store.domain gst) in
  let _           = check_slocs_distinct quantification_error sub cf.qlocs in
  let _           = check_slocs_distinct global_quantification_error sub (Store.domain whole_store) in
  let _           = check_annots_wf sub bas in
  let revsub      = revert_spec_names sub whole_store in
  let sto         = Store.subs revsub sto in
  let sto         = cf |> CFun.slocs |> List.fold_left add_loc_if_missing sto in
  let sto         = List.fold_left add_loc_if_missing sto (Store.slocs sto) in
  let sub         = S.Subst.compose revsub sub in
    if check_out_store_complete whole_store sto then
      (sub, SLM.fold (fun s _ sto -> SLM.remove s sto) gst sto)
    else
         halt
      <| C.error "Failed checking store typing:\nStore:\n%a\n\ndoesn't match expected type:\n\n%a\n\nGlobal store:\n\n%a\n\n"
          Store.d_store sto
          CFun.d_cfun cf
          Store.d_store gst

let d_vartypes () vars =
  P.docList ~sep:(P.dprintf "@!") (fun (v, ct) -> P.dprintf "%s: %a" v.C.vname Ct.d_ctype ct) () vars

let fresh_sloc_of = function
  | Ref (s, i) -> Ref (S.fresh_abstract (), i)
  | c          -> c

let fresh_local_slocs ve =
  VM.mapi (fun v ct -> if v.C.vglob then ct else fresh_sloc_of ct) ve

exception LocationMismatch of S.t * LDesc.t * S.t * LDesc.t

let assert_location_inclusion l1 ld1 l2 ld2 =
  (* Polymorphism hack! *)
  if ld2 = LDesc.empty then
    ()
  else
    LDesc.fold begin fun _ pl _ ->
      if LDesc.mem pl ld2 then () else raise (LocationMismatch (l1, ld1, l2, ld2))
    end () ld1

let assert_call_no_physical_subtyping fe f store gst annots =
  let cf, _ = VM.find f fe in
    List.iter begin function
      | RA.New (scallee, scaller) ->
          let sto = if SLM.mem scaller store then store else gst in
            assert_location_inclusion
              scaller (SLM.find scaller sto)
              scallee (SLM.find scallee cf.sto_out)
      | _ -> ()
    end annots

let assert_no_physical_subtyping fe cfg anna store gst =
  try
    Array.iteri begin fun i b ->
      match b.Ssa.bstmt.C.skind with
        | C.Instr is ->
            List.iter2 begin fun i annots ->
              let _  = C.currentLoc := C.get_instrLoc i in
                match i with
                  | C.Call (_, C.Lval (C.Var f, _), _, _) -> assert_call_no_physical_subtyping fe f store gst annots
                  | _                                     -> ()
            end is anna.(i)
        | _ -> ()
    end cfg.Ssa.blocks
  with LocationMismatch (l1, ld1, l2, ld2) ->
    ignore <|
        C.error "Location mismatch:\n%a |-> %a\nis not included in\n%a |-> %a\n"
          S.d_sloc l1 LDesc.d_ldesc ld1 S.d_sloc l2 LDesc.d_ldesc ld2;
    exit 1

let infer_shape fe ve gst scim (cf, sci, vm) =
  let ve                    = vm |> CM.vm_union ve |> fresh_local_slocs in
  let sto                   = Store.upd cf.sto_out gst in
  let em, bas, sub, sto     = constrain_fun fe cf ve sto sci in
  let _                     = C.currentLoc := sci.ST.fdec.C.svar.C.vdecl in
  let sub, sto              = check_sol cf ve gst em bas sub sto in
  let vtyps                 = VM.map (Ct.subs sub) ve in
  let vtyps                 = VM.fold (fun vi vt vtyps -> if vi.C.vglob then vtyps else VM.add vi vt vtyps) vtyps VM.empty in
  let em                    = I.ExpMap.map (Ct.subs sub) em in
  let bas                   = Array.map (RA.subs sub) bas in
  let annot, conca, theta   = RA.annotate_cfg sci.ST.cfg (Store.domain gst) em bas in
  let _                     = assert_no_physical_subtyping fe sci.ST.cfg annot sto gst in
  let nasa                  = NotAliased.non_aliased_locations sci.ST.cfg em conca annot in
    {Sh.vtyps   = CM.vm_to_list vtyps;
     Sh.etypm   = em;
     Sh.store   = sto;
     Sh.anna    = annot;
     Sh.conca   = conca;
     Sh.theta   = theta;
     Sh.nasa    = nasa;
     Sh.ffmsa   = Array.create 0 (SLM.empty, []); (* filled in by finalFields *)}

let declared_funs cil =
  C.foldGlobals cil begin fun fs -> function
    | C.GFun (fd, _)                                      -> fd.C.svar :: fs
    | C.GVarDecl (vi, _) when C.isFunctionType vi.C.vtype -> vi :: fs
    | _                                                   -> fs
  end []

let print_shape fname cf gst {Sh.vtyps = locals; Sh.store = st; Sh.anna = annot; Sh.ffmsa = ffmsa} =
  let _ = P.printf "%s@!" fname in
  let _ = P.printf "============@!@!" in
  let _ = P.printf "Signature:@!" in
  let _ = P.printf "----------@!@!" in
  let _ = P.printf "%a@!@!" CFun.d_cfun cf in
  let _ = P.printf "Locals:@!" in
  let _ = P.printf "-------@!@!" in
  let _ = P.printf "%a@!@!" d_vartypes locals in
  let _ = P.printf "Store:@!" in
  let _ = P.printf "------@!@!" in
  let _ = P.printf "%a@!@!" Store.d_store st in
  let _ = P.printf "Global Store:@!" in
  let _ = P.printf "------@!@!" in
  let _ = P.printf "%a@!@!" Store.d_store gst in
  let _ = P.printf "Annotations:@!" in
  let _ = P.printf "------@!@!" in
  let _ = P.printf "%a@!@!" RA.d_block_annotation_array annot in
  let _ = P.printf "Final Fields:@!" in
  let _ = P.printf "------@!@!" in
  let _ = P.printf "%a@!@!" FinalFields.d_final_fields ffmsa in
    ()

let print_shapes spec shpm =
  let funspec, storespec = CSpec.funspec spec, CSpec.store spec in
    if !Cs.verbose_level >= Cs.ol_ctypes || !Cs.ctypes_only then
      SM.iter (fun fname shp -> print_shape fname (SM.find fname funspec |> fst) storespec shp) shpm

let _DEBUG_ADD vi ct ve = 
  let _   = _DEBUG_print_ve "DEBUG ADD: BEFORE" ve in
  let _   = P.printf "DEBUG ADD: bind %s := %a \n" vi.Cil.vname Ct.d_ctype ct in
  let ve' = VM.add vi ct ve in
  let _   = _DEBUG_print_ve "DEBUG ADD: AFTER" ve' in
  ve'

(* API *)
let infer_shapes cil spec scis =
  let ve = C.foldGlobals cil begin fun ve -> function
             | C.GVarDecl (vi, loc) | C.GVar (vi, _, loc) when not (C.isFunctionType vi.C.vtype) ->
                begin try
                  CSpec.get_var vi.C.vname spec 
                  |> fst
                  |> Misc.flip (VM.add vi) ve
                with Not_found ->
                  halt <| C.errorLoc loc "Could not find spec for global var %a\n" CM.d_var vi
                 end
             | _ -> ve
           end VM.empty
  in
  let fe = declared_funs cil
           |> List.map (fun f -> (f, CSpec.get_fun f.C.vname spec |> fst))
           |> List.fold_left (fun fe (f, cf) -> VM.add f (funenv_entry_of_cfun cf) fe) VM.empty in
  let xm = SM.fold (fun _ (_, sci, _) xm -> VM.add sci.ST.fdec.C.svar sci xm) scis VM.empty in
  scis
  |> SM.map (infer_shape fe ve (CSpec.store spec) xm)
  |> FinalFields.infer_final_fields spec scis 
  >> print_shapes spec
