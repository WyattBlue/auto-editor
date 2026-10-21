## What an editor export can't carry from a timeline. The writers skip what
## their format has no place for; this names it so the loss isn't silent.

import std/[sequtils, strutils]
import ../[action, log, timeline]

type
  LayerRule = enum
    lrAll        # every layer is written
    lrBase       # only the base layer
    lrSameSource # the base, plus layers that only use the base's files: the
                 # editor reads those streams from the files it already has
    lrFirst      # the first layer, when it only uses the base's files

  Support = object
    actions: set[ActionKind]
    v, a: LayerRule

const mltActions = {actSpeed, actVolume, actDeesser, actInvert, actHflip,
  actVflip, actErosion, actBlur, actBrightness, actLuv, actLens, actDrawbox,
  actPixelate, actAberration}

func support(kind: ExportKind): Support {.raises: [].} =
  case kind
  of exPremiere:
    Support(actions: {actSpeed, actOpacity, actVolume}, v: lrAll, a: lrAll)
  of exResolveFcp7:
    Support(actions: {actSpeed, actOpacity, actVolume}, v: lrBase, a: lrAll)
  of exFinalCutPro: Support(actions: {actSpeed}, v: lrBase, a: lrSameSource)
  of exResolve: Support(actions: {actSpeed}, v: lrBase, a: lrAll)
  of exShotcut: Support(actions: mltActions, v: lrBase, a: lrFirst)
  of exKdenlive: Support(actions: mltActions, v: lrSameSource, a: lrSameSource)
  of exPremiereOtio:
    Support(actions: {actSpeed, actOpacity, actPos, actRotate, actSpin,
      actInvert, actHflip, actVflip}, v: lrAll, a: lrAll)
  else: Support(v: lrAll, a: lrAll)

func isEditorExport*(kind: ExportKind): bool {.raises: [].} =
  kind in {exPremiere, exResolveFcp7, exFinalCutPro, exResolve, exShotcut,
    exKdenlive, exPremiereOtio}

func appliesTo(kind: ActionKind, video: bool): bool {.raises: [].} =
  # Every clip of a section shares its action group, so a video clip also
  # holds the section's audio actions. ActionKind is laid out by media:
  # speed for both, then audio, then video.
  if kind == actSpeed: true
  elif video: kind >= actInvert
  else: kind < actInvert

func plural(n: int, noun: string): string {.raises: [].} =
  if n == 1: "1 " & noun else: $n & " " & noun & "s"

proc exportDrops*(tl: v3, kind: ExportKind): seq[string] {.raises: [].} =
  ## What exporting `tl` as `kind` leaves out: action names, then counts of
  ## video, audio, generated and subtitle tracks. Empty when nothing is lost.
  if not kind.isEditorExport:
    return
  let sup = support(kind)
  let videoBase = tl.v.len > 0 and tl.v[0].len > 0

  var baseSrcs: seq[ptr string]
  for clip in (if videoBase: tl.v[0] elif tl.a.len > 0: tl.a[0] else: @[]):
    if clip.src != nil and clip.src notin baseSrcs:
      baseSrcs.add clip.src

  func onlyBaseSrcs(layer: seq[Clip]): bool =
    for clip in layer:
      if clip.src != nil and clip.src notin baseSrcs:
        return false
    true

  proc carried(layer: seq[Clip], i: int, rule: LayerRule, isBase: bool): bool =
    if isBase: return true
    case rule
    of lrAll: true
    of lrBase: false
    of lrSameSource: layer.onlyBaseSrcs
    of lrFirst: i == 0 and layer.onlyBaseSrcs

  var actions: seq[string]
  var droppedV, droppedA, generated = 0

  proc scan(layers: seq[seq[Clip]], video: bool, rule: LayerRule) =
    for i, layer in layers:
      if layer.len == 0: continue
      let isBase = (if video: i == 0 else: i == 0 and not videoBase)
      # Generator layers (add:text, add:tone) have no file for an editor to
      # reference. A video base without files is different: it's the canvas
      # an audio-only timeline gets for its overlays, not content.
      if not (video and i == 0) and layer.allIt(it.src == nil):
        inc generated
        continue
      if not carried(layer, i, rule, isBase):
        if video: inc droppedV else: inc droppedA
        continue
      for clip in layer:
        if clip.src == nil: continue
        for act in tl.effects[clip.effects]:
          if act.kind notin sup.actions and act.kind.appliesTo(video):
            let name = ($act).split({':', ','})[0]
            if name notin actions: actions.add name

  scan(tl.v, true, sup.v)
  scan(tl.a, false, sup.a)

  result = actions
  if droppedV > 0: result.add plural(droppedV, "video track")
  if droppedA > 0: result.add plural(droppedA, "audio track")
  if generated > 0: result.add plural(generated, "generated track")
  var subs = 0
  for layer in tl.s:
    if layer.len > 0: inc subs
  if subs > 0: result.add plural(subs, "subtitle track")

proc warnDrops*(tl: v3, kind: ExportKind) {.raises: [].} =
  let drops = exportDrops(tl, kind)
  if drops.len > 0:
    warning "Left out of the export: " & drops.join(", ")
