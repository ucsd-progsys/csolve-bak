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

module C  = Cil
module CM = CilMisc
module S  = Sloc

open Ctypes
open Misc.Ops

type shape =
  {vtyps : (Cil.varinfo * Ctypes.ctype) list;
   etypm : Ctypes.ctemap;
   store : Ctypes.store;
   anna  : Refanno.block_annotation array;
   conca : (Refanno.cncm * Refanno.cncm) array;
   theta : Refanno.ctab}

let rec typealias_attrs: C.typ -> C.attributes = function
  | C.TNamed (ti, a) -> a @ typealias_attrs ti.C.ttype
  | _                -> []

let fresh_heaptype (t: C.typ): ctype =
  let ats1 = typealias_attrs t in
    match C.unrollType t with
      | C.TInt (ik, _)                           -> CTInt (C.bytesSizeOfInt ik, index_top)
      | C.TEnum (ei, _)                          -> CTInt (C.bytesSizeOfInt ei.C.ekind, index_top)
      | C.TFloat _                               -> CTInt (CM.typ_width t, index_top)
      | C.TVoid _                                -> void_ctype
      | C.TPtr (t, ats2) | C.TArray (t, _, ats2) -> CTRef (S.fresh S.Abstract, if CM.has_array_attr (ats1 @ ats2) then ISeq (0, CM.typ_width t, Pos) else IInt 0)
      | _                                        -> halt <| C.bug "Unimplemented fresh_heaptype: %a@!@!" C.d_type t
