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

module Misc = FixMisc 
module P   = Pretty
module E   = Errormsg
module S   = Sloc
module SS  = S.SlocSet
module N   = Index
module C   = Cil
module CM  = CilMisc
module FC  = FixConstraint
module SM  = Misc.StringMap
module SLM = S.SlocMap

module SLMPrinter = P.MakeMapPrinter(SLM)

open Misc.Ops

let mydebug = false

(******************************************************************************)
(*********************************** Indices **********************************)
(******************************************************************************)


module IndexSetPrinter = P.MakeSetPrinter (N.IndexSet)

(******************************************************************************)
(****************************** Type Refinements ******************************)
(******************************************************************************)

module type CTYPE_REFINEMENT = sig
  type t
  val is_subref    : t -> t -> bool
  val of_const     : C.constant -> t
  val top          : t
  val d_refinement : unit -> t -> P.doc
end

module IndexRefinement = struct
  type t = Index.t

  let top          = Index.top
  let is_subref    = Index.is_subindex
  let d_refinement = Index.d_index
  
  let of_const = function
    | C.CInt64 (v, ik, _) -> Index.of_int (Int64.to_int v)
    | C.CChr c            -> Index.IInt (Char.code c)
    | C.CReal (_, fk, _)  -> Index.top
    | C.CStr _            -> Index.IInt 0
    | c                   -> halt <| E.bug "Unimplemented ctype_of_const: %a@!@!" C.d_const c
end

(******************************************************************************)
(************************* Binders ********************************************)
(******************************************************************************)

type binder  = N of Ast.Symbol.t
             | S of string 
             | I of Index.t 
             | Nil

let d_binder () = function 
  | N n -> P.text (Ast.Symbol.to_string n)
  | S s -> P.text s
  | I i -> P.dprintf "@@%a" Index.d_index i
  | Nil -> P.nil




(******************************************************************************)
(************************* Refctypes and Friends ******************************)
(******************************************************************************)

let reft_of_top = 
  let so = Ast.Sort.t_obj in
  let vv = Ast.Symbol.value_variable so in
  FC.make_reft vv so []

let d_reft () r =
  CM.doc_of_formatter (FC.print_reft_pred None) r
  (* WORKS: P.dprintf "@[%s@]" (Misc.fsprintf (FC.print_reft_pred None) r) *)

let d_index_reft () (i,r) = 
  P.dprintf "%a , %a" Index.d_index i d_reft r
  (*let di = Index.d_index () i in
  let dc = P.text " , " in
  let dr = d_reft () r in
  P.concat (P.concat di dc) dr
  *)

module Reft = struct
  type t           = Index.t * FC.reft
  let d_refinement = d_index_reft
  let is_subref    = fun ir1 ir2 -> assert false
  let of_const     = fun c -> assert false
  let top          = Index.top, reft_of_top 
  let ref_of_any   = Index.ind_of_any, reft_of_top
end

(******************************************************************************)
(***************************** Parameterized Types ****************************)
(******************************************************************************)

type finality =
  | Final
  | Nonfinal

type fieldinfo  = {fname : string option; ftype : Cil.typ option} 
type ldinfo     = {stype : Cil.typ option; any: bool} 

let dummy_fieldinfo  = {fname = None; ftype = None}
let dummy_ldinfo = {stype = None; any = false}
let any_ldinfo   = {stype = None; any = true }
let any_fldinfo  = {fname = None; ftype = None}

type 'a prectype =
  | Int  of int * 'a           (* fixed-width integer *)
  | Ref  of Sloc.t * 'a        (* reference *)
  | FRef of ('a precfun) * 'a  (* function reference *)
  | ARef                       (* a dynamic "blackhole" reference *)
  | Any                        (* the variable-width type of a "blackhole" *)


and 'a prefield = {  pftype     : 'a prectype
                   ; pffinal    : finality
                   ; pfloc      : C.location
                   ; pfinfo     : fieldinfo }

and effectptr  = Reft.t prectype

and effectset = effectptr SLM.t

and 'a preldesc = { plfields   : (Index.t * 'a prefield) list
                  ; plinfo     : ldinfo 
                  }

and 'a prestore = 'a preldesc Sloc.SlocMap.t
                * 'a precfun Sloc.SlocMap.t
                * 'a hf_appl list
               
and 'a hf_appl  = string * Sloc.t list * 'a list

and ref_hf_appl = FixConstraint.reft hf_appl

and 'a precfun =
    { args        : (string * 'a prectype) list;  (* arguments *)
      ret         : 'a prectype;                  (* return *)
      globlocs    : S.t list;                     (* unquantified locations *)
      sto_in      : 'a prestore;                  (* in store *)
      sto_out     : 'a prestore;                  (* out store *)
      effects     : effectset;                    (* heap effects *)
    }

type specType =
  | HasShape
  | IsSubtype
  | HasType

type 'a prespec = ('a precfun * specType) Misc.StringMap.t 
                * ('a prectype * specType) Misc.StringMap.t 
                * 'a prestore
                * specType SLM.t

let d_specTypeRel () = function
  | HasShape  -> P.text "::"
  | IsSubtype -> P.text "<:"
  | HasType   -> P.text "|-"

let specTypeMax st1 st2 = match st1, st2 with
  | HasShape, st | st, HasShape -> st
  | HasType, _   | _, HasType   -> HasType
  | _                           -> IsSubtype

let d_fieldinfo () = function
  | { fname = Some fn; ftype = Some t } -> 
      P.dprintf "/* FIELDINFO %s %a */" fn Cil.d_type t 
  | { ftype = Some t } -> 
      P.dprintf "/* FIELDINFO %a */" Cil.d_type t 
  | _ ->
      P.nil (* RJ: screws up the autospec printer. P.dprintf "/* FIELDINFO ??? */" *)

let d_ldinfo () = function
  | { stype = Some t } -> 
      P.dprintf "/* %a */" Cil.d_type t
  | _ -> 
      P.nil

let rec d_prectype d_refinement () = function
      | Int (n, r)  -> P.dprintf "int(%d, %a)" n d_refinement r
      | Ref (s, r)  -> P.dprintf "ref(%a, %a)" S.d_sloc s d_refinement r
      | FRef (f, r) -> P.dprintf "fref(<TBD>, %a)" d_refinement r
      | ARef        -> P.dprintf "aref(%a)" S.d_sloc Sloc.sloc_of_any
      | Any         -> P.dprintf "any"

let d_refctype = d_prectype Reft.d_refinement

let d_effectinfo = d_refctype

let d_storelike d_binding =
  SLMPrinter.docMap ~sep:(P.dprintf ";@!") (fun l d -> P.dprintf "%a |-> %a" S.d_sloc l d_binding d)

let prectype_subs subs = function
  | Ref  (s, i) -> Ref (S.Subst.apply subs s, i)
  | pct         -> pct

let fieldinfo_of_cilfield prefix v = 
  { fname = Some (prefix ^ v.Cil.fname)
  ; ftype = Some v.Cil.ftype 
  }

let rec unfold_compinfo prefix ci = 
  let _  = asserti ci.Cil.cstruct "TBD: unfold_compinfo: unions" in
  ci.Cil.cfields |> Misc.flap (unfold_fieldinfo prefix)

and unfold_fieldinfo prefix fi = 
  match Cil.unrollType fi.Cil.ftype with
  | Cil.TComp (ci, _) -> 
     unfold_compinfo (prefix ^  fi.Cil.fname ^ ".") ci
  | _ -> [fieldinfo_of_cilfield prefix fi]

let unfold_compinfo pfx ci = 
  unfold_compinfo pfx ci 
  >> wwhen mydebug (E.log "unfold_compinfo: pfx = <%s> result = %a\n"  pfx (CM.d_many_braces false d_fieldinfo))

let unfold_ciltyp = function 
  | Cil.TComp (ci,_) ->
      unfold_compinfo "" ci
      |> Misc.index_from 0 
      |> Misc.IntMap.of_list 
      |> (fun im _ i -> Misc.IntMap.find i im)
  | Cil.TArray (t',_,_) ->
      (fun _ i -> { fname = None ; ftype = Some t'})
  | t -> 
      (fun _ i -> { fname = None; ftype = Some t}) 






module EffectSet = struct
  type t = effectset

  let empty = SLM.empty

  let apply f effs =
    SLM.map f effs

  let maplisti f effs =
    effs |> SLM.to_list |>: Misc.uncurry f

  let subs sub effs =
    apply (prectype_subs sub) effs

  let find effs l =
    SLM.find l effs

  let mem effs l =
    SLM.mem l effs

  let add effs l eff =
    SLM.add l eff effs

  let domain effs =
    SLM.domain effs

  let d_effect () eptr =
    d_refctype () eptr

  let d_effectset () effs =
    P.dprintf "{@[%a@]}" (d_storelike d_effect) effs
end

module type CTYPE_DEFS = sig
  module R : CTYPE_REFINEMENT

  type refinement = R.t

  type ctype = refinement prectype
  type field = refinement prefield
  type ldesc = refinement preldesc
  type store = refinement prestore
  type cfun  = refinement precfun
  type spec  = refinement prespec
end

module MakeTypes (R : CTYPE_REFINEMENT): CTYPE_DEFS with module R = R = struct
  module R = R

  type refinement = R.t

  type ctype = refinement prectype
  type field = refinement prefield
  type ldesc = refinement preldesc
  type store = refinement prestore
  type cfun  = refinement precfun
  type spec  = refinement prespec
end

module IndexTypes = MakeTypes (IndexRefinement)
module ReftTypes  = MakeTypes (Reft)

module SIGS (T : CTYPE_DEFS) = struct
  module type CTYPE = sig
    type t = T.ctype

    exception NoLUB of t * t

    val refinement     : t -> T.refinement
    val set_refinement : t -> T.refinement -> t
    val map            : ('a -> 'b) -> 'a prectype -> 'b prectype
    val map_func       : ('a -> 'b) -> 'a precfun -> 'b precfun
    val d_ctype        : unit -> t -> P.doc
    val of_const       : Cil.constant -> t
    val is_subctype    : t -> t -> bool
    val width          : t -> int
    val sloc           : t -> Sloc.t option
    val subs           : Sloc.Subst.t -> t -> t
    val eq             : t -> t -> bool
    val collide        : Index.t -> t -> Index.t -> t -> bool
    val is_void        : t -> bool
  end

  module type FIELD = sig
    type t = T.field

    val get_finality  : t -> finality
    val set_finality  : t -> finality -> t
    val get_fieldinfo : t -> fieldinfo
    val set_fieldinfo : t -> fieldinfo -> t
    val is_final      : t -> bool
    val type_of       : t -> T.ctype
    val sloc_of       : t -> Sloc.t option
    val create        : finality -> fieldinfo -> T.ctype -> t
    val subs          : Sloc.Subst.t -> t -> t
    val map_type      : ('a prectype -> 'b prectype) -> 'a prefield -> 'b prefield
    val map2_type     : ('a prectype -> 'a prectype -> 'b prectype) ->
                        'a prefield -> 'b prefield
    val d_field       : unit -> t -> P.doc
  end

  module type LDESC = sig
    type t = T.ldesc

    exception TypeDoesntFit of Index.t * T.ctype * t

    val empty         : t
    val any           : t
    val eq            : t -> t -> bool
    val is_empty      : t -> bool
    val is_any        : t -> bool
    val is_read_only  : t -> bool
    val add           : Index.t -> T.field -> t -> t
    val create        : ldinfo -> (Index.t * T.field) list -> t
    val remove        : Index.t -> t -> t
    val mem           : Index.t -> t -> bool
    val referenced_slocs : t -> Sloc.t list
    val find          : Index.t -> t -> (Index.t * T.field) list
    val foldn         : (int -> 'a -> Index.t -> T.field -> 'a) -> 'a -> t -> 'a
    val fold          : ('a -> Index.t -> T.field -> 'a) -> 'a -> t -> 'a
    val subs          : Sloc.Subst.t -> t -> t
    val map           : ('a prefield -> 'b prefield) -> 'a preldesc -> 'b preldesc
    val map2          : ('a prefield -> 'b prefield) ->
                        'a preldesc -> 'a preldesc -> 'b preldesc
    val mapn          : (int -> Index.t -> 'a prefield -> 'b prefield) -> 'a preldesc -> 'b preldesc
    val iter          : (Index.t -> T.field -> unit) -> t -> unit
    val indices       : t -> Index.t list
    val bindings      : t -> (Index.t * T.field) list

    val set_ldinfo    : t -> ldinfo -> t
    val get_ldinfo    : t -> ldinfo
    val set_stype     : t -> Cil.typ option -> t
    val d_ldesc       : unit -> t -> P.doc
    val decorate      : Sloc.t -> Cil.typ -> t -> t
    
    val d_vbind       : unit -> (binder * (T.ctype * Cil.typ)) -> P.doc
    val d_sloc_ldesc  : unit -> (Sloc.t * t) -> P.doc
  end

  module type STORE = sig
    type t = T.store

    val empty        : t
    val bindings     : 'a prestore -> (Sloc.t * 'a preldesc) list * (Sloc.t * 'a precfun) list
    val abstract     : t -> t
    val join_effects :
      t ->
      effectset ->
      (Sloc.t * (T.ldesc * effectptr)) list * (Sloc.t * (T.cfun * effectptr)) list
    val domain       : t -> Sloc.t list
    val mem          : t -> Sloc.t -> bool
    val closed       : t -> t -> bool
    val reachable    : t -> Sloc.t -> Sloc.t list
    val restrict     : t -> Sloc.t list -> t
    val map          : ('a prectype -> 'b prectype) -> 'a prestore -> 'b prestore
    val map_variances : ('a prectype -> 'b prectype) ->
                        ('a prectype -> 'b prectype) ->
                        'a prestore ->
                        'b prestore
    val map_ldesc    : (Sloc.t -> 'a preldesc -> 'a preldesc) -> 'a prestore -> 'a prestore
    val partition    : (Sloc.t -> bool) -> t -> t * t
    val remove       : t -> Sloc.t -> t
    val upd          : t -> t -> t
  (** [upd st1 st2] returns the store obtained by adding the locations from st2 to st1,
      overwriting the common locations of st1 and st2 with the blocks appearing in st2 *)
    val subs         : Sloc.Subst.t -> t -> t
    val ctype_closed : T.ctype -> t -> bool
    val indices      : t -> Index.t list

    val data         : t -> t

    val d_store_addrs: unit -> t -> P.doc
    val d_store      : unit -> t -> P.doc

    module Data: sig
      val add           : t -> Sloc.t -> T.ldesc -> t
      val bindings      : t -> (Sloc.t * T.ldesc) list
      val domain        : t -> Sloc.t list
      val mem           : t -> Sloc.t -> bool
      val ensure_sloc   : t -> Sloc.t -> t
      val find          : t -> Sloc.t -> T.ldesc
      val find_or_empty : t -> Sloc.t -> T.ldesc
      val map           : (T.ctype -> T.ctype) -> t -> t
      val fold_fields   : ('a -> Sloc.t -> Index.t -> T.field -> 'a) -> 'a -> t -> 'a
      val fold_locs     : (Sloc.t -> T.ldesc -> 'a -> 'a) -> 'a -> t -> 'a
    end

    module Function: sig
      val add       : 'a prestore -> Sloc.t -> 'a precfun -> 'a prestore
      val bindings  : 'a prestore -> (Sloc.t * 'a precfun) list
      val domain    : t -> Sloc.t list
      val mem       : 'a prestore -> Sloc.t -> bool
      val find      : 'a prestore -> Sloc.t -> 'a precfun
      val fold_locs : (Sloc.t -> 'b precfun -> 'a -> 'a) -> 'a -> 'b prestore -> 'a
    end

    module Unify: sig
      exception UnifyFailure of Sloc.Subst.t * t

      val unify_ctype_locs : t -> Sloc.Subst.t -> T.ctype -> T.ctype -> t * Sloc.Subst.t
      val unify_overlap    : t -> Sloc.Subst.t -> Sloc.t -> Index.t -> t * Sloc.Subst.t
      val add_field        : t -> Sloc.Subst.t -> Sloc.t -> Index.t -> T.field -> t * Sloc.Subst.t
      val add_fun          : t -> Sloc.Subst.t -> Sloc.t -> T.cfun -> t * Sloc.Subst.t
    end
  end

  module type CFUN = sig
    type t = T.cfun

    val d_cfun          : unit -> t -> P.doc
    val map             : ('a prectype -> 'b prectype) -> 'a precfun -> 'b precfun
    val map_variances   : ('a prectype -> 'b prectype) ->
                          ('a prectype -> 'b prectype) ->
                          'a precfun ->
                          'b precfun
    val map_ldesc       : (Sloc.t -> 'a preldesc -> 'a preldesc) -> 'a precfun -> 'a precfun
    val apply_effects   : (effectptr -> effectptr) -> t -> t
    val well_formed     : T.store -> t -> bool
    val normalize_names :
      t ->
      t ->
      (T.store -> Sloc.Subst.t -> (string * string) list -> T.ctype -> T.ctype) ->
      (T.store -> Sloc.Subst.t -> (string * string) list -> effectptr -> effectptr) ->
      t * t
    val same_shape      : t -> t -> bool
    val quantified_locs : t -> Sloc.t list
    val instantiate     : CM.srcinfo -> t -> t * S.Subst.t
    val make            : (string * T.ctype) list -> S.t list -> T.store -> T.ctype -> T.store -> effectset -> t
    val subs            : t -> Sloc.Subst.t -> t
    val indices         : t -> Index.t list
  end

  module type SPEC = sig
    type t      = T.spec

    val empty   : t

    val map : ('a prectype -> 'b prectype) -> 'a prespec -> 'b prespec
    val add_fun : bool -> string -> T.cfun * specType -> t -> t
    val add_var : bool -> string -> T.ctype * specType -> t -> t
    val add_data_loc : Sloc.t -> T.ldesc * specType -> t -> t
    val add_fun_loc  : Sloc.t -> T.cfun * specType -> t -> t
    val store   : t -> T.store
    val funspec : t -> (T.cfun * specType) Misc.StringMap.t
    val varspec : t -> (T.ctype * specType) Misc.StringMap.t
    val locspectypes : t -> specType SLM.t

    val make    : (T.cfun * specType) Misc.StringMap.t ->
                  (T.ctype * specType) Misc.StringMap.t ->
                  T.store ->
                  specType SLM.t ->
                  t
    val add     : t -> t -> t
    val d_spec  : unit -> t -> P.doc
  end
end

module type S = sig
  module T : CTYPE_DEFS

  module CType : SIGS (T).CTYPE
  module Field : SIGS (T).FIELD
  module LDesc : SIGS (T).LDESC
  module Store : SIGS (T).STORE
  module CFun  : SIGS (T).CFUN
  module Spec  : SIGS (T).SPEC

  module ExpKey: sig
    type t = Cil.exp
    val compare: t -> t -> int
  end

  module ExpMap: Map.S with type key = ExpKey.t

  module ExpMapPrinter: sig
    val d_map:
      ?dmaplet:(P.doc -> P.doc -> P.doc) ->
      string ->
      (unit -> ExpMap.key -> P.doc) ->
      (unit -> 'a -> P.doc) -> unit -> 'a ExpMap.t -> P.doc
  end

  type ctemap = CType.t ExpMap.t

  val d_ctemap: unit -> ctemap -> P.doc
end

module Make (T: CTYPE_DEFS): S with module T = T = struct
  module T   = T
  module SIG = SIGS (T)

  (***********************************************************************)
  (***************************** Types ***********************************)
  (***********************************************************************)

  module rec CType: SIG.CTYPE = struct
    type t = T.ctype

    let refinement = function
      | Int (_, r) | Ref (_, r) | FRef (_, r) -> r
      | ARef | Any -> T.R.top

    let set_refinement ct r = match ct with
      | Int (w, _)  -> Int (w, r)
      | Ref (s, _)  -> Ref (s, r)
      | FRef (f, _) -> FRef (f, r)
      | ARef        -> ARef
      | Any         -> Any

    let rec map f = function
      | Int (i, x) -> Int (i, f x)
      | Ref (l, x) -> Ref (l, f x)
      | FRef(g, x) -> FRef (map_func f g, f x)
      | ARef      -> ARef
      | Any       -> Any    
    and map_field f ({pftype = typ} as pfld) =
      {pfld with pftype = map f typ}
    and map_desc f {plfields = flds; plinfo = info} =
      {plfields = List.map (id <**> map_field f) flds; plinfo = info}
    and map_sto f (desc, func, _) = (Sloc.SlocMap.map (map_desc f) desc,
      Sloc.SlocMap.map (map_func f) func, [])
    and map_func f ({args=args; ret=ret; sto_in=stin; sto_out=stout} as g) =
	{g with args    = List.map (id <**> (map f)) args;
	        ret     = map f ret;
	        sto_in  = map_sto f stin;
	        sto_out = map_sto f stout}

    let d_ctype () = function
      | Int (n, i)  -> P.dprintf "int(%d, %a)" n T.R.d_refinement i
      | Ref (s, i)  -> P.dprintf "ref(%a, %a)" S.d_sloc s T.R.d_refinement i
      | FRef (g, i) -> P.dprintf "fref(@[%a,@!%a@])" CFun.d_cfun g T.R.d_refinement i
      | ARef        -> P.dprintf "aref(%a)" S.d_sloc S.sloc_of_any
      | Any         -> P.dprintf "any"  

    let width = function
      | Int (n, _) -> n
      | Any        -> 0
      | _          -> CM.int_width
    
    let sloc = function
      | Ref (s, _) -> Some s
      | ARef       -> Some S.sloc_of_any
      | _          -> None

    let subs subs = function
      | Ref (s, i) -> Ref (S.Subst.apply subs s, i)
      | pct        -> pct

    exception NoLUB of t * t

    let is_subctype pct1 pct2 =                        
      match pct1, pct2 with
        | Int (n1, r1), Int (n2, r2) when n1 = n2    -> T.R.is_subref r1 r2
        | Ref (s1, r1), Ref (s2, r2) when S.eq s1 s2 -> T.R.is_subref r1 r2
	  (* not sure what the semantics are here
	     should is_subctype be called on the arguments of f1/f2 etc? *)
	      | FRef (f1, r1), FRef (f2, r2) when f1 = f2  -> T.R.is_subref r1 r2
        | ARef, ARef                                 -> true
        | Any, Any                                   -> true
        | Int _, Any                                 -> true
        | Any, Int _                                 -> true
        | _                                          -> false

    let of_const c =
      let r = T.R.of_const c in
        match c with
          | C.CInt64 (v, ik, _) -> Int (C.bytesSizeOfInt ik, r)
          | C.CChr c            -> Int (CM.int_width, r)
          | C.CReal (_, fk, _)  -> Int (CM.bytesSizeOfFloat fk, r)
          | C.CStr s            -> Ref (S.fresh_abstract (CM.srcinfo_of_constant c None) , r)
          | _                   -> halt <| E.bug "Unimplemented ctype_of_const: %a@!@!" C.d_const c

    let eq pct1 pct2 =
      match (pct1, pct2) with
        | Ref (l1, i1), Ref (l2, i2) -> S.eq l1 l2 && i1 = i2
        | _                          -> pct1 = pct2

    let index_overlaps_type i i2 pct =
      Misc.foldn (fun b n -> b || N.overlaps i (N.offset n i2)) (width pct) false

    let extrema_in i1 pct1 i2 pct2 =
      index_overlaps_type i1 i2 pct2 || index_overlaps_type (N.offset (width pct1 - 1) i1) i2 pct2

    let collide i1 pct1 i2 pct2 =
      extrema_in i1 pct1 i2 pct2 || extrema_in i2 pct2 i1 pct1

    let is_void = function
      | Int (0, _) | Any     -> true
      | _                    -> false
  end

  (******************************************************************************)
  (*********************************** Stores ***********************************)
  (******************************************************************************)

  and Field: SIG.FIELD = struct
    type t = T.field

    let get_finality {pffinal = fnl} =
      fnl

    let set_finality fld fnl =
      {fld with pffinal = fnl}

    let get_fieldinfo {pfinfo = fi} =
      fi

    let set_fieldinfo fld fi =
      {fld with pfinfo = fi}

    let type_of {pftype = ty} =
      ty

    let create fnl fi t =
      (* pmr: Change location from locUnknown *)
      {pftype = t; pffinal = fnl; pfloc = C.locUnknown; pfinfo = fi}

    let is_final fld =
      get_finality fld = Final

    let sloc_of fld =
      fld |> type_of |> CType.sloc

    let map_type f fld =
      {fld with pftype = fld |> type_of |> f}

    let map2_type f fld1 fld2 =
      {fld1 with pftype = f <| (type_of <| fld1)
                            <| (type_of <| fld1)}

    let subs sub =
      map_type (CType.subs sub)

    let d_finality () = function
      | Final -> P.text "final "
      | _     -> P.nil

    (* ORIG *)
    let d_field () fld =
      P.dprintf "%a%a%a" 
        d_finality (get_finality fld) 
        CType.d_ctype (type_of fld)
        d_fieldinfo (get_fieldinfo fld)

  end

  and LDesc: SIG.LDESC = struct
    type t = T.ldesc

    exception TypeDoesntFit of Index.t * CType.t * t

    let empty =
      { plfields = [] ; plinfo = dummy_ldinfo }

    let any =
      { plfields = [] ; plinfo = any_ldinfo   }

    let eq {plfields = cs1} {plfields = cs2} =
      Misc.same_length cs1 cs2 &&
        List.for_all2
          (fun (i1, f1) (i2, f2) -> i1 = i2 && Field.type_of f1 = Field.type_of f2)
          cs1 cs2

    let is_any {plinfo = inf} =
      inf.any

    let is_empty ld =
      ld.plfields = [] && not(is_any ld)

    let is_read_only {plfields = flds} =
      List.for_all (fun (_, {pffinal = fnl}) -> fnl = Final) flds

    let fits i fld {plfields = cs} =
      let t = Field.type_of fld in
      let w = CType.width t in
        Misc.get_option w (N.period i) >= w &&
          not (List.exists (fun (i2, fld2) -> CType.collide i t i2 (Field.type_of fld2)) cs)

    let rec insert_field ((i, _) as fld) = function
      | []                      -> [fld]
      | (i2, _) as fld2 :: flds -> if i < i2 then fld :: fld2 :: flds else fld2 :: insert_field fld flds

    let add i fld ld =
      if fits i fld ld then
        {ld with plfields = insert_field (i, fld) ld.plfields}
      else raise (TypeDoesntFit (i, Field.type_of fld, ld))

    let remove i ld =
      {ld with plfields = List.filter (fun (i2, _) -> not (i = i2)) ld.plfields}

    let create si flds =
      List.fold_right (Misc.uncurry add) flds {empty with plinfo = si}

    let mem i {plfields = flds} =
      List.exists (fun (i2, _) -> N.is_subindex i i2) flds

    let find i ld =
      if is_any ld then
        [i, {pftype = Any;          pffinal = Nonfinal;
             pfloc  = C.locUnknown; pfinfo  = any_fldinfo}]
      else
        List.filter (fun (i2, _) -> N.overlaps i i2) ld.plfields

    let rec foldn_aux f n b = function
      | []               -> b
      | (i, fld) :: flds -> foldn_aux f (n + 1) (f n b i fld) flds

    let foldn f b ld =
      foldn_aux f 0 b ld.plfields

    let fold f b flds =
      foldn (fun _ b i fld -> f b i fld) b flds

    let mapn f ld =
      {ld with plfields = Misc.mapi (fun n (i, fld) -> (i, f n i fld)) ld.plfields}

    let map2n f ld1 ld2 =
      let ld1p, ld2p = ld1.plfields, ld2.plfields in
      {ld with plfields =
        Misc.map2i (fun n (i, fld1, fld2) -> (i, f n i fld1 fld2)) ld1p ld2p}

    let map f flds =
      mapn (fun _ _ fld -> f fld) flds

    let map2 f flds1 flds2 =
      map2n (fun _ _ fld1 fld2 -> f fld1 fld2) flds1 flds2

    let subs sub ld =
      map (Field.subs sub) ld

    let iter f ld =
      fold (fun _ i fld -> f i fld) () ld

    let referenced_slocs ld =
      fold begin fun rls _ fld -> match Field.sloc_of fld with 
        | None   -> rls
        | Some l -> l :: rls
      end [] ld

    let bindings {plfields = flds} =
      flds

    let indices ld =
      ld |> bindings |>: fst

    let get_ldinfo {plinfo = si} =
      si

    let set_ldinfo ld si =
      {ld with plinfo = si}

    let set_stype ld st =
      {ld with plinfo = {ld.plinfo with stype = st}}

    let d_ldesc () {plfields = flds} =
      P.dprintf "@[%t@]"
        begin fun () ->
          P.seq
            (P.dprintf ",@!")
            (fun (i, fld) -> P.dprintf "%a: %a" Index.d_index i Field.d_field fld)
            flds
        end

    let decorate l ty ld =
      let fldm = unfold_ciltyp ty in
      ld |> Misc.flip set_stype (Some ty)
         |> mapn begin fun i _ pf -> 
              try Field.set_fieldinfo pf (fldm ld i) with Not_found -> 
                let _ = E.warn "WARNING: decorate : %a bad idx %d, ld=%a, t=%a \n" 
                        Sloc.d_sloc l i d_ldesc ld Cil.d_type ty
                in pf
            end

    let d_ref () = function
      | Ref (l,_) -> P.dprintf "REF(%a)" Sloc.d_sloc l
      | _         -> P.nil

    let d_vbind () (b, (ct, t)) =
      P.dprintf "%a %a %a %a" 
        Cil.d_type (CM.typStripAttrs t)
        d_ref ct
        d_binder b 
        T.R.d_refinement (CType.refinement ct) 

    let d_ann_field () (i, fld) = 
      match Field.get_fieldinfo fld with
      | { fname = Some fldname; ftype = Some t } ->
          d_vbind () (S fldname, (Field.type_of fld, t))
      | { ftype = Some t } ->
          d_vbind () (I i, (Field.type_of fld, t))
      | _ -> P.dprintf "%a ??? %a" d_binder (I i) d_ref (Field.type_of fld)

    let d_ldinfo () = function
      | {stype = Some t} -> Cil.d_type () (CM.typStripAttrs t)
      | _                -> P.nil

    let d_sloc_ldesc () (l, ld) =
      P.dprintf "%a %a |-> %a" 
        d_ldinfo ld.plinfo
        Sloc.d_sloc l 
        (CM.d_many_braces true d_ann_field) (bindings ld)
    
    (* API *)
    let d_sloc_ldesc () ((l : Sloc.t), (ld: t)) =
      let ld = match ld.plinfo.stype, Sloc.to_ciltyp l with 
               | None, Some ty -> decorate l ty ld 
               | _             -> ld 
      in d_sloc_ldesc () (l, ld)
        
  end

  and Store: SIG.STORE = struct
    type t = T.store

    let empty = (SLM.empty, SLM.empty, [])

    let map2_data f =
      f |> Field.map2_type |> LDesc.map2 |> SLM.map2

    let map_data f =
      f |> Field.map_type |> LDesc.map |> SLM.map

    let map_function f =
      SLM.map (CFun.map f)

    let map_ldesc f (ds, fs, _) =
      (SLM.mapi f ds, SLM.map (CFun.map_ldesc f) fs, [])

    let restrict_slm_abstract m =
      SLM.filter (fun l -> const <| S.is_abstract l) m

    module Data = struct
      let add (ds, fs, _) l ld =
        let _ = assert ((l = Sloc.sloc_of_any) || (not (SLM.mem l fs))) in
        if (l = Sloc.sloc_of_any) then
          (ds, fs, [])
        else
          (SLM.add l ld ds, fs, [])

      let bindings (ds, _, _) =
        SLM.to_list ds

      let domain (ds, _, _) =
        SLM.domain ds

      let mem (ds, _, _) l =
        if (l = Sloc.sloc_of_any) then
          true
        else
          SLM.mem l ds

      let find (ds, _, _) l =
        if (l = Sloc.sloc_of_any) then
          LDesc.any 
        else
          SLM.find l ds

      let find_or_empty sto l =
        try find sto l with Not_found -> LDesc.empty

      let ensure_sloc sto l =
        l |> find_or_empty sto |> add sto l

      let map f (ds, fs, _) =
        (map_data f ds, fs, [])

      let map2 f (ds, fs, _) (ds', fs', _) =
        (map2_data f ds ds', fs, [])

      let fold_fields f b (ds, fs, _) =
        SLM.fold (fun l ld b -> LDesc.fold (fun b i pct -> f b l i pct) b ld) ds b

      let fold_locs f b (ds, fs, _) =
        SLM.fold f ds b
    end

    module Function = struct
      let add (ds, fs, _) l cf =
        let _ = assert (not (SLM.mem l ds)) in
        let _ = assert (Sloc.is_abstract l) in
          (ds, SLM.add l cf fs, [])

      let bindings (_, fs, _) =
        SLM.to_list fs

      let domain (_, fs, _) =
        SLM.domain fs

      let mem (_, fs, _) l =
        SLM.mem l fs

      let find (_, fs, _) l =
        SLM.find l fs

      let fold_locs f b (_, fs, _) =
        SLM.fold f fs b
    end

    let map_variances f_co f_contra (ds, fs, _) =
      (map_data f_co ds, SLM.map (CFun.map_variances f_co f_contra) fs, [])

    let map f (ds, fs, _) =
      (map_data f ds, map_function f fs, [])

    let bindings sto =
      (Data.bindings sto, Function.bindings sto)

    let abstract (ds, fs, _) =
      (restrict_slm_abstract ds, restrict_slm_abstract fs, [])

    let join_effects sto effs =
      ((sto |> Data.bindings |>: fun (l, ld) -> (l, (ld, EffectSet.find effs (S.canonical l)))),
       (sto |> Function.bindings |>: fun (l, fn) -> (l, (fn, EffectSet.find effs l))))

    let domain sto =
      Data.domain sto ++ Function.domain sto

    let mem (ds, fs, _) s =
      if (s = Sloc.sloc_of_any) then
        true
      else
        SLM.mem s ds || SLM.mem s fs

    let subs_slm_dom subs m =
      SLM.fold (fun l d m -> SLM.add (S.Subst.apply subs l) d m) m SLM.empty

    let subs_addrs subs (ds, fs, _) =
      (subs_slm_dom subs ds, subs_slm_dom subs fs, [])

    let subs subs (ds, fs, _) =
      (SLM.map (LDesc.subs subs) ds, fs |> SLM.map (Misc.flip CFun.subs subs),
      []) |> subs_addrs subs

    let remove (ds, fs, _) l =
      if (l = Sloc.sloc_of_any) then
        (ds, fs, [])
      else
        (SLM.remove l ds, SLM.remove l fs, [])

    let upd (ds1, fs1, _) (ds2, fs2, _) =
      (SLM.fold SLM.add ds2 ds1, SLM.fold SLM.add fs2 fs1, [])

    let partition_map f m =
      SLM.fold begin fun l d (m1, m2, _) ->
        if f l then (SLM.add l d m1, m2, []) else (m1, SLM.add l d m2, [])
      end m (SLM.empty, SLM.empty, [])

    let partition f (ds, fs, _) =
      let ds1, ds2, _ = partition_map f ds in
      let fs1, fs2, _ = partition_map f fs in
        ((ds1, fs1, []), (ds2, fs2, []))

    let ctype_closed t sto = match t with
      | Ref (l, _) -> mem sto l
      | ARef       -> false
      | Int _ | Any | FRef _ -> true

    let rec reachable_aux sto visited l =
      if SS.mem l visited then
        visited
      else if Function.mem sto l then
        SS.add l visited
      else begin
           l
        |> Data.find sto
        |> LDesc.referenced_slocs
        |> List.fold_left (reachable_aux sto) (SS.add l visited)
      end

    let reachable sto l =
      l |> reachable_aux sto SS.empty |> SS.elements

    let restrict sto ls =
         sto
      |> partition (ls |> Misc.flap (reachable sto) |> Misc.sort_and_compact |> Misc.flip List.mem)
      |> fst

    let rec closed globstore ((_, fs, _) as sto) =
      Data.fold_fields
        (fun c _ _ fld -> c && ctype_closed (Field.type_of fld) (upd globstore sto)) true sto &&
        SLM.fold (fun _ cf c -> c && CFun.well_formed globstore cf) fs true

    let slm_acc_list f m =
      SLM.fold (fun _ d acc -> f d ++ acc) m []

    let indices (ds, fs, _) =
      slm_acc_list LDesc.indices ds ++ slm_acc_list CFun.indices fs

    let data (ds, _, _) =
      (ds, SLM.empty, [])

    let d_store_addrs () st =
      P.seq (P.text ",") (Sloc.d_sloc ()) (domain st)

    let d_store () (ds, fs, _) =
      if fs = SLM.empty then
        P.dprintf "[@[%a@]]" (d_storelike LDesc.d_ldesc) ds
      else if ds = SLM.empty then
        P.dprintf "[@[%a@]]" (d_storelike CFun.d_cfun) fs
      else
        P.dprintf "[@[%a;@!%a@]]" (d_storelike LDesc.d_ldesc) ds (d_storelike CFun.d_cfun) fs

    module Unify = struct
      exception UnifyFailure of S.Subst.t * t

      let fail sub sto _ =
        raise (UnifyFailure (sub, sto))

      let rec unify_ctype_locs sto sub ct1 ct2 = match CType.subs sub ct1, CType.subs sub ct2 with
        | Int (n1, _), Int (n2, _) when n1 = n2 -> (sto, sub)
        | Ref (s1, _), Ref (s2, _)              -> unify_locations sto sub s1 s2
        | FRef (f1,_), FRef(f2,_)  when CFun.same_shape f1 f2 -> (sto, sub)
        | ARef, ARef                            -> (sto, sub)
        | Ref (s, _), ARef                      -> anyfy_location sto sub s
        | ARef, Ref (s, _)                      -> anyfy_location sto sub s
        | Any, Any                              -> (sto, sub)
        | Any, Int _                            -> (sto, sub)
        | Int _, Any                            -> (sto, sub)
        | ct1, ct2                              -> 
          fail sub sto <| C.error "Cannot unify locations of %a and %a@!" CType.d_ctype ct1 CType.d_ctype ct2

      and unify_data_locations sto sub s1 s2 =
        let ld1, ld2 = Misc.map_pair (Data.find_or_empty sto <+> LDesc.subs sub) (s1, s2) in
        let sto      = remove sto s1 in
        let sto      = ld2 |> Data.add sto s2 |> subs sub in
          LDesc.fold (fun (sto, sub) i f -> add_field sto sub s2 i f) (sto, sub) ld1

      and unify_fun_locations sto sub s1 s2 =
        if Function.mem sto s1 then
          let cf1 = CFun.subs (Function.find sto s1) sub in
          let sto = s1 |> remove sto |> subs sub in
          if Function.mem sto s2 then
            let cf2 = CFun.subs (Function.find sto s2) sub in
            if CFun.same_shape cf1 cf2 then
              (sto, sub)
            else
              fail sub sto <|
                  C.error "Trying to unify locations %a, %a with different function types:@!@!%a: %a@!@!%a: %a@!"
                    S.d_sloc_info s1 S.d_sloc_info s2 S.d_sloc_info s1 CFun.d_cfun cf1 S.d_sloc_info s2 CFun.d_cfun cf2
          else (Function.add sto s2 cf1, sub)
        else (subs sub sto, sub)

      and assert_unifying_same_location_type sto sub s1 s2 =
        if (Function.mem sto s1 && Data.mem sto s2) ||
          (Data.mem sto s1 && Function.mem sto s2) then
            fail sub sto <| C.error "Trying to unify data and function locations (%a, %a) in store@!%a@!"
                S.d_sloc_info s1 S.d_sloc_info s2 d_store sto
        else ()

      and anyfy_location sto sub s =
        if s = S.sloc_of_any then
          (sto, sub)
        else
          let sub = S.Subst.extend s S.sloc_of_any sub in
          if Function.mem sto s || Data.mem sto s then
            (subs sub (remove sto s), sub)
          else
            (subs sub sto, sub)

      and unify_locations sto sub s1 s2 =
        if not (S.eq s1 s2) then
          (* let _ = print_now (Printf.sprintf "unify_locations TRUE s1 = %s s2 = %s \n" (CilMisc.pretty_to_string S.d_sloc s1) (CilMisc.pretty_to_string S.d_sloc s2)) in
          *) let _   = assert_unifying_same_location_type sto sub s1 s2 in
          let sub = S.Subst.extend s1 s2 sub in
            if Function.mem sto s1 || Function.mem sto s2 then
              unify_fun_locations sto sub s1 s2
            else if Data.mem sto s1 || Data.mem sto s2 then
              unify_data_locations sto sub s1 s2
            else (subs sub sto, sub)
        else 
          (* let _ = print_now (Printf.sprintf "unify_locations FALSE s1 = %s s2 = %s \n" (CilMisc.pretty_to_string S.d_sloc s1) (CilMisc.pretty_to_string S.d_sloc s2)) in
          *) (sto, sub)

      and unify_fields sto sub fld1 fld2 = match Misc.map_pair (Field.type_of <+> CType.subs sub) (fld1, fld2) with
        | ct1, ct2                   when ct1 = ct2 -> (sto, sub)
        | Ref (s1, i1), Ref (s2, i2) when i1 = i2   -> unify_locations sto sub s1 s2
        | Ref (s, _), ARef | ARef, Ref(s, _)        -> anyfy_location sto sub s
        | Any , Int _ | Int _, Any                  -> (sto, sub)
        | ct1, ct2                                  ->
          fail sub sto <| C.error "Cannot unify %a and %a@!" CType.d_ctype ct1 CType.d_ctype ct2

      and unify_overlap sto sub s i =
        let s  = S.Subst.apply sub s in
        let ld = Data.find_or_empty sto s in
          match LDesc.find i ld with
            | []                         -> (sto, sub)
            | ((_, fstfld) :: _) as olap ->
              let i = olap |>: fst |> List.fold_left Index.lub i in
                   ld
                |> List.fold_right (fst <+> LDesc.remove) olap
                |> LDesc.add i fstfld
                |> Data.add sto s
                |> fun sto ->
                     List.fold_left
                       (fun (sto, sub) (_, olfld) -> unify_fields sto sub fstfld olfld)
                       (sto, sub)
                       olap

      and add_field sto sub s i fld =
        try
          begin match i with
            | N.IBot                 -> (sto, sub)
            | N.ICClass _ | N.IInt _ ->
              let sto, sub = unify_overlap sto sub s i in
              let s        = S.Subst.apply sub s in
              let fld      = Field.subs sub fld in
              let ld       = Data.find_or_empty sto s in
                begin match LDesc.find i ld with
                  | []          -> (ld |> LDesc.add i fld |> Data.add sto s, sub)
                  | [(_, fld2)] -> unify_fields sto sub fld fld2
                  | _           -> assert false
                end
          end
        with e ->
          C.error "Can't fit @!%a: %a@!  in location@!%a |-> %a@!"
            Index.d_index i 
            Field.d_field fld 
            S.d_sloc_info s 
            LDesc.d_ldesc (Data.find_or_empty sto s) 
          |> ignore;
          raise e

      let add_fun sto sub l cf =
        let l = S.Subst.apply sub l in
          if not (Data.mem sto l) then
            if Function.mem sto l then
              let _ = assert (CFun.same_shape cf (Function.find sto l)) in
                (sto, sub)
            else (Function.add sto l cf, sub)
          else fail sub sto <| C.error "Attempting to store function in location %a, which contains: %a@!"
                 S.d_sloc_info l LDesc.d_ldesc (Data.find sto l)
    end
  end

  (******************************************************************************)
  (******************************* Function Types *******************************)
  (******************************************************************************)
  and CFun: SIG.CFUN = struct
    type t = T.cfun

    (* API *)
    let make args globs sin reto sout effs =
      { args     = args;
        ret      = reto;
        globlocs = globs;
        sto_in   = sin;
        sto_out  = sout;
        effects  = effs;
      }

    let map_variances f_co f_contra ft =
      { args     = List.map (Misc.app_snd f_contra) ft.args;
        ret      = f_co ft.ret;
        globlocs = ft.globlocs;
        sto_in   = Store.map_variances f_contra f_co ft.sto_in;
        sto_out  = Store.map_variances f_co f_contra ft.sto_out;
        effects  = ft.effects;
      }

    let map f ft =
      map_variances f f ft

    let map_ldesc f ft =
      { ft with 
        sto_in = Store.map_ldesc f ft.sto_in
      ; sto_out = Store.map_ldesc f ft.sto_out }

    let apply_effects f ft =
      {ft with effects = EffectSet.apply f ft.effects}

    let quantified_locs {sto_out = sto} =
      Store.domain sto

    let d_slocs () slocs = P.dprintf "[%t]" (fun _ -> P.seq (P.text ";") (S.d_sloc ()) slocs)
    let d_arg () (x, ct) = P.dprintf "%s : %a" x CType.d_ctype ct
    let d_args () args   = P.seq (P.dprintf ",@!") (d_arg ()) args

    let d_argret () ft =
      P.dprintf "arg       (@[%a@])\nret       %a\n"
        d_args ft.args
        CType.d_ctype ft.ret

    let d_spec_globlocs () ft =
      P.dprintf "global    %a\n" d_slocs ft.globlocs

    let d_globlocs () ft =
      d_spec_globlocs () ft

    let d_stores () ft =
      P.dprintf "store_in  %a\nstore_out %a\n"
        Store.d_store ft.sto_in
        Store.d_store ft.sto_out

    let d_effectset () ft =
      P.dprintf "effects   %a" EffectSet.d_effectset ft.effects

    let d_cfun () ft  =
      P.dprintf "@[%a%a%a%a@]" d_argret ft d_globlocs ft d_stores ft d_effectset ft

    let capturing_subs cf sub =
      let apply_sub = CType.subs sub in
        make (List.map (Misc.app_snd apply_sub) cf.args)
             (List.map (S.Subst.apply sub) cf.globlocs)
             (Store.subs sub cf.sto_in)
             (apply_sub cf.ret)
             (Store.subs sub cf.sto_out)
             (EffectSet.subs sub cf.effects)

    let subs cf sub =
      cf |> quantified_locs |> S.Subst.avoid sub |> capturing_subs cf

    let rec order_locs_aux sto ord = function
      | []      -> ord
      | l :: ls ->
          if not (List.mem l ord) then
            let ls = if Store.Data.mem sto l then ls @ (l |> Store.Data.find sto |> LDesc.referenced_slocs) else ls in
              order_locs_aux sto (l :: ord) ls
          else order_locs_aux sto ord ls

    let ordered_locs ({args = args; ret = ret; sto_out = sto} as cf) =
      let ord = (CType.sloc ret :: List.map (snd <+> CType.sloc) args)
             |> Misc.maybe_list
             |> order_locs_aux sto []
             |> Misc.mapi (fun i x -> (x, i)) in
      cf |> quantified_locs |> Misc.fsort (Misc.flip List.assoc ord)

    let replace_arg_names anames cf =
      {cf with args = List.map2 (fun an (_, t) -> (an, t)) anames cf.args}

    let normalize_names cf1 cf2 f fe =
      let ls1, ls2     = Misc.map_pair ordered_locs (cf1, cf2) in
      let fresh_locs   = List.map (Sloc.copy_abstract []) ls1 in
      let lsub1, lsub2 = Misc.map_pair (Misc.flip List.combine fresh_locs) (ls1, ls2) in
      let fresh_args   = List.map (fun _ -> CM.fresh_arg_name ()) cf1.args in
      let asub1, asub2 = Misc.map_pair (List.map fst <+> Misc.flip List.combine fresh_args) (cf1.args, cf2.args) in
      let cf1, cf2     = Misc.map_pair (replace_arg_names fresh_args) (cf1, cf2) in
        (capturing_subs cf1 lsub1 |> map (f cf1.sto_out lsub1 asub1) |> apply_effects (fe cf1.sto_out lsub1 asub1),
         capturing_subs cf2 lsub2 |> map (f cf2.sto_out lsub2 asub2) |> apply_effects (fe cf2.sto_out lsub2 asub2))

    let rec same_shape cf1 cf2 =
      Misc.same_length (quantified_locs cf1) (quantified_locs cf2) && Misc.same_length cf1.args cf2.args &&
        let cf1, cf2 = normalize_names cf1 cf2 (fun _ _ _ ct -> ct) (fun _ _ _ ct -> ct) in
          List.for_all2 (fun (_, a) (_, b) -> a = b) cf1.args cf2.args
       && cf1.ret = cf2.ret
       && Store.Data.fold_locs begin fun l ld b ->
            b && Store.Data.mem cf2.sto_out l && LDesc.eq ld (Store.Data.find cf2.sto_out l)
          end true cf1.sto_out
       && Store.Function.fold_locs begin fun l cf b ->
              b && Store.Function.mem cf2.sto_out l && same_shape cf (Store.Function.find cf2.sto_out l)
          end true cf1.sto_out

    let well_formed globstore cf =
      (* pmr: also need to check sto_out includes sto_in, possibly subtyping *)
      let whole_instore  = Store.upd cf.sto_in globstore in
      let whole_outstore = Store.upd cf.sto_out globstore in
             Store.closed globstore cf.sto_in
          && Store.closed globstore cf.sto_out
          && List.for_all (Store.mem globstore) cf.globlocs
          && not (cf.sto_out |> Store.domain |> List.exists (Misc.flip List.mem cf.globlocs))
          && List.for_all (fun (_, ct) -> Store.ctype_closed ct whole_instore) cf.args
          && Store.ctype_closed cf.ret whole_outstore

    let indices cf =
      Store.indices cf.sto_out

    let instantiate srcinf cf =
      let qslocs    = quantified_locs cf in
      let instslocs = List.map (S.copy_abstract [srcinf]) qslocs in
      let sub       = List.combine qslocs instslocs in
        (subs cf sub, sub)
  end

  (******************************************************************************)
  (************************************ Specs ***********************************)
  (******************************************************************************)
  and Spec: SIG.SPEC = struct
    type t = T.spec

    let empty = (SM.empty, SM.empty, Store.empty, SLM.empty)

    let map f (funspec, varspec, storespec, storetypes) =
      (SM.map (f |> CFun.map |> Misc.app_fst) funspec,
       SM.map (f |> Misc.app_fst) varspec,
       Store.map f storespec,
       storetypes)

    let add_fun b fn sp (funspec, varspec, storespec, storetypes) =
      (Misc.sm_protected_add b fn sp funspec, varspec, storespec, storetypes)

    let add_var b vn sp (funspec, varspec, storespec, storetypes) =
      (funspec, Misc.sm_protected_add b vn sp varspec, storespec, storetypes)

    let add_data_loc l (ld, st) (funspec, varspec, storespec, storetypes) =
      (funspec, varspec, Store.Data.add storespec l ld, SLM.add l st storetypes)

    let add_fun_loc l (cf, st) (funspec, varspec, storespec, storetypes) =
      (funspec, varspec, Store.Function.add storespec l cf, SLM.add l st storetypes)
      
    let funspec (fs, _, _, _)        = fs
    let varspec (_, vs, _, _)        = vs
    let store (_, _, sto, _)         = sto
    let locspectypes (_, _, _, lsts) = lsts
    let make w x y z                 = (w, x, y, z)

    let add (funspec, varspec, storespec, storetypes) spec =  
          spec
       |> SM.fold (fun fn sp spec -> add_fun false fn sp spec) funspec
       |> SM.fold (fun vn sp spec -> add_var false vn sp spec) varspec
       |> (fun (w, x, y, z) -> (w, x, Store.upd y storespec, z))

    let d_spec () sp =
      let lspecs = locspectypes sp in
      [ (Store.Data.fold_locs (fun l ld acc ->
          P.concat acc (P.dprintf "loc %a %a %a\n\n"
                          Sloc.d_sloc l d_specTypeRel (SLM.find l lspecs) LDesc.d_ldesc ld)
         ) P.nil (store sp))
      ; (Store.Function.fold_locs (fun l cf acc ->
          P.concat acc  (P.dprintf "loc %a %a@!  @[%a@]@!@!"
                           Sloc.d_sloc l d_specTypeRel (SLM.find l lspecs) CFun.d_cfun cf)
         ) P.nil (store sp))
      ; (P.seq (P.text "\n\n") (fun (vn, (ct, _)) -> 
          P.dprintf "%s :: @[%a@]" vn CType.d_ctype ct
         ) (varspec sp |> SM.to_list))
      ; (P.seq (P.text "\n\n") (fun (fn, (cf, _)) -> 
          P.dprintf "%s ::@!  @[%a@]\n\n" fn CFun.d_cfun cf
         ) (funspec sp |> SM.to_list)) ]
      |> List.fold_left P.concat P.nil
  end

  (******************************************************************************)
  (******************************* Expression Maps ******************************)
  (******************************************************************************)
  module ExpKey = struct
    type t      = Cil.exp
    let compare = compare
    let print   = CilMisc.pretty_to_format Cil.d_exp
  end

  module ExpMap = Misc.EMap (ExpKey)

  module ExpMapPrinter = P.MakeMapPrinter(ExpMap)

  type ctemap = CType.t ExpMap.t

  let d_ctemap () (em: ctemap): P.doc =
    ExpMapPrinter.d_map "\n" Cil.d_exp CType.d_ctype () em
end

module I    = Make (IndexTypes)

type ctype  = I.CType.t
type cfun   = I.CFun.t
type store  = I.Store.t
type cspec  = I.Spec.t
type ctemap = I.ctemap

let null_fun      = {args = [];
                     ret  = Int (0, N.top);
                     globlocs = [];
                     sto_in = Sloc.SlocMap.empty,Sloc.SlocMap.empty,[];
                     sto_out = Sloc.SlocMap.empty,Sloc.SlocMap.empty,[];
                     effects = SLM.empty}
  
let void_ctype   = Int  (0, N.top)
let ptr_ctype    = Ref  (S.none, N.top)
let scalar_ctype = Int  (0, N.top)
let fptr_ctype   = FRef (null_fun, N.top)

let rec vtype_to_ctype v = if Cil.isArithmeticType v
  then scalar_ctype
  else match v with
    | Cil.TNamed ({C.ttype = v'},_) -> vtype_to_ctype v'
    | Cil.TPtr (Cil.TFun _, _) -> fptr_ctype
    | _ -> ptr_ctype


let d_ctype        = I.CType.d_ctype
let index_of_ctype = I.CType.refinement

(*******************************************************************)
(********************* Refined Types and Stores ********************)
(*******************************************************************)

module RefCTypes   = Make (ReftTypes)
module RCt         = RefCTypes

type refctype      = RCt.CType.t
type refcfun       = RCt.CFun.t
type reffield      = RCt.Field.t
type refldesc      = RCt.LDesc.t
type refstore      = RCt.Store.t
type refspec       = RCt.Spec.t

let d_refstore     = RCt.Store.d_store
let d_refcfun      = RCt.CFun.d_cfun

let refstore_partition = RCt.Store.partition

let refstore_set sto l rd =
  try RCt.Store.Data.add sto l rd with Not_found -> 
    assertf "refstore_set"

let refstore_get sto l =
  try RCt.Store.Data.find sto l with Not_found ->
    (Errormsg.error "Cannot find location %a in store\n" Sloc.d_sloc l;   
     asserti false "refstore_get"; assert false)

let refldesc_subs rd f =
  RCt.LDesc.mapn (fun i pl fld -> RCt.Field.map_type (f i pl) fld) rd

(*******************************************************************)
(******************** Operations on Refined Stores *****************)
(*******************************************************************)

let refdesc_find i rd = 
  match RCt.LDesc.find i rd with
  | [(i', rfld)] -> (rfld, Index.is_periodic i')
  | _            -> assertf "refdesc_find"

let addr_of_refctype loc = function
  | Ref (cl, (i,_)) when not (Sloc.is_abstract cl) ->
      (cl, i)
  | ARef -> (Sloc.sloc_of_any, Index.ind_of_any)
  | cr   ->
      let s = cr  |> d_refctype () |> P.sprint ~width:80 in
      let l = loc |> Cil.d_loc () |> P.sprint ~width:80 in
      let _ = asserti false "addr_of_refctype: bad arg %s at %s \n" s l in
      assert false

let ac_refstore_read loc sto cr = 
  let (l, ix) = addr_of_refctype loc cr in 
     l
  |> RCt.Store.Data.find sto 
  |> refdesc_find ix

(* API *)
let refstore_read loc sto cr = 
  ac_refstore_read loc sto cr |> fst

(* API *)
let is_soft_ptr loc sto cr = 
  ac_refstore_read loc sto cr |> snd

(* API *)
let refstore_write loc sto rct rct' = 
  let (cl, ix) = addr_of_refctype loc rct in
  let _  = assert (not (Sloc.is_abstract cl)) in
  let ld = RCt.Store.Data.find sto cl in
  let ld = RCt.LDesc.remove ix ld in
  let ld = RCt.LDesc.add ix (RCt.Field.create Nonfinal dummy_fieldinfo rct') ld in
  RCt.Store.Data.add sto cl ld

(* API *)
let ctype_of_refctype = function
  | Int (x, (y, _))  -> Int (x, y) 
  | Ref (x, (y, _))  -> Ref (x, y)
  | ARef             -> ARef
  | Any              -> Any  
  | f -> RCt.CType.map fst f

(* API *)
let cfun_of_refcfun   = I.CFun.map ctype_of_refctype 
let cspec_of_refspec  = I.Spec.map (RCt.CType.map (fun (i,_) -> i))
let store_of_refstore = I.Store.map ctype_of_refctype
let args_of_refcfun   = fun ft -> ft.args
let ret_of_refcfun    = fun ft -> ft.ret
let stores_of_refcfun = fun ft -> (ft.sto_in, ft.sto_out)

let reft_of_refctype = function
  | Int (_,(_,r)) 
  | Ref (_,(_,r))
  | FRef (_,(_,r)) -> r
  | Any | ARef -> reft_of_top

(**********************************************************************)


