type block_annotation = Ctypes.PlocSet.t Sloc.SlocMap.t list

val infer_final_fields :
  Ctypes.I.Spec.t ->
  (Ctypes.cfun * Ssa_transform.ssaCfgInfo) Misc.StringMap.t ->
  Shape.t Misc.StringMap.t ->
  Shape.t Misc.StringMap.t

val d_final_fields :
  unit ->
  block_annotation array ->
  Pretty.doc
