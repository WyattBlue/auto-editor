import std/[json, os, sets, tables]
from std/math import round, hypot, ceil, sin, cos, PI

import ../[action, ffmpeg, log, media, timeline]
import ../util/[color, fun, rational]

#[
OpenTimelineIO (.otio) export, compatible with Adobe Premiere Pro.

Premiere can import and export .otio files. Unlike the FCP7 XML format, OTIO lets
us attach the "Invert" video effect (AE.ADBE Invert) alongside Premiere's
intrinsic effects, so auto-editor's `invert` action survives the round-trip.

Clip timing follows OTIO's time-effect convention: `source_range` is in the
source media's frames, and a LinearTimeWarp `time_scalar` compresses it on the
timeline. The visible duration is `source_range.duration / time_scalar`, which
recovers auto-editor's (already sped-up) `clip.dur`.
]#

# Premiere's sentinel keyframe position, "start of time" (-100 hours).
const POS = -10800000.0


proc rationalTime(rate, value: float): JsonNode =
  %*{"OTIO_SCHEMA": "RationalTime.1", "rate": rate, "value": value}

proc center(): JsonNode = %*{"X": 0.5, "Y": 0.5}

proc jarr(items: varargs[JsonNode]): JsonNode =
  result = newJArray()
  for it in items:
    result.add it

proc startParam(name: string, id: int, value: JsonNode, rate: float): JsonNode =
  ## A parameter whose value is fixed for the whole clip (single keyframe).
  %*{
    "DisplayName": name,
    "ID": id,
    "StartValue": {"Position": rationalTime(rate, POS), "Value": value}
  }

proc keyframeParam(name: string, id: int): JsonNode =
  ## A parameter with no keyframes (used by track-level and audio effects).
  %*{"DisplayName": name, "ID": id, "Keyframes": newJArray()}

proc effectNode(matchName, effectName, name: string, intrinsic: bool,
    params: JsonNode): JsonNode =
  %*{
    "OTIO_SCHEMA": "Effect.1",
    "metadata": {
      "PremierePro_OTIO": {
        "IsIntrinsic": intrinsic,
        "MatchName": matchName,
        "Parameters": params
      }
    },
    "name": name,
    "effect_name": effectName,
    "enabled": true
  }

proc speedEffect(scalar: float): JsonNode =
  %*{
    "OTIO_SCHEMA": "LinearTimeWarp.1",
    "metadata": {},
    "name": "Speed",
    "effect_name": "Speed",
    "enabled": true,
    "time_scalar": scalar
  }

proc opacityEffect(rate: float, pct: float): JsonNode =
  effectNode("AE.ADBE Opacity", "Opacity", "", true, jarr(
    startParam("Opacity", 1, %pct, rate),
    startParam("Blend Mode", 2, %18, rate),
    startParam("Blend Mode", 3, %0, rate),
  ))

proc rotationParam(actions: Actions, srcStart, srcDur: float, clipDur: int,
    rate: float): JsonNode =
  ## Premiere Motion "Rotation" (id 5), in degrees, clockwise-positive (matching
  ## auto-editor). `spin` turns at a constant rate, so two linear keyframes (start
  ## angle -> end angle over the clip) reproduce it exactly; `rotate` is a fixed
  ## angle. Note: Premiere rotates in place and does not expand the canvas the way
  ## auto-editor's spin does, so the corners are not auto-fit (they clip / show
  ## through) unless you also scale the clip down.
  # Premiere caps Rotation near +/-90 turns. A spin that exceeds it is written as
  # a sawtooth: sweep in <=89-turn segments and reset on a 360-degree multiple,
  # which is the same orientation so the reset is invisible, keeping every keyframe
  # value within the cap. 89*360 leaves margin below the cap for a non-zero start.
  const maxDeg = 32040.0
  for a in actions:
    if a.kind == actSpin:
      let startDeg = rotDeg(a.sStart).float
      if srcDur <= 1.0 or clipDur <= 1:
        return startParam("Rotation", 5, %startDeg, rate)
      # angle(local) = startDeg + rate_deg_per_sec * local/fps (fps == `rate`).
      let totalDeg = a.sRate.float * float(clipDur - 1) / rate
      let lastPos = srcStart + srcDur - 1.0
      let span = srcDur - 1.0
      let kfs = newJArray()
      kfs.add %*{"Position": rationalTime(rate, srcStart), "Value": startDeg}
      if abs(totalDeg) <= maxDeg:
        kfs.add %*{"Position": rationalTime(rate, lastPos),
                   "Value": startDeg + totalDeg}
      else:
        let sign = (if totalDeg < 0: -1.0 else: 1.0)
        let n = int(abs(totalDeg) / maxDeg)
        var resets = 0
        for k in 1 .. n:
          let posK = round(srcStart + (k.float * maxDeg / abs(totalDeg)) * span)
          if posK + 1.0 >= lastPos: break  # no room before the end; fold into last
          kfs.add %*{"Position": rationalTime(rate, posK),
                     "Value": startDeg + sign * maxDeg}
          kfs.add %*{"Position": rationalTime(rate, posK + 1.0), "Value": startDeg}
          resets = k
        kfs.add %*{"Position": rationalTime(rate, lastPos),
                   "Value": startDeg + totalDeg - sign * maxDeg * resets.float}
      return %*{"DisplayName": "Rotation", "ID": 5, "Keyframes": kfs}
    if a.kind == actRotate:
      return startParam("Rotation", 5, %rotDeg(a.rStart).float, rate)
  startParam("Rotation", 5, %0.0, rate)

proc motionEffect(rate: float, position: JsonNode, scalePct: float,
    rotation: JsonNode): JsonNode =
  effectNode("AE.ADBE Motion", "Motion", "", true, jarr(
    startParam("Position", 1, position, rate),
    startParam("Scale", 2, %scalePct, rate),
    startParam("Scale Width", 3, %scalePct, rate),
    startParam(" ", 4, %true, rate),
    rotation,
    startParam("Anchor Point", 6, center(), rate),
    startParam("Anti-flicker Filter", 7, %0.0, rate),
    startParam("Crop Left", 8, %0.0, rate),
    startParam("Crop Top", 9, %0.0, rate),
    startParam("Crop Right", 10, %0.0, rate),
    startParam("Crop Bottom", 11, %0.0, rate),
  ))

proc contentSize(actions: Actions, srcW, srcH: float): (float, float) =
  ## Size of the picture's bounding box after rotation expansion, matching the
  ## render: `spin` rotates inside a fixed square sized to the diagonal (so it never
  ## clips at any angle), while static `rotate` expands to the rotated bounding box.
  for a in actions:
    if a.kind == actSpin:
      let side = float((int(ceil(hypot(srcW, srcH))) + 1) and not 1)
      return (side, side)
    if a.kind == actRotate:
      let rad = rotDeg(a.rStart).float * PI / 180.0
      return (abs(srcW * cos(rad)) + abs(srcH * sin(rad)),
              abs(srcW * sin(rad)) + abs(srcH * cos(rad)))
  (srcW, srcH)

proc motionFor(actions: Actions, mi: MediaInfo, res: (int32, int32),
    srcStart, srcDur: float, clipDur: int, rate: float): JsonNode =
  ## Translate auto-editor's placement/scale into Premiere's intrinsic Motion. With
  ## an explicit `pos`, the picture is sized by its scale multiplier and positioned
  ## by the (rotation-expanded) content box's top-left corner. Without `pos` it is
  ## fit-and-centred to the canvas like the base layer (scaleWithPad). Scale is a
  ## percentage of the source's native size; Position is the clip centre as a
  ## fraction of the frame. Only the first pos keyframe is read (static placement).
  let (sw, sh) = mi.getRes()
  let srcW = sw.float
  let srcH = sh.float
  let (effW, effH) = contentSize(actions, srcW, srcH)
  let canvasW = res[0].float
  let canvasH = res[1].float

  var position = center()
  var scalePct = 100.0
  var hasPos = false
  for a in actions:
    if a.kind == actPos:
      hasPos = true
      let scale = (if a.pscaleKf.len > 0: a.pscaleKf[0].float else: 1.0)
      let x = (if a.pxKf.len > 0: a.pxKf[0].float else: 0.0)
      let y = (if a.pyKf.len > 0: a.pyKf[0].float else: 0.0)
      position = %*{"X": (x + effW * scale / 2.0) / canvasW,
                    "Y": (y + effH * scale / 2.0) / canvasH}
      scalePct = scale * 100.0
      break
  if not hasPos:
    # Fit the (rotation-expanded) content to the canvas and centre it. For an
    # un-rotated source this is the plain fit; for spin it shrinks so the diagonal
    # square fits, so the picture never clips as it turns.
    scalePct = min(canvasW / effW, canvasH / effH) * 100.0

  scalePct = round(scalePct * 10000.0) / 10000.0
  motionEffect(rate, position, scalePct,
    rotationParam(actions, srcStart, srcDur, clipDur, rate))

proc pctVal(v: float): float =
  ## auto-editor opacity is 0.0..1.0; Premiere wants a 0..100 percentage. Round off
  ## float32 storage noise (opacity is quantized to unorm16).
  round(v * 100.0 * 10000.0) / 10000.0

proc opacityKeyframes(act: Action, srcStart, srcDur: float, clipDur: int,
    rate: float): JsonNode =
  ## A Premiere Keyframes array for an animated opacity, positioned across the
  ## clip's source range (matching `source_range`). An un-eased ramp is exact: one
  ## keyframe per control point, linearly interpolated. An eased ramp is baked by
  ## sampling auto-editor's own curve at a bounded resolution.
  result = newJArray()
  let n = act.kf.len
  template kfNode(p: float, v: float): JsonNode =
    %*{"Position": rationalTime(rate, srcStart + round(p * (srcDur - 1.0))),
       "Value": pctVal(v)}
  if not act.hasEase:
    for i in 0 ..< n:
      let p = (if n == 1: 0.0 else: i.float / float(n - 1))
      result.add kfNode(p, act.kf[i].float)
  else:
    let animLen =
      case act.easeDurUnit
      of duClip: clipDur
      of duSec: max(1, int(round(act.easeDur.float * rate)))
      of duFrames: max(1, int(round(act.easeDur.float)))
    let denom = max(1, clipDur - 1)
    let samples = min(denom, 60)
    for s in 0 .. samples:
      let local = int(round(s.float / samples.float * denom.float))
      let prog = applyEase(act.easeCurve, clipT(local, animLen))
      result.add kfNode(local.float / denom.float, sampleKf(act.kf, prog).float)

proc opacityFor(actions: Actions, srcStart, srcDur: float, clipDur: int,
    rate: float): JsonNode =
  ## Premiere's intrinsic Opacity effect. A single value is a fixed StartValue; a
  ## keyframe ramp becomes an animated Keyframes parameter.
  for a in actions:
    if a.kind == actOpacity and a.kf.len > 0:
      if a.kf.len == 1:
        return opacityEffect(rate, pctVal(a.kf[0].float))
      return effectNode("AE.ADBE Opacity", "Opacity", "", true, jarr(
        %*{"DisplayName": "Opacity", "ID": 1,
           "Keyframes": opacityKeyframes(a, srcStart, srcDur, clipDur, rate)},
        startParam("Blend Mode", 2, %18, rate),
        startParam("Blend Mode", 3, %0, rate),
      ))
  opacityEffect(rate, 100.0)

proc invertEffect(rate: float): JsonNode =
  effectNode("AE.ADBE Invert", "Invert", "", false, jarr(
    startParam("Channel", 1, %0, rate),
    startParam("Blend With Original", 2, %0.0, rate),
  ))

proc hflipEffect(): JsonNode =
  effectNode("AE.ADBE Horizontal Flip", "Horizontal Flip", "", false, newJArray())

proc vflipEffect(): JsonNode =
  effectNode("AE.ADBE Vertical Flip", "Vertical Flip", "", false, newJArray())

proc volumeEffect(): JsonNode =
  effectNode("Internal Volume Stereo", "Volume", "", true, jarr(
    keyframeParam("Mute", 0),
    keyframeParam("Level", 1),
  ))

proc clipPanner(rate: float): JsonNode =
  effectNode("PanProcessor", "Panner", "Panner", false, jarr(
    startParam("Balance", 0, %0.5, rate),
  ))

proc audioFaderEffect(): JsonNode =
  effectNode("AudioFader", "Track", "", false, jarr(
    keyframeParam("Volume", 0),
    keyframeParam("Mute", 1),
  ))

proc trackPanner(): JsonNode =
  effectNode("PanProcessor", "Panner", "Panner", false, jarr(
    keyframeParam("Balance", 0),
  ))

proc mediaRef(mi: MediaInfo, rate, availDur: float): JsonNode =
  ## `availDur` is the available media length in frames. For a still image this
  ## must cover the clip's source range, not the still's 1-frame "duration":
  ## Premiere maps a clip's effect-keyframe times against the media extent, so a
  ## 1-frame available_range stretches every keyframe animation (e.g. spin runs at
  ## half speed).
  %*{
    "DEFAULT_MEDIA": {
      "OTIO_SCHEMA": "ExternalReference.1",
      "metadata": {},
      "name": "",
      "available_range": {
        "OTIO_SCHEMA": "TimeRange.1",
        "duration": rationalTime(rate, availDur),
        "start_time": rationalTime(rate, 0.0)
      },
      "available_image_bounds": nil,
      "target_url": mi.path.absPath.pathToUri()
    }
  }

proc clipSpeed(actions: Actions): float =
  # `varispeed` and `speed` collapse to the same LinearTimeWarp `time_scalar`.
  # OTIO's time effects only model time remapping; there is no field for audio
  # pitch preservation (Premiere's "Maintain Audio Pitch"). Premiere itself
  # exports both identically and drops the distinction, so it cannot survive the
  # round-trip regardless of how we write the file.
  result = 1.0
  for a in actions:
    if a.kind in [actSpeed, actVarispeed]:
      result *= a.val.float

proc hasAction(actions: Actions, kind: ActionKind): bool =
  for a in actions:
    if a.kind == kind:
      return true

proc buildClip(clip: Clip, actions: Actions, mi: MediaInfo, rate: float,
    tb: AVRational, isVideo: bool, linkId: int, nbCh: int,
    res: (int32, int32)): JsonNode =
  let speed = clipSpeed(actions)
  let srcStart = round(clip.offset.float * speed)
  let srcDur = max(1.0, round(clip.dur.float * speed))

  # Available media length (frames). A still has ~no real duration, so size its
  # range to cover the clip; otherwise Premiere mis-scales its keyframe times.
  let realAvail = float(int(mi.duration * tb))
  let availDur = (if mi.v.len > 0 and realAvail <= 1.0: srcStart + srcDur
                  else: realAvail)

  let effectsArr = newJArray()
  if isVideo:
    effectsArr.add opacityFor(actions, srcStart, srcDur, clip.dur.int, rate)
    effectsArr.add motionFor(actions, mi, res, srcStart, srcDur, clip.dur.int, rate)
    if hasAction(actions, actInvert):
      effectsArr.add invertEffect(rate)
    if hasAction(actions, actHflip):
      effectsArr.add hflipEffect()
    if hasAction(actions, actVflip):
      effectsArr.add vflipEffect()
  else:
    effectsArr.add volumeEffect()
    effectsArr.add clipPanner(rate)
  # Premiere only writes a time warp on a re-timed clip; a no-op one at 1x makes
  # it treat the clip as time-remapped and drop the intrinsic Opacity/Motion.
  if speed != 1.0:
    effectsArr.add speedEffect(speed)

  let meta = newJObject()
  if not isVideo:
    let secondary = newJArray()
    for c in 0 ..< max(1, nbCh):
      secondary.add(%*{"SecondaryChannelIndex": c})
    meta["AudioChannels"] = %*{
      "ChannelType": (if nbCh >= 2: "Stereo" else: "Mono"),
      "SecondaryAssignments": secondary
    }
  meta["LinkID"] = %($linkId)
  meta["OriginalChannelGroupIndex"] = %0
  meta["SourceClipIndex"] = %0

  %*{
    "OTIO_SCHEMA": "Clip.2",
    "metadata": {"PremierePro_OTIO": meta},
    "name": agSplitFile(mi.path).name,
    "source_range": {
      "OTIO_SCHEMA": "TimeRange.1",
      "duration": rationalTime(rate, srcDur),
      "start_time": rationalTime(rate, srcStart)
    },
    "effects": effectsArr,
    "markers": newJArray(),
    "enabled": true,
    "media_references": mediaRef(mi, rate, availDur),
    "active_media_reference_key": "DEFAULT_MEDIA"
  }

proc writeSolidPng(path: string, w, h: cint, bg: RGBColor) =
  ## Encode a solid w×h RGB image to a PNG file. PNG is an image codec, so a single
  ## encoded packet is the whole file. Used to materialise `-bg` as real media the
  ## OTIO can reference (a generator/color-matte can't be carried portably).
  let codec = avcodec_find_encoder(ID_PNG)
  if codec == nil:
    error "PNG encoder not found"
  let ctx = avcodec_alloc_context3(codec)
  if ctx == nil:
    error "Could not allocate PNG encoder context"
  ctx.width = w
  ctx.height = h
  ctx.pix_fmt = AV_PIX_FMT_RGB24
  ctx.time_base = AVRational(num: 1, den: 1)
  if avcodec_open2(ctx, codec, nil) < 0:
    error "Could not open PNG encoder"

  let frame = av_frame_alloc()
  frame.format = AV_PIX_FMT_RGB24.cint
  frame.width = w
  frame.height = h
  if av_frame_get_buffer(frame, 32) < 0:
    error "Could not allocate PNG frame buffer"
  discard av_frame_make_writable(frame)
  for y in 0 ..< h:
    let row = cast[ptr UncheckedArray[uint8]](
      cast[int](frame.data[0]) + y.int * frame.linesize[0].int)
    for x in 0 ..< w:
      row[x * 3] = bg.red
      row[x * 3 + 1] = bg.green
      row[x * 3 + 2] = bg.blue

  let pkt = av_packet_alloc()
  if avcodec_send_frame(ctx, frame) < 0 or avcodec_receive_packet(ctx, pkt) < 0:
    error "Could not encode background PNG"
  var buf = newString(pkt.size)
  copyMem(addr buf[0], pkt.data, pkt.size)
  writeFile(path, buf)

  av_packet_free(addr pkt)
  av_frame_free(addr frame)
  avcodec_free_context(addr ctx)

proc bgClip(mi: MediaInfo, tl: v3, rate: float): JsonNode =
  ## A full-frame background clip referencing the generated `-bg` PNG. No effects
  ## of its own (opacity 100, fit-and-centre at native size = full frame, no
  ## rotation) and no LinkID, so it stays an independent bottom layer.
  %*{
    "OTIO_SCHEMA": "Clip.2",
    "metadata": {"PremierePro_OTIO": {
      "OriginalChannelGroupIndex": 0, "SourceClipIndex": 0}},
    "name": agSplitFile(mi.path).name,
    "source_range": {
      "OTIO_SCHEMA": "TimeRange.1",
      "duration": rationalTime(rate, tl.len.float),
      "start_time": rationalTime(rate, 0.0)
    },
    "effects": jarr(
      opacityFor(aNil, 0.0, tl.len.float, tl.len.int, rate),
      motionFor(aNil, mi, tl.res, 0.0, tl.len.float, tl.len.int, rate)
    ),
    "markers": newJArray(),
    "enabled": true,
    "media_references": mediaRef(mi, rate, tl.len.float),
    "active_media_reference_key": "DEFAULT_MEDIA"
  }

proc gapNode(rate: float, dur: int64): JsonNode =
  %*{
    "OTIO_SCHEMA": "Gap.1", "metadata": newJObject(), "name": "",
    "source_range": {
      "OTIO_SCHEMA": "TimeRange.1",
      "duration": rationalTime(rate, dur.float),
      "start_time": rationalTime(rate, 0.0)
    },
    "effects": newJArray(), "markers": newJArray(), "enabled": true
  }

proc transitionNode(rate: float, t: Transition): JsonNode =
  let inOffset = case t.alignment
    of taStart: 0'i64
    of taCenter: t.dur div 2
    of taEnd: t.dur
  %*{
    "OTIO_SCHEMA": "Transition.1",
    "metadata": newJObject(),
    "name": "Dissolve",
    "transition_type": "SMPTE_Dissolve",
    "parameters": newJObject(),
    "in_offset": rationalTime(rate, inOffset.float),
    "out_offset": rationalTime(rate, (t.dur - inOffset).float)
  }

proc otioWrite*(name, output: string, tl: v3) =
  let rate = tl.tb.num.float / tl.tb.den.float
  let (width, height) = tl.res
  let nbCh = (if tl.layout != nil: tl.layout.nb_channels.int else: 2)

  var ptrToMi = initTable[ptr string, MediaInfo]()
  for ptrSrc in tl.uniqueSources:
    ptrToMi[ptrSrc] = initMediaInfo(ptrSrc[])

  let children = newJArray()

  # A non-default `-bg` is materialised as a solid PNG written next to the output
  # and referenced as the bottom video track, so the colour shows wherever the
  # picture doesn't cover the frame. (Premiere's color-matte generator references a
  # project-local item by GUID and can't be carried portably, so it isn't used.)
  var videoTrackNum = 0
  if output != "-" and tl.bg != RGBColor(red: 0, green: 0, blue: 0):
    let (dir, nm, _) = splitFile(output)
    let pngPath = dir / (nm & "-bg.png")
    writeSolidPng(pngPath, tl.res[0], tl.res[1], tl.bg)
    videoTrackNum += 1
    children.add %*{
      "OTIO_SCHEMA": "Track.1",
      "metadata": newJObject(),
      "name": "Video " & $videoTrackNum,
      "source_range": newJNull(),
      "effects": newJArray(),
      "markers": newJArray(),
      "enabled": true,
      "children": jarr(bgClip(initMediaInfo(pngPath), tl, rate)),
      "kind": "Video"
    }

  # LinkID groups the parts of one linked A/V clip in Premiere. The base video
  # clip j and the audio clips at index j (the same cut) share LinkID j+1;
  # independent `add:` overlay clips must get unique IDs past that range, or
  # Premiere fuses them with the audio (showing it as "[V]" and muting it).
  var maxAligned = 0
  if tl.v.len > 0:
    maxAligned = max(maxAligned, tl.v[0].len)
  for atrack in tl.a:
    maxAligned = max(maxAligned, atrack.len)
  var nextOverlayLink = maxAligned

  for vIdx, track in tl.v:
    let clipArr = newJArray()
    let transitions = (if vIdx < tl.vt.len: tl.vt[vIdx] else: @[])
    let transitionLinks = transitionPlan(track, transitions)
    var cursor = 0'i64
    for j, clip in track:
      # An audio-only timeline that gained `add:` overlays has a synthesized base
      # track with no source file; it exists only as a render canvas, so there is
      # nothing to reference here. Skip it (and any track left empty).
      if clip.src == nil:
        continue
      var linkId: int
      if vIdx == 0:
        linkId = j + 1
      else:
        inc nextOverlayLink
        linkId = nextOverlayLink
      if transitionLinks[j].incoming >= 0:
        let t = transitions[transitionLinks[j].incoming]
        if t.alignment == taStart:
          clipArr.add gapNode(rate, 0)
          clipArr.add transitionNode(rate, t)
      if clip.start > cursor: clipArr.add gapNode(rate, clip.start - cursor)
      let actions = tl.effects[clip.effects]
      clipArr.add buildClip(clip, actions, ptrToMi[clip.src], rate, tb = tl.tb,
        isVideo = true, linkId = linkId, nbCh = nbCh, res = tl.res)
      cursor = clip.start + clip.dur
      if transitionLinks[j].outgoing >= 0:
        let t = transitions[transitionLinks[j].outgoing]
        clipArr.add transitionNode(rate, t)
        if t.alignment == taEnd:
          clipArr.add gapNode(rate, 0)
    if clipArr.len == 0:
      continue
    videoTrackNum += 1
    children.add %*{
      "OTIO_SCHEMA": "Track.1",
      "metadata": newJObject(),
      "name": "Video " & $videoTrackNum,
      "source_range": nil,
      "effects": newJArray(),
      "markers": newJArray(),
      "enabled": true,
      "children": clipArr,
      "kind": "Video"
    }

  for i, track in tl.a:
    let clipArr = newJArray()
    let transitions = (if i < tl.at.len: tl.at[i] else: @[])
    let transitionLinks = transitionPlan(track, transitions)
    var cursor = 0'i64
    for j, clip in track:
      if transitionLinks[j].incoming >= 0:
        let t = transitions[transitionLinks[j].incoming]
        if t.alignment == taStart:
          clipArr.add gapNode(rate, 0)
          clipArr.add transitionNode(rate, t)
      if clip.start > cursor: clipArr.add gapNode(rate, clip.start - cursor)
      let actions = tl.effects[clip.effects]
      clipArr.add buildClip(clip, actions, ptrToMi[clip.src], rate, tb = tl.tb,
        isVideo = false, linkId = j + 1, nbCh = nbCh, res = tl.res)
      cursor = clip.start + clip.dur
      if transitionLinks[j].outgoing >= 0:
        let t = transitions[transitionLinks[j].outgoing]
        clipArr.add transitionNode(rate, t)
        if t.alignment == taEnd:
          clipArr.add gapNode(rate, 0)
    children.add %*{
      "OTIO_SCHEMA": "Track.1",
      "metadata": {"PremierePro_OTIO": {"AudioChannels": {
        "ChannelType": (if nbCh >= 2: "Stereo" else: "Mono"),
        "NumberOfChannels": nbCh
      }}},
      "name": "Audio " & $(i + 1),
      "source_range": nil,
      "effects": jarr(audioFaderEffect(), trackPanner()),
      "markers": newJArray(),
      "enabled": true,
      "children": clipArr,
      "kind": "Audio"
    }

  let timeline = %*{
    "OTIO_SCHEMA": "Timeline.1",
    "metadata": {"PremierePro_OTIO": {"MetadataVersion": "1.0"}},
    "name": name,
    "global_start_time": rationalTime(rate, 0.0),
    "tracks": {
      "OTIO_SCHEMA": "Stack.1",
      "metadata": {"PremierePro_OTIO": {
        "AudioFrameRate": tl.sr.float,
        "PixelAspectRatio": {"denominator": 1.0, "numerator": 1.0},
        "VideoFrameRate": rate,
        "VideoResolution": {"height": height.int, "width": width.int}
      }},
      "name": name,
      "source_range": nil,
      "effects": newJArray(),
      "markers": newJArray(),
      "enabled": true,
      "children": children
    }
  }

  if output == "-":
    echo pretty(timeline, indent = 4)
  else:
    writeFile(output, pretty(timeline, indent = 4))
