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

(* This file is part of the liquidC Project.*)

(****************************************************************)
(************** Misc Operations on CIL entities *****************)
(****************************************************************)

module F  = Format
open Cil
open Misc.Ops
 
(**********************************************************)
(**************** Build Call Graph ************************)
(**********************************************************)

class calleeVisitor calleesr = object(self)
  inherit nopCilVisitor
    method vinst = function
    | Call (_, Lval ((Var v), NoOffset), _, _) ->
        calleesr := v.vname :: !calleesr; DoChildren
    | _ -> DoChildren
end

let edges_of_file file = 
  let cil = Frontc.parse file () in
  Cil.foldGlobals cil begin
    fun es g -> match g with
    | Cil.GFun (fd,_) ->
        let u    = fd.svar.vname in
        let vsr  = ref [] in
        let _    = visitCilFunction (new calleeVisitor vsr) fd in
        let es'  = List.map (fun v -> (u,v)) !vsr in
        es' ++ es
    | _ -> es
  end [] 

(* API *)
let callgraph_of_files files = 
  Misc.flap edges_of_file files 

(******************************************************************************)
(************************ Ensure Expression/Lval Purity ***********************)
(******************************************************************************)

(** Ensures no expression contains a memory access and another
    operation. *)
class purifyVisitor (fd: fundec) = object(self)
  inherit nopCilVisitor

  method vexpr = function
    | Lval ((Mem _, _) as lv) ->
        let tmp = makeTempVar fd (typeOfLval lv) in
        let tlv = (Var tmp, NoOffset) in
        let _   = self#queueInstr [Set (tlv, Lval lv, !currentLoc)] in
          ChangeTo (Lval tlv)
    | _ -> DoChildren

  method vinst = function
    | Set (_, Lval _, _) -> SkipChildren
    | _                  -> DoChildren
end

let doGlobal = function
  | GFun (fd, _) -> fd.sbody <- visitCilBlock (new purifyVisitor fd) fd.sbody
  | _            -> ()

let purify file =
  iterGlobals file doGlobal

(**********************************************************)
(********** Check Expression/Lval Purity ******************)
(**********************************************************)

exception ContainsDeref

class checkPureVisitor = object(self)
  inherit nopCilVisitor
  method vlval = function
  | (Mem _), _ -> raise ContainsDeref 
  | _          -> DoChildren
end

(* API *)
let check_pure_expr e =
  try visitCilExpr (new checkPureVisitor) e |> ignore
  with ContainsDeref ->
    let _ = Errormsg.error "impure expr: %a" Cil.d_exp e in
    assertf "impure expr"

(**********************************************************)
(********** Stripping Casts from Exprs, Lvals *************)
(**********************************************************)

class castStripVisitor = object(self)
  inherit nopCilVisitor
    method vexpr = function
      | CastE (_, e) -> ChangeDoChildrenPost (e, id)
      | _            -> DoChildren
end

(* API *)
let stripcasts_of_lval = visitCilLval (new castStripVisitor)
let stripcasts_of_expr = visitCilExpr (new castStripVisitor)
