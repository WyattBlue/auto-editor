import std/[strformat, strutils, xmltree]
from std/math import log10, round

import ../action

# Helpers shared by the MLT-based exporters (Shotcut, Kdenlive).

proc addProp*(parent: XmlNode, name, value: string) =
  let prop = newElement("property")
  prop.attrs = {"name": name}.toXmlAttributes()
  prop.add(newText(value))
  parent.add(prop)

func gainToDb*(gain: float32): string =
  let db = (if gain <= 0.0: -100.0 else: max(-100.0, 20.0 * log10(gain.float64)))
  $db

func isAnimated*(a: Action): bool = a.kf.len > 1

func mltFadeAnim*(a, b: string, dur: int64): string =
  ## Two-point linear fade ramp. A single-frame fade holds its start value;
  ## two keys on the same frame would be resolved arbitrarily by MLT.
  if dur <= 1: a
  else: &"0={a};{dur - 1}={b}"

func mltAnimValue*(a: Action, clipDur: int, fps: float64, asDb = false): string =
  ## An MLT property value for a scalar keyframe action: a plain value when
  ## static, otherwise an animation string "frame=value;..." with positions
  ## relative to the owning filter's `in` (0 .. clipDur-1). MLT interpolates
  ## linearly between control points, so an eased ramp is baked by sampling
  ## auto-editor's own curve at a bounded resolution.
  template fmtVal(v: float32): string =
    (if asDb: gainToDb(v) else: $v)
  if not a.isAnimated:
    return fmtVal(if a.kf.len == 1: a.kf[0] else: 1.0'f32)

  let denom = max(1, clipDur - 1)
  var parts: seq[string]
  if not a.hasEase:
    if a.kf.len - 1 <= denom:
      for i in 0 ..< a.kf.len:
        let f = int(round(i.float / float(a.kf.len - 1) * denom.float))
        parts.add &"{f}={fmtVal(a.kf[i])}"
    else:
      # More control points than frames would put several keys on one frame,
      # and MLT's behavior for duplicate keys is undefined; sample per frame.
      for f in 0 .. denom:
        parts.add &"{f}={fmtVal(sampleKf(a.kf, f.float32 / denom.float32))}"
  else:
    let animLen =
      case a.easeDurUnit
      of duClip: clipDur
      of duSec: max(1, int(round(a.easeDur.float64 * fps)))
      of duFrames: max(1, int(round(a.easeDur)))
    let samples = min(denom, 60)
    for s in 0 .. samples:
      let local = int(round(s.float / samples.float * denom.float))
      let v = sampleKf(a.kf, applyEase(a.easeCurve, clipT(local, animLen)))
      parts.add &"{local}={fmtVal(v)}"
  parts.join(";")
