import std/[json, os, sets, tables]
from std/math import round
when defined(windows):
  import std/strutils

import ../[action, ffmpeg, media, timeline]
import ../util/[fun, rational]

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


proc pathToUri(a: string): string =
  let absPath = a.absolutePath()
  when defined(windows):
    "file:///" & absPath.replace('\\', '/')
  else:
    "file://" & absPath

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

proc opacityEffect(rate: float): JsonNode =
  effectNode("AE.ADBE Opacity", "Opacity", "", true, jarr(
    startParam("Opacity", 1, %100.0, rate),
    startParam("Blend Mode", 2, %18, rate),
    startParam("Blend Mode", 3, %0, rate),
  ))

proc motionEffect(rate: float): JsonNode =
  effectNode("AE.ADBE Motion", "Motion", "", true, jarr(
    startParam("Position", 1, center(), rate),
    startParam("Scale", 2, %100.0, rate),
    startParam("Scale Width", 3, %100.0, rate),
    startParam(" ", 4, %true, rate),
    startParam("Rotation", 5, %0.0, rate),
    startParam("Anchor Point", 6, center(), rate),
    startParam("Anti-flicker Filter", 7, %0.0, rate),
    startParam("Crop Left", 8, %0.0, rate),
    startParam("Crop Top", 9, %0.0, rate),
    startParam("Crop Right", 10, %0.0, rate),
    startParam("Crop Bottom", 11, %0.0, rate),
  ))

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

proc mediaRef(mi: MediaInfo, rate: float, tb: AVRational): JsonNode =
  let availDur = float(int(mi.duration * tb))
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
      "target_url": mi.path.pathToUri()
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
    tb: AVRational, isVideo: bool, linkId: int, nbCh: int): JsonNode =
  let speed = clipSpeed(actions)
  let srcStart = round(clip.offset.float * speed)
  let srcDur = max(1.0, round(clip.dur.float * speed))

  let effectsArr = newJArray()
  if isVideo:
    effectsArr.add opacityEffect(rate)
    effectsArr.add motionEffect(rate)
    if hasAction(actions, actInvert):
      effectsArr.add invertEffect(rate)
    if hasAction(actions, actHflip):
      effectsArr.add hflipEffect()
    if hasAction(actions, actVflip):
      effectsArr.add vflipEffect()
  else:
    effectsArr.add volumeEffect()
    effectsArr.add clipPanner(rate)
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
    "media_references": mediaRef(mi, rate, tb),
    "active_media_reference_key": "DEFAULT_MEDIA"
  }

proc otioWrite*(name, output: string, tl: v3) =
  let rate = tl.tb.num.float / tl.tb.den.float
  let (width, height) = tl.res
  let nbCh = (if tl.layout != nil: tl.layout.nb_channels.int else: 2)

  var ptrToMi = initTable[ptr string, MediaInfo]()
  for ptrSrc in tl.uniqueSources:
    ptrToMi[ptrSrc] = initMediaInfo(ptrSrc[])

  let children = newJArray()

  for i, track in tl.v:
    let clipArr = newJArray()
    for j, clip in track:
      let actions = tl.effects[clip.effects]
      clipArr.add buildClip(clip, actions, ptrToMi[clip.src], rate, tb = tl.tb,
        isVideo = true, linkId = j + 1, nbCh = nbCh)
    children.add %*{
      "OTIO_SCHEMA": "Track.1",
      "metadata": newJObject(),
      "name": "Video " & $(i + 1),
      "source_range": nil,
      "effects": newJArray(),
      "markers": newJArray(),
      "enabled": true,
      "children": clipArr,
      "kind": "Video"
    }

  for i, track in tl.a:
    let clipArr = newJArray()
    for j, clip in track:
      let actions = tl.effects[clip.effects]
      clipArr.add buildClip(clip, actions, ptrToMi[clip.src], rate, tb = tl.tb,
        isVideo = false, linkId = j + 1, nbCh = nbCh)
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
