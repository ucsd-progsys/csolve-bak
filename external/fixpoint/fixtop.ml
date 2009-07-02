(*
 * Copyright © 2009 The Regents of the University of California. All rights reserved. 
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


(** read a set of constraints, solve, and dump out the solution *)

module SM = Ast.Symbol.SMap
module Co = Constants 
module C  = FixConstraint
module F  = Format
open Misc.Ops

(*****************************************************************)
(********************* Command line options **********************)
(*****************************************************************)

let usage = "Usage: fixtop <options> [source-files]\noptions are:"

let sift xs = 
  List.fold_left 
    (fun (ts, ps, cs, ws, qs, s) -> 
      function 
      | C.Srt t        -> (t::ts, ps, cs, ws, qs, s) 
      | C.Axm p        -> (ts, p::ps, cs, ws, qs, s) 
      | C.Cst c        -> (ts, ps, c::cs, ws, qs, s)
      | C.Wfc w        -> (ts, ps, cs, w::ws, qs, s)
      | C.Qul q        -> (ts, ps, cs, ws, q::qs, s)
      | C.Sol (k, kps) -> (ts, ps, cs, ws, qs, SM.add k kps s))
    ([], [], [], [], [], SM.empty) xs

let parse f = 
  let _ = Errorline.startFile f in
  open_in f 
  |> Lexing.from_channel 
  |> FixParse.defs FixLex.token
(* Andrey: TODO: need to close the file? *)
 
let main () =
  Printf.printf "© Copyright 2007 Regents of the University of California. ";
  Printf.printf "All Rights Reserved.\n";
  let fs = ref [] in
  let _  = Arg.parse Co.arg_spec (fun s -> fs := s::!fs) usage in
  let _, _, cs, ws, _, _ =  !fs |> Misc.flap parse |> sift in
    begin
      match !Co.latex_file with
	| Some f ->
	    let out = open_out f in
	      ToLatex.to_latex out cs ws;
	      close_out out
	| None -> ()
    end;
    begin
      match !Co.armc_file with
	| Some f -> failwith "-armc: not yet implemented"
	| None -> ()
    end


let _ = main ()