(*
 * Copyright © 1990-2011 The Regents of the University of California. All rights reserved. 
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
(*
class t:
  object
    method add_var      : FixAstInterface.name -> Ctypes.refctype -> unit
    method add_sto      : string -> Ctypes.refstore -> unit
    method dump_annots  : FixConstraint.soln option -> unit
    method dump_infspec : CilMisc.dec list -> FixConstraint.soln -> unit
  end
*)

val annot_shape  : Shape.t Misc.StringMap.t 
                 -> Ssa_transform.t Misc.StringMap.t 
                 -> Ctypes.refcfun Misc.StringMap.t
                 -> unit
val annot_var    : FixAstInterface.name -> Ctypes.refctype -> unit
val annot_sto    : string -> Ctypes.refstore -> unit
val clear        : unit -> unit
val dump_annots  : FixConstraint.soln option -> unit
val dump_infspec : CilMisc.dec list -> FixConstraint.soln -> unit

