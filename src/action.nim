import std/[math, strutils, options]
import ./util/dnorm16

type
  ActionKind* = enum
    actSpeed, actVarispeed, actVolume, actDeesser, actInvert, actZoom, actHflip,
    actVflip, actOpacity, actBlur, actBrightness, actLuv, actLens, actRotate,
    actEase

  Easing* = enum  # interpolation curve for animations
    easeLinear, easeIn, easeOut, easeInOut

  DurUnit* = enum  # how an ease duration is measured
    duClip,    # the whole clip/section (the default)
    duSec,     # seconds
    duFrames   # timeline frames

  # Represents a full-sized action. Animatable scalar effects carry a `from`/`to`
  # pair (when from == to the action is static). The easing curve and duration
  # live in a separate `actEase` envelope that applies to the animated actions
  # following it within the same effect group.
  Action* = object
    case kind*: ActionKind
    of actInvert, actHflip, actVflip:
      discard
    of actEase:
      easeCurve*: Easing
      easeDurUnit*: DurUnit
      easeDur*: float32      # magnitude in easeDurUnit (ignored for duClip)
    of actOpacity:
      nFrom*, nTo*: Unorm16
    of actRotate:
      rStart*: Unorm16       # circular [0, 360) start angle
      rRate*: float32        # spin rate in degrees/second (0 = static)
    of actBrightness:
      sFrom*, sTo*: Snorm16
    of actLens:
      k1*, k2*: Snorm16
    of actSpeed, actVarispeed, actVolume:
      val*: float32
    of actZoom, actBlur:
      fFrom*, fTo*: float32
    of actDeesser:
      intensity*, maxd*, freq*: Unorm16
    of actLuv:
      contrast*: float32
      saturation*: float32
      brighthue*: Snorm16

  Actions* = distinct int # A fat pointer to a list of action in atf-8 format.

  # atf-8: store actions in as small a space as possible, inspirited by utf-8.

  ActionParseError* = object of CatchableError

  ActionType* = enum  # which media stream(s) the action affects
    atAudio, atVideo, atBoth

  RangeDoc* = object
    lo*, hi*: float
    loIncl*, hiIncl*: bool  # closed (inclusive) bounds
    each*: bool             # the interval applies to each positional arg

  ActionDef* = object
    name*: string
    atype*: ActionType
    argSpec*: string  # storage type ("float32") or positional spec ("k1[:k2]")
    range*: Option[RangeDoc]
    help*: string

func rng(lo, hi: float; loIncl = true, hiIncl = true, each = false): Option[RangeDoc] =
  some(RangeDoc(lo: lo, hi: hi, loIncl: loIncl, hiIncl: hiIncl, each: each))

func `$`*(r: RangeDoc): string =
  ## e.g. "(0.0, 99999.0)", "each [-1.0, 1.0]"
  (if r.each: "each " else: "") &
    (if r.loIncl: "[" else: "(") & $r.lo & ", " & $r.hi &
    (if r.hiIncl: "]" else: ")")

func `$`*(t: ActionType): string =
  case t
  of atAudio: "A"
  of atVideo: "V"
  of atBoth: "AV"

const actionDefs*: seq[ActionDef] = @[
  ActionDef(name: "nil", atype: atBoth,
    help: "Do nothing. Keep the section unchanged at normal speed and pitch."),
  ActionDef(name: "cut", atype: atBoth,
    help: "Remove the section completely from the output."),
  ActionDef(name: "speed", atype: atBoth, argSpec: "float32", range: rng(0.0, 99999.0, loIncl = false, hiIncl = false),
    help: "Change the playback speed while preserving pitch via time-stretching. 1.0 = unchanged, 2.0 = twice as fast, 0.5 = half speed. Implemented with ffmpeg's `atempo` filter."),
  ActionDef(name: "varispeed", atype: atBoth, argSpec: "float32", range: rng(0.2, 100.0),
    help: "Change the playback speed by resampling, so pitch shifts along with it, like analog tape or vinyl. 1.0 = unchanged, 2.0 = twice as fast and an octave higher. Implemented with ffmpeg's `asetrate` + `aresample` filters."),
  ActionDef(name: "volume", atype: atAudio, argSpec: "float32",
    help: "Scale the audio volume by val. 1.0 = unchanged, 0.5 = half (-6 dB), 2.0 = double (+6 dB)."),
  ActionDef(name: "deesser", atype: atAudio, argSpec: "intensity[:max[:freq]]", range: rng(0.0, 1.0, each = true),
    help: """
Reduce harsh "s" and "sh" sibilance in the section. Implemented via ffmpeg's `deesser` filter.
Positional args: `intensity` sets how much to de-ess (0.0 = none, 1.0 = maximum), `max` caps the reduction (default 0.5), and `freq` sets the split frequency (default 0.5)."""),
  ActionDef(name: "invert", atype: atVideo,
    help: "Invert every pixel in the section, producing a photo-negative."),
  ActionDef(name: "hflip", atype: atVideo,
    help: "Flip the section horizontally, mirroring it left to right."),
  ActionDef(name: "vflip", atype: atVideo,
    help: "Flip the section vertically, mirroring it top to bottom."),
  ActionDef(name: "zoom", atype: atVideo, argSpec: "float32", range: rng(0.0, 100.0, loIncl = false),
    help: "Scale the picture about its center by val. 1.0 = no zoom, 2.0 = zoom in 2x, 0.5 = zoom out 2x. Animatable: accepts a `from..to` ramp."),
  ActionDef(name: "opacity", atype: atVideo, argSpec: "unorm16", range: rng(0.0, 1.0),
    help: "Blend the section against the background. 1.0 = fully opaque, 0.0 = fully transparent. Animatable: accepts a `from..to` ramp."),
  ActionDef(name: "blur", atype: atVideo, argSpec: "float32", range: rng(0.0, 1024.0),
    help: "Gaussian-blur the picture by sigma = val. 0.0 = no blur; larger values blur more. Animatable: accepts a `from..to` ramp."),
  ActionDef(name: "brightness", atype: atVideo, argSpec: "snorm16", range: rng(-1.0, 1.0),
    help: "Shift brightness by adding an equal offset to the R, G, and B channels. 0.0 = unchanged, positive brightens, negative darkens. Implemented via ffmpeg's `lutrgb` filter. Animatable: accepts a `from..to` ramp."),
  ActionDef(name: "brighthue", atype: atVideo, argSpec: "snorm16", range: rng(-1.0, 1.0),
    help: "Shift luma by offsetting the Y channel. 0.0 = unchanged, positive brightens, negative darkens."),
  ActionDef(name: "contrast", atype: atVideo, argSpec: "float32", range: rng(-2.0, 2.0),
    help: "Scale contrast around mid-gray. 1.0 = unchanged, higher values increase contrast, lower values reduce it. Implemented via ffmpeg's `lutyuv` filter."),
  ActionDef(name: "saturation", atype: atVideo, argSpec: "float32", range: rng(0.0, 3.0),
    help: "Scale color saturation. 1.0 = unchanged, 0.0 = grayscale, higher values are more vivid. Implemented via ffmpeg's `lutyuv` filter."),
  ActionDef(name: "rotate", atype: atVideo, argSpec: "deg[/rate]",
    help: "Rotate the picture clockwise about its center, filling the exposed corners with the background color. `rotate:deg` holds a fixed angle. `rotate:deg/rate` spins continuously, starting at `deg` and turning at `rate` degrees per second (negative is counter-clockwise), e.g. `rotate:0/120`. Implemented via ffmpeg's `rotate` filter."),
  ActionDef(name: "lens", atype: atVideo, argSpec: "k1[:k2]", range: rng(-1.0, 1.0, each = true),
    help: """
Distort the picture like a camera lens. With no arguments, a fun fisheye is applied. Implemented via ffmpeg's `lenscorrection` filter.
Positional args: `k1` is the quadratic correction factor and `k2` the double-quadratic factor. Negative values bulge the image outward (fisheye); positive values pinch it inward (pincushion)."""),
  ActionDef(name: "ease", atype: atBoth, argSpec: "curve[:duration]",
    help: """
Set the interpolation envelope for the animated actions that follow it in the same group. `curve` is one of `linear`, `in`, `out`, or `inout`.
The optional `duration` (e.g. `2sec` or a bare frame count) is how long the animation takes before holding at its end value; omitted, it spans the whole section. Animated values are written as a ramp, e.g. `zoom:1..2`."""),
]

# Effects whose value can be a ramp ("from..to") driven by an `ease` envelope.
const animScalar* = ["zoom", "opacity", "blur", "brightness"]

const aNil* = Actions(0)
const aCut* = Actions(1)

func isCut*(a: Actions): bool = int(a) == 1
func isEmpty*(a: Actions): bool = int(a) == 0

const
  luvBrighthueId* = toSnorm16(0.0'f32)
  luvContrastId* = 1.0'f32
  luvSaturationId* = 1.0'f32

func applyEase*(e: Easing, t: float32): float32 =
  let x = clamp(t, 0.0'f32, 1.0'f32)
  case e
  of easeLinear: x
  of easeIn: x * x
  of easeOut: 1.0'f32 - (1.0'f32 - x) * (1.0'f32 - x)
  of easeInOut:
    if x < 0.5'f32: 2.0'f32 * x * x
    else: 1.0'f32 - 2.0'f32 * (1.0'f32 - x) * (1.0'f32 - x)

func easeName(e: Easing): string =
  case e
  of easeLinear: "linear"
  of easeIn: "in"
  of easeOut: "out"
  of easeInOut: "inout"

proc parseDuration(spec: string): (float32, DurUnit) {.raises: [ActionParseError].} =
  ## "2sec" -> (2, duSec); "30" or "30frames" -> (30, duFrames).
  var s = spec
  var unit = duFrames
  for suf in ["seconds", "second", "sec"]:
    if s.endsWith(suf):
      unit = duSec
      s = s[0 ..< s.len - suf.len]
      break
  if unit == duFrames:
    for suf in ["frames", "frame", "f"]:
      if s.endsWith(suf):
        s = s[0 ..< s.len - suf.len]
        break
  try:
    (parseFloat(s).float32, unit)
  except ValueError:
    raise newException(ActionParseError, "Invalid duration: " & spec)

func rotDeg*(code: Unorm16): float32 =
  ## Decode a circular rotate angle back into [0, 360) degrees.
  uint16(code).float32 / 65536.0'f32 * 360.0'f32

func rotCode(deg: float32): uint16 =
  ## Quantize degrees into a circular [0, 360) bucket (see the rotate action).
  let turns = deg / 360.0'f32
  let frac = turns - floor(turns)
  uint16(int(round(frac * 65536.0'f32)) and 0xFFFF)

proc parseRamp(spec: string): (float32, float32) {.raises: [ActionParseError].} =
  ## "30" -> (30, 30); "0..360" -> (0, 360), interpolated across the section.
  let idx = spec.find("..")
  try:
    if idx >= 0:
      (parseFloat(spec[0 ..< idx]).float32, parseFloat(spec[idx + 2 .. ^1]).float32)
    else:
      let v = parseFloat(spec).float32
      (v, v)
  except ValueError:
    raise newException(ActionParseError, "Invalid float value")

proc parseEasing(spec: string): Easing {.raises: [ActionParseError].} =
  let name = if spec.startsWith("ease="): spec[5 .. ^1] else: spec
  case name
  of "linear": easeLinear
  of "in": easeIn
  of "out": easeOut
  of "inout", "in-out": easeInOut
  else: raise newException(ActionParseError, "Unknown easing: " & spec)

func parseAction*(val: string): Action {.raises: [ActionParseError].} =
  if val == "invert":
    return Action(kind: actInvert)
  if val == "hflip":
    return Action(kind: actHflip)
  if val == "vflip":
    return Action(kind: actVflip)

  let parts = val.split(":")

  # ease envelope: ease:curve[:duration]
  if parts[0] == "ease" and parts.len in {2, 3}:
    let curve = parseEasing(parts[1])
    if parts.len == 3:
      let (mag, unit) = parseDuration(parts[2])
      return Action(kind: actEase, easeCurve: curve, easeDurUnit: unit, easeDur: mag)
    return Action(kind: actEase, easeCurve: curve, easeDurUnit: duClip, easeDur: 0.0'f32)

  # deesser takes positional args: intensity[:max[:freq]]
  if parts.len >= 2 and parts.len <= 4 and parts[0] == "deesser":
    var vals = [toUnorm16(0.0), halfUnorm16, halfUnorm16]
    for idx in 1 ..< parts.len:
      vals[idx - 1] = (
        try:
          toUnorm16(parseFloat(parts[idx]).float32)
        except ValueError:
          raise newException(ActionParseError, "Invalid float value")
      )
    return Action(kind: actDeesser,
      intensity: vals[0], maxd: vals[1], freq: vals[2]
    )

  # lens takes positional args: [k1[:k2]]
  if parts[0] == "lens" and parts.len <= 3:
    if parts.len == 1:
      # A fun fisheye bulge, used when `lens` is given with no arguments.
      return Action(kind: actLens, k1: toSnorm16(-0.5'f32), k2: toSnorm16(0.0'f32))
    var k = [0.0'f32, 0.0'f32]
    for idx in 1 ..< parts.len:
      k[idx - 1] = (
        try:
          parseFloat(parts[idx]).float32
        except ValueError:
          raise newException(ActionParseError, "Invalid float value")
      )
    for v in k:
      if v < -1.0 or v > 1.0:
        raise newException(ActionParseError, "lens factors must be in [-1.0, 1.0]")
    return Action(kind: actLens, k1: toSnorm16(k[0]), k2: toSnorm16(k[1]))

  # rotate: a fixed angle "rotate:deg", or "rotate:deg/rate" for a continuous
  # spin starting at `deg` and turning `rate` degrees/second.
  if parts[0] == "rotate" and parts.len == 2:
    let spec = parts[1]
    let slash = spec.find('/')
    try:
      if slash < 0:
        return Action(kind: actRotate, rStart: Unorm16(rotCode(parseFloat(spec).float32)),
          rRate: 0.0'f32)
      return Action(kind: actRotate,
        rStart: Unorm16(rotCode(parseFloat(spec[0 ..< slash]).float32)),
        rRate: parseFloat(spec[slash + 1 .. ^1]).float32)
    except ValueError:
      raise newException(ActionParseError, "Invalid float value")

  # Animatable scalar effects accept a constant or a ramp ("from..to"):
  #   zoom:2   zoom:1..2
  if parts[0] in animScalar and parts.len == 2:
    let (fromV, toV) = parseRamp(parts[1])
    case parts[0]
    of "zoom":
      if fromV <= 0.0 or toV <= 0.0:
        raise newException(ActionParseError, "zoom value must be greater than 0.0")
      return Action(kind: actZoom, fFrom: fromV, fTo: toV)
    of "blur":
      return Action(kind: actBlur, fFrom: fromV, fTo: toV)
    of "opacity":
      if fromV < 0.0 or fromV > 1.0 or toV < 0.0 or toV > 1.0:
        raise newException(ActionParseError, "opacity must be in [0.0, 1.0]")
      return Action(kind: actOpacity, nFrom: toUnorm16(fromV), nTo: toUnorm16(toV))
    of "brightness":
      if fromV < -1.0 or fromV > 1.0 or toV < -1.0 or toV > 1.0:
        raise newException(ActionParseError, "brightness must be in [-1.0, 1.0]")
      return Action(kind: actBrightness, sFrom: toSnorm16(fromV), sTo: toSnorm16(toV))
    else: discard

  if parts.len == 2:
    let effectType = parts[0]
    let effectVal = (
      try:
        parseFloat(parts[1]).float32
      except ValueError:
        raise newException(ActionParseError, "Invalid float value")
    )
    case effectType
    of "speed": return Action(kind: actSpeed, val: effectVal)
    of "volume": return Action(kind: actVolume, val: effectVal)
    of "varispeed": return Action(kind: actVarispeed, val: effectVal)
    of "brighthue":
      return Action(kind: actLuv, brighthue: effectVal,
        contrast: luvContrastId, saturation: luvSaturationId)
    of "contrast":
      if effectVal < -2.0 or effectVal > 2.0:
        raise newException(ActionParseError, "contrast must be in [-2.0, 2.0]")
      return Action(kind: actLuv, brighthue: luvBrighthueId,
        contrast: effectVal, saturation: luvSaturationId)
    of "saturation":
      if effectVal < 0.0 or effectVal > 3.0:
        raise newException(ActionParseError, "saturation must be in [0.0, 3.0]")
      return Action(kind: actLuv, brighthue: luvBrighthueId,
        contrast: luvContrastId, saturation: effectVal)
    else: discard

  raise newException(ActionParseError, "Unknown action: " & val)

# The renderer supplies `p`, the eased progress in [0, 1] (the envelope's curve
# has already been applied), and these map it onto each effect's value range.
func rampAt*(a: Action, p: float32): float32 =
  ## Interpolated value for actZoom / actBlur.
  a.fFrom + (a.fTo - a.fFrom) * p

func opacityAt*(a: Action, p: float32): float32 =
  ## Interpolated opacity in [0, 1].
  let f0 = a.nFrom.toFloat32
  f0 + (a.nTo.toFloat32 - f0) * p

func brightnessAt*(a: Action, p: float32): float32 =
  ## Interpolated brightness in [-1, 1].
  let f0 = a.sFrom.toFloat32
  f0 + (a.sTo.toFloat32 - f0) * p

when not defined(nimscript):
  func `$`*(act: Action): string =
    case act.kind
    of actInvert: "invert"
    of actHflip: "hflip"
    of actVflip: "vflip"
    of actSpeed: "speed:" & $act.val
    of actVarispeed: "varispeed:" & $act.val
    of actVolume: "volume:" & $act.val
    of actDeesser:
      let i = act.intensity
      let m = act.maxd
      let f = act.freq
      "deesser:" & $i & ":" & $m & ":" & $f
    of actEase:
      case act.easeDurUnit
      of duClip: "ease:" & easeName(act.easeCurve)
      of duSec: "ease:" & easeName(act.easeCurve) & ":" & $act.easeDur & "sec"
      of duFrames: "ease:" & easeName(act.easeCurve) & ":" & $act.easeDur
    of actZoom:
      if act.fFrom == act.fTo: "zoom:" & $act.fFrom
      else: "zoom:" & $act.fFrom & ".." & $act.fTo
    of actOpacity:
      if act.nFrom == act.nTo: "opacity:" & $act.nFrom
      else: "opacity:" & $act.nFrom & ".." & $act.nTo
    of actBlur:
      if act.fFrom == act.fTo: "blur:" & $act.fFrom
      else: "blur:" & $act.fFrom & ".." & $act.fTo
    of actRotate:
      let startDeg = rotDeg(act.rStart)
      if act.rRate == 0.0'f32: "rotate:" & $startDeg
      else: "rotate:" & $startDeg & "/" & $act.rRate
    of actBrightness:
      if act.sFrom == act.sTo: "brightness:" & $act.sFrom
      else: "brightness:" & $act.sFrom & ".." & $act.sTo
    of actLuv:
      var parts: seq[string]
      if act.brighthue != luvBrighthueId: parts.add "brighthue:" & $act.brighthue
      if act.contrast != luvContrastId: parts.add "contrast:" & $act.contrast
      if act.saturation != luvSaturationId: parts.add "saturation:" & $act.saturation
      if parts.len == 0: "brighthue:0.0" else: parts.join(",")
    of actLens: "lens:" & $act.k1 & ":" & $act.k2

  func actionByteSize(kind: ActionKind): int =
    case kind
    of actInvert, actHflip, actVflip: 1
    of actSpeed, actVarispeed, actVolume, actLens, actOpacity, actBrightness: 5
    of actRotate: 7
    of actDeesser: 7
    of actEase: 7        # curve(1) + durUnit(1) + durMag(float32)
    of actZoom, actBlur: 9
    of actLuv: 11

  func len*(a: Actions): int =  # byte length
    if int(a) <= 1: 0
    else: int(cast[ptr uint16](int(a))[])

  iterator items*(a: Actions): Action =
    if int(a) > 1:
      let n = a.len
      let base = cast[ptr UncheckedArray[uint8]](int(a) + sizeof(uint16))
      var i = 0
      while i < n:
        let kind = cast[ActionKind](base[i])
        case kind
        of actInvert, actHflip, actVflip:
          yield Action(kind: kind)
          i += 1
        of actSpeed, actVarispeed, actVolume:
          var v: float32
          copyMem(addr v, addr base[i + 1], sizeof(float32))
          yield Action(kind: kind, val: v)
          i += 5
        of actEase:
          var d: float32
          copyMem(addr d, addr base[i + 3], sizeof(float32))
          yield Action(kind: actEase, easeCurve: Easing(base[i + 1].int),
            easeDurUnit: DurUnit(base[i + 2].int), easeDur: d)
          i += 7
        of actZoom, actBlur:
          var f0, f1: float32
          copyMem(addr f0, addr base[i + 1], sizeof(float32))
          copyMem(addr f1, addr base[i + 5], sizeof(float32))
          yield Action(kind: kind, fFrom: f0, fTo: f1)
          i += 9
        of actOpacity:
          var n0, n1: Unorm16
          copyMem(addr n0, addr base[i + 1], sizeof(Unorm16))
          copyMem(addr n1, addr base[i + 3], sizeof(Unorm16))
          yield Action(kind: actOpacity, nFrom: n0, nTo: n1)
          i += 5
        of actBrightness:
          var s0, s1: Snorm16
          copyMem(addr s0, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr s1, addr base[i + 3], sizeof(Snorm16))
          yield Action(kind: actBrightness, sFrom: s0, sTo: s1)
          i += 5
        of actRotate:
          var st: Unorm16
          var rate: float32
          copyMem(addr st, addr base[i + 1], sizeof(Unorm16))
          copyMem(addr rate, addr base[i + 3], sizeof(float32))
          yield Action(kind: actRotate, rStart: st, rRate: rate)
          i += 7
        of actDeesser:
          var iu, mu, fu: Unorm16
          copyMem(addr iu, addr base[i + 1], sizeof(Unorm16))
          copyMem(addr mu, addr base[i + 3], sizeof(Unorm16))
          copyMem(addr fu, addr base[i + 5], sizeof(Unorm16))
          yield Action(kind: actDeesser, intensity: iu, maxd: mu, freq: fu)
          i += 7
        of actLuv:
          var bh: Snorm16
          var c, s: float32
          copyMem(addr bh, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr c, addr base[i + 3], sizeof(float32))
          copyMem(addr s, addr base[i + 7], sizeof(float32))
          yield Action(kind: actLuv, brighthue: bh, contrast: c, saturation: s)
          i += 11
        of actLens:
          var k1v, k2v: Snorm16
          copyMem(addr k1v, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr k2v, addr base[i + 3], sizeof(Snorm16))
          yield Action(kind: actLens, k1: k1v, k2: k2v)
          i += 5

  func actionLen*(a: Actions): int =  # O(n)
    for _ in a: inc result

  func `==`*(a, b: Actions): bool =
    let ia = int(a)
    let ib = int(b)
    if ia == ib: return true
    if ia <= 1 or ib <= 1: return false
    let n = a.len
    if n != b.len: return false
    let pa = cast[ptr UncheckedArray[uint8]](ia + sizeof(uint16))
    let pb = cast[ptr UncheckedArray[uint8]](ib + sizeof(uint16))
    for i in 0 ..< n:
      if pa[i] != pb[i]: return false
    true

  proc newActions*(list: openArray[Action]): Actions =
    if list.len == 0: return aNil
    var total = 0
    for a in list: total += actionByteSize(a.kind)
    if total > 65535:
      raise newException(ActionParseError, "atf-8 buffer overflow: too many actions")
    let p = alloc(sizeof(uint16) + total)
    cast[ptr uint16](p)[] = uint16(total)
    let base = cast[ptr UncheckedArray[uint8]](cast[int](p) + sizeof(uint16))
    var i = 0
    for a in list:
      base[i] = uint8(ord(a.kind))
      case a.kind
      of actInvert, actHflip, actVflip:
        i += 1
      of actSpeed, actVarispeed, actVolume:
        var v = a.val
        copyMem(addr base[i + 1], addr v, sizeof(float32))
        i += 5
      of actEase:
        base[i + 1] = uint8(ord(a.easeCurve))
        base[i + 2] = uint8(ord(a.easeDurUnit))
        var d = a.easeDur
        copyMem(addr base[i + 3], addr d, sizeof(float32))
        i += 7
      of actZoom, actBlur:
        var f0 = a.fFrom
        var f1 = a.fTo
        copyMem(addr base[i + 1], addr f0, sizeof(float32))
        copyMem(addr base[i + 5], addr f1, sizeof(float32))
        i += 9
      of actOpacity:
        var n0 = a.nFrom
        var n1 = a.nTo
        copyMem(addr base[i + 1], addr n0, sizeof(Unorm16))
        copyMem(addr base[i + 3], addr n1, sizeof(Unorm16))
        i += 5
      of actBrightness:
        var s0 = a.sFrom
        var s1 = a.sTo
        copyMem(addr base[i + 1], addr s0, sizeof(Snorm16))
        copyMem(addr base[i + 3], addr s1, sizeof(Snorm16))
        i += 5
      of actRotate:
        var st = a.rStart
        var rate = a.rRate
        copyMem(addr base[i + 1], addr st, sizeof(Unorm16))
        copyMem(addr base[i + 3], addr rate, sizeof(float32))
        i += 7
      of actDeesser:
        var iu = a.intensity
        var mu = a.maxd
        var fu = a.freq
        copyMem(addr base[i + 1], addr iu, sizeof(Unorm16))
        copyMem(addr base[i + 3], addr mu, sizeof(Unorm16))
        copyMem(addr base[i + 5], addr fu, sizeof(Unorm16))
        i += 7
      of actLuv:
        var bh = toSnorm16(a.brighthue)
        var c = a.contrast
        var s = a.saturation
        copyMem(addr base[i + 1], addr bh, sizeof(Snorm16))
        copyMem(addr base[i + 3], addr c, sizeof(float32))
        copyMem(addr base[i + 7], addr s, sizeof(float32))
        i += 11
      of actLens:
        var k1v = a.k1
        var k2v = a.k2
        copyMem(addr base[i + 1], addr k1v, sizeof(Snorm16))
        copyMem(addr base[i + 3], addr k2v, sizeof(Snorm16))
        i += 5
    Actions(cast[int](p))

  proc parseActions*(val: string): Actions =
    var list: seq[Action]
    for part in val.strip().split(","):
      let trimmedPart = part.strip()
      if trimmedPart == "nil":
        continue
      if trimmedPart == "cut":
        return aCut

      # Desugar easing attached to an animatable action into a separate `ease`
      # envelope placed just before it:
      #   rotate:0..360:ease=inout       -> ease:inout , rotate:0..360
      #   rotate:0..360:ease=inout:2sec  -> ease:inout:2sec , rotate:0..360
      let segs = trimmedPart.split(":")
      var easeIdx = -1
      for k in 1 .. segs.high:
        if segs[k].startsWith("ease="):
          easeIdx = k
          break
      if easeIdx >= 0 and segs[0] in animScalar:
        var ease = Action(kind: actEase, easeCurve: parseEasing(segs[easeIdx]),
          easeDurUnit: duClip, easeDur: 0.0'f32)
        if easeIdx < segs.high:
          (ease.easeDur, ease.easeDurUnit) = parseDuration(segs[easeIdx + 1])
        list.add ease
        list.add parseAction(segs[0 ..< easeIdx].join(":"))
        continue

      let action = parseAction(trimmedPart)
      if action.kind == actLuv:
        # Adjacent-fusion: collapse this actLuv into the previous one if it's
        # also actLuv. Per field, the non-identity value wins; later wins on
        # genuine conflicts.
        if list.len > 0 and list[^1].kind == actLuv:
          var prev = list[^1]
          if action.brighthue != luvBrighthueId: prev.brighthue = action.brighthue
          if action.contrast != luvContrastId: prev.contrast = action.contrast
          if action.saturation != luvSaturationId: prev.saturation = action.saturation
          list[^1] = prev
          continue
      list.add action

    # Drop any all-identity actLuv (no-op).
    var pruned: seq[Action]
    for a in list:
      if a.kind == actLuv and a.brighthue == luvBrighthueId and
          a.contrast == luvContrastId and a.saturation == luvSaturationId:
        continue
      pruned.add a
    return newActions(pruned)

  func `$`*(a: Actions): string =
    if a.isCut: return "cut"
    if a.isEmpty: return "nil"
    var parts: seq[string]
    for action in a: parts.add $action
    parts.join(",")
