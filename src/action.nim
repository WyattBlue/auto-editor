import std/[math, strutils, options]
import ./util/[dnorm16, color]

template writeAt(baseBuffer: auto, index: int, offset: int, val: untyped) =
  var temp = val
  copyMem(addr baseBuffer[index + offset], addr temp, sizeof(temp))

type
  ActionKind* = enum
    actSpeed, actVarispeed, actVolume, actDeesser, actInvert, actHflip, actVflip,
    actZoom, actOpacity, actBlur, actBrightness, actLuv, actLens, actRotate, actSpin,
    actDrawbox, actPos, actColorKey, actChromaKey, actLoop, actErosion, actChoke

  Easing* = enum  # interpolation curve for animations
    easeLinear, easeIn, easeOut, easeInOut

  DurUnit* = enum  # how an ease duration is measured
    duClip,    # the whole clip/section (the default)
    duSec,     # seconds
    duFrames   # timeline frames

  # Represents a full-sized action. Animatable scalar effects hold a list of
  # keyframes (one value = static, several = a ramp interpolated across the
  # section) plus an optional easing curve + duration packed inline.
  Action* = object
    case kind*: ActionKind
    of actInvert, actHflip, actVflip, actLoop, actErosion:
      discard
    of actRotate:
      rStart*: Unorm16       # circular [0, 360) static angle (expands the canvas)
    of actSpin:
      sStart*: Unorm16       # circular [0, 360) start angle
      sRate*: float32        # spin rate in degrees/second (continuous)
    of actLens:
      k1*, k2*: Snorm16
    of actSpeed, actVarispeed, actVolume:
      val*: float32
    of actZoom, actBlur, actOpacity, actBrightness:
      kf*: seq[float32]      # keyframes in native units; len >= 1
      hasEase*: bool
      easeCurve*: Easing
      easeDurUnit*: DurUnit
      easeDur*: float32      # magnitude in easeDurUnit (ignored for duClip)
    of actDeesser:
      intensity*, maxd*, freq*: Unorm16
    of actLuv:
      contrast*: float32
      saturation*: float32
      brighthue*: Snorm16
    of actDrawbox:
      dbX*, dbY*, dbW*, dbH*: int32   # rectangle in pixels (x, y, width, height)
      dbColor*: RGBColor              # outline color (RGB only)
    of actPos:
      px*, py*: int32        # overlay top-left in canvas pixels
      pscale*: float32       # overlay size multiplier (1.0 = native)
    of actColorKey, actChromaKey:
      color*: RGBColor
      similar*, blend*: Unorm16
    of actChoke:
      chokeN*: uint8         # matte-erosion passes (px to shrink the alpha matte)

  Actions* = distinct int # A fat pointer to a list of action in atf-8 format.

  # atf-8: store actions in as small a space as possible, inspirited by utf-8.

  ActionParseError* = object of CatchableError
  ActionFlag* = enum   # capabilities of an action
    afAudio,
    afVideo,
    afAnimatable       # value can be a keyframe ramp (`a..b..c`) with easing
  ActionFlags* = set[ActionFlag]

  RangeDoc* = object
    lo*, hi*: float
    loIncl*, hiIncl*: bool  # closed (inclusive) bounds
    each*: bool             # the interval applies to each positional arg
  ActionDef* = object
    name*: string
    flags*: ActionFlags
    argSpec*: string  # storage type ("float32") or positional spec ("k1[:k2]")
    range*: Option[RangeDoc]
    help*: string

const easeFlag = 0x80'u8  # high bit of an animated action's atf-8 header byte

func rng(lo, hi: float; loIncl = true, hiIncl = true, each = false): Option[RangeDoc] =
  some(RangeDoc(lo: lo, hi: hi, loIncl: loIncl, hiIncl: hiIncl, each: each))

func `$`*(r: RangeDoc): string =
  ## e.g. "(0.0, 99999.0)", "each [-1.0, 1.0]"
  (if r.each: "each " else: "") &
    (if r.loIncl: "[" else: "(") & $r.lo & ", " & $r.hi &
    (if r.hiIncl: "]" else: ")")

func `$`*(f: ActionFlags): string =
  if afAudio in f: result &= "A"
  if afVideo in f: result &= "V"
  if afAnimatable in f: result &= "*"

const actionDefs*: seq[ActionDef] = @[
  ActionDef(name: "nil", flags: {afAudio, afVideo},
    help: "Do nothing. Keep the section unchanged at normal speed and pitch."),
  ActionDef(name: "cut", flags: {afAudio, afVideo},
    help: "Remove the section completely from the output."),
  ActionDef(name: "speed", flags: {afAudio, afVideo}, argSpec: "float32", range: rng(0.0, 99999.0, loIncl = false, hiIncl = false),
    help: "Change the playback speed while preserving pitch via time-stretching. 1.0 = unchanged, 2.0 = twice as fast, 0.5 = half speed."),
  ActionDef(name: "varispeed", flags: {afAudio, afVideo}, argSpec: "float32", range: rng(0.2, 100.0),
    help: "Change the playback speed by resampling, so pitch shifts along with it, like analog tape or vinyl. 1.0 = unchanged, 2.0 = twice as fast and an octave higher."),
  ActionDef(name: "ease", flags: {afAudio, afVideo}, argSpec: "curve[:duration]",
    help: """
Set the easing for the animated actions that follow it (until another `ease` overrides it); equivalent to adding `:ease=curve` to each. `curve` is one of `linear`, `in`, `out`, or `inout`.
The optional `duration` (e.g. `2sec` or a bare frame count) is how long the animation takes before holding at its end value; omitted, it spans the whole section. Example: `ease:inout,zoom:1..2`."""),
  ActionDef(name: "volume", flags: {afAudio}, argSpec: "float32",
    help: "Scale the audio volume by val. 1.0 = unchanged, 0.5 = half (-6 dB), 2.0 = double (+6 dB)."),
  ActionDef(name: "deesser", flags: {afAudio}, argSpec: "intensity[:max[:freq]]", range: rng(0.0, 1.0, each = true),
    help: """
Reduce harsh "s" and "sh" sibilance in the section. Implemented via ffmpeg's `deesser` filter.
Positional args: `intensity` sets how much to de-ess (0.0 = none, 1.0 = maximum), `max` caps the reduction (default 0.5), and `freq` sets the split frequency (default 0.5)."""),
  ActionDef(name: "invert", flags: {afVideo},
    help: "Invert every pixel in the section, producing a photo-negative."),
  ActionDef(name: "hflip", flags: {afVideo},
    help: "Flip the section horizontally, mirroring it left to right."),
  ActionDef(name: "vflip", flags: {afVideo},
    help: "Flip the section vertically, mirroring it top to bottom."),
  ActionDef(name: "erosion", flags: {afVideo},
    help: "Erode the picture by replacing each pixel with the darkest of its 3x3 neighborhood. Bright details shrink and dark regions grow, giving a gritty, eaten-away look. Implemented via ffmpeg's `erosion` filter."),
  ActionDef(name: "zoom", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(0.0, 100.0, loIncl = false),
    help: "Scale the picture about its center by val. 1.0 = no zoom, 2.0 = zoom in 2x, 0.5 = zoom out 2x. Animatable: accepts keyframes `a..b..c` interpolated across the section, optionally eased with `:ease=`."),
  ActionDef(name: "opacity", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(0.0, 1.0),
    help: "Blend the section against the background. 1.0 = fully opaque, 0.0 = fully transparent. Animatable: accepts keyframes `a..b..c`, optionally eased with `:ease=`."),
  ActionDef(name: "blur", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(0.0, 1024.0),
    help: "Gaussian-blur the picture by sigma = val. 0.0 = no blur; larger values blur more. Animatable: accepts keyframes `a..b..c`, optionally eased with `:ease=`."),
  ActionDef(name: "brightness", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(-1.0, 1.0),
    help: "Shift brightness by adding an equal offset to the R, G, and B channels. 0.0 = unchanged, positive brightens, negative darkens. Implemented via ffmpeg's `lutrgb` filter. Animatable: accepts keyframes `a..b..c`, optionally eased with `:ease=`."),
  ActionDef(name: "brighthue", flags: {afVideo}, argSpec: "snorm16", range: rng(-1.0, 1.0),
    help: "Shift luma by offsetting the Y channel. 0.0 = unchanged, positive brightens, negative darkens."),
  ActionDef(name: "contrast", flags: {afVideo}, argSpec: "float32", range: rng(-2.0, 2.0),
    help: "Scale contrast around mid-gray. 1.0 = unchanged, higher values increase contrast, lower values reduce it. Implemented via ffmpeg's `lutyuv` filter."),
  ActionDef(name: "saturation", flags: {afVideo}, argSpec: "float32", range: rng(0.0, 3.0),
    help: "Scale color saturation. 1.0 = unchanged, 0.0 = grayscale, higher values are more vivid. Implemented via ffmpeg's `lutyuv` filter."),
  ActionDef(name: "rotate", flags: {afVideo}, argSpec: "deg",
    help: "Rotate the picture clockwise about its center by a fixed `deg` angle, expanding the frame so nothing is clipped and filling the exposed corners with the background color. Good for aspect flips, e.g. `rotate:90`. For a continuous spin, use `spin` instead."),
  ActionDef(name: "spin", flags: {afVideo}, argSpec: "deg/rate",
    help: "Spin the picture continuously, starting at `deg` and turning at `rate` degrees per second (negative is counter-clockwise), e.g. `spin:0/120`. The picture spins within a constant square that contains every rotation (so it is never clipped); on an overlay the exposed corners are transparent, otherwise they are filled with the background color."),
  ActionDef(name: "drawbox", flags: {afVideo}, argSpec: "x:y:w:h:color",
    help: "Draw a filled rectangle onto the picture. Positional args: `x` and `y` are the top-left corner, `w` and `h` the width and height in pixels, and `color` an RGB color (a name like `red` or a hex value like `#ff0000`). Example: `drawbox:100:100:400:200:red`. Implemented via ffmpeg's `drawbox` filter."),
  ActionDef(name: "pos", flags: {afVideo}, argSpec: "x:y[:scale]",
    help: "Place this clip as an overlay when it is composited over a lower video track. `x` and `y` are the top-left corner in canvas pixels; the optional `scale` multiplies the source's native size (default 1.0). Has no effect on the base (bottom) track. Example: `pos:600:300:0.5`."),
  ActionDef(name: "lens", flags: {afVideo}, argSpec: "k1[:k2]", range: rng(-1.0, 1.0, each = true),
    help: """
Distort the picture like a camera lens. With no arguments, a fun fisheye is applied. Implemented via ffmpeg's `lenscorrection` filter.
Positional args: `k1` is the quadratic correction factor and `k2` the double-quadratic factor. Negative values bulge the image outward (fisheye); positive values pinch it inward (pincushion)."""),
  ActionDef(name: "colorkey", flags: {afVideo}, argSpec: "color[:similar:blend]", range: rng(0.0, 1.0),
    help: "Make a color transparent by matching it in RGB space. Best for flat, synthetic backgrounds (a logo's matte, a screen recording, a gif with one clean color); for real green-/blue-screen camera footage use `chromakey` instead. On the base (bottom) video track there is nothing to reveal, so the matched color is replaced with the timeline background (`-bg`) instead. Positional args: `color` is the key color (a name like `green` or a hex value), `similar` how close a pixel must be to be keyed (default 0.25), and `blend` how soft the edge is (default 0.0). Implemented via ffmpeg's `colorkey` filter."),
  ActionDef(name: "chromakey", flags: {afVideo}, argSpec: "color[:similar:blend]", range: rng(0.0, 1.0),
    help: "Make a color transparent by matching it in chroma (YUV) space, tolerating lighting variation, shadows, and soft edges. This is the green-/blue-screen keyer for real camera footage; for flat synthetic backgrounds use `colorkey` instead. On the base (bottom) video track there is nothing to reveal, so the matched color is replaced with the timeline background (`-bg`) instead. Positional args: `color` is the key color (a name like `green` or a hex value), `similar` how close a pixel must be to be keyed (default 0.25), and `blend` how soft the edge is (default 0.0). Implemented via ffmpeg's `chromakey` filter."),
  ActionDef(name: "choke", flags: {afVideo}, argSpec: "[n]", range: rng(1.0, 16.0),
    help: "Shrink (choke) the alpha matte left by a `colorkey`/`chromakey` inward by `n` pixels (default 1), cutting off the ring of key-color spill and ragged edge pixels around the subject. Must come after the key in the chain, e.g. `add:fg.mp4,chromakey:green,choke:2`. Only meaningful on overlay tracks (where keying produces alpha); a no-op on the base track. Implemented by eroding only the alpha plane via ffmpeg's `erosion` filter."),
  ActionDef(name: "loop", flags: {afVideo},
    help: "Loop the clip's source back to its start when it runs out of frames, instead of ending. Useful for overlays whose source (e.g. a short gif) is shorter than the section it covers, e.g. `add:logo.gif,loop`."),
]

# Effects whose value can be a keyframe ramp (the `afAnimatable` actions).
const animScalar* = block:
  var names: seq[string]
  for a in actionDefs:
    if afAnimatable in a.flags:
      names.add a.name
  names

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

proc parseKeyframes(spec: string): seq[float32] {.raises: [ActionParseError].} =
  ## "2" -> @[2]; "1..0.5..1" -> @[1, 0.5, 1] (keyframes spread across the section).
  for part in spec.split(".."):
    try:
      result.add parseFloat(part).float32
    except ValueError:
      raise newException(ActionParseError, "Invalid float value:" & part)

func sampleKf*(kf: seq[float32], p: float32): float32 =
  ## Piecewise-linear sample of keyframes at progress p in [0, 1].
  if kf.len <= 1:
    return (if kf.len == 1: kf[0] else: 0.0'f32)
  let x = clamp(p, 0.0'f32, 1.0'f32) * float32(kf.len - 1)
  let seg = min(int(x), kf.len - 2)
  kf[seg] + (kf[seg + 1] - kf[seg]) * (x - float32(seg))

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
  if val == "loop":
    return Action(kind: actLoop)
  if val == "erosion":
    return Action(kind: actErosion)

  let parts = val.split(":")

  # deesser takes positional args: intensity[:max[:freq]]
  if parts.len >= 2 and parts.len <= 4 and parts[0] == "deesser":
    var vals = [toUnorm16(0.0), halfUnorm16, halfUnorm16]
    for idx in 1 ..< parts.len:
      vals[idx - 1] = (
        try:
          toUnorm16(parseFloat(parts[idx]).float32)
        except ValueError:
          raise newException(ActionParseError, "Invalid float value:" & parts[idx])
      )
    return Action(kind: actDeesser, intensity: vals[0], maxd: vals[1], freq: vals[2])

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
          raise newException(ActionParseError, "Invalid float value: " & parts[idx])
      )
    for v in k:
      if v < -1.0 or v > 1.0:
        raise newException(ActionParseError, "lens factors must be in [-1.0, 1.0]")
    return Action(kind: actLens, k1: toSnorm16(k[0]), k2: toSnorm16(k[1]))

  # rotate: a fixed angle "rotate:deg" (static, expands the canvas).
  if parts[0] == "rotate" and parts.len == 2:
    if '/' in parts[1]:
      raise newException(ActionParseError,
        "rotate takes a fixed angle (rotate:deg); use spin:deg/rate for a continuous spin")
    try:
      return Action(kind: actRotate, rStart: Unorm16(rotCode(parseFloat(parts[1]).float32)))
    except ValueError:
      raise newException(ActionParseError, "Invalid float value:" & parts[1])

  # spin: a continuous rotation "spin:deg/rate", starting at `deg` and turning
  # `rate` degrees/second.
  if parts[0] == "spin" and parts.len == 2:
    let spec = parts[1]
    let slash = spec.find('/')
    if slash < 0:
      raise newException(ActionParseError, "spin requires spin:deg/rate")
    try:
      return Action(kind: actSpin,
        sStart: Unorm16(rotCode(parseFloat(spec[0 ..< slash]).float32)),
        sRate: parseFloat(spec[slash + 1 .. ^1]).float32)
    except ValueError:
      raise newException(ActionParseError, "Invalid float value")

  # drawbox takes positional args: x:y:w:h:color (color is RGB only).
  if parts[0] == "drawbox":
    if parts.len != 6:
      raise newException(ActionParseError, "drawbox requires x:y:w:h:color")
    var coords: array[4, int32]
    for idx in 0 ..< 4:
      try:
        coords[idx] = int32(parseInt(parts[idx + 1]))
      except ValueError:
        raise newException(ActionParseError, "Invalid integer value")
    if coords[2] <= 0 or coords[3] <= 0:
      raise newException(ActionParseError, "drawbox width and height must be positive")
    let col = (
      try:
        parseColor(parts[5])
      except ValueError:
        raise newException(ActionParseError, "Invalid color: " & parts[5])
    )
    return Action(kind: actDrawbox, dbX: coords[0], dbY: coords[1],
      dbW: coords[2], dbH: coords[3], dbColor: col)

  if parts[0] in ["colorkey", "chromakey"]:
    if parts.len < 2 or parts.len > 4:
      raise newException(ActionParseError, parts[0] & " requires color[:similar:blend]")
    let col = (
      try:
        parseColor(parts[1])
      except ValueError:
        raise newException(ActionParseError, "Invalid color: " & parts[1])
    )
    var vals = [toUnorm16(0.25'f32), toUnorm16(0.0'f32)]
    for idx in 2 ..< parts.len:
      vals[idx - 2] = (
        try:
          toUnorm16(parseFloat(parts[idx]).float32)
        except ValueError:
          raise newException(ActionParseError, "Invalid float value:" & parts[idx])
      )
    if vals[0] < toUnorm16(0.01'f32):
      vals[0] = toUnorm16(0.01'f32)

    if parts[0] == "colorkey":
      return Action(kind: actColorKey, color: col, similar: vals[0], blend: vals[1])
    return Action(kind: actChromaKey, color: col, similar: vals[0], blend: vals[1])

  # choke: shrink the alpha matte inward by `n` pixels (default 1).
  if parts[0] == "choke" and parts.len <= 2:
    if parts.len == 1:
      return Action(kind: actChoke, chokeN: 1)
    let n = (
      try:
        parseInt(parts[1])
      except ValueError:
        raise newException(ActionParseError, "Invalid integer value: " & parts[1])
    )
    if n < 1 or n > 16:
      raise newException(ActionParseError, "choke must be in [1, 16]")
    return Action(kind: actChoke, chokeN: uint8(n))

  # pos: overlay placement "pos:x:y" or "pos:x:y:scale".
  if parts[0] == "pos" and parts.len in {3, 4}:
    try:
      let scale = (if parts.len == 4: parseFloat(parts[3]).float32 else: 1.0'f32)
      if scale <= 0.0'f32:
        raise newException(ActionParseError, "pos scale must be greater than 0.0")
      return Action(kind: actPos, px: int32(parseInt(parts[1])),
        py: int32(parseInt(parts[2])), pscale: scale)
    except ValueError:
      raise newException(ActionParseError, "Invalid pos value")

  # Animatable scalar effects: a value or keyframe ramp, with optional easing:
  #   zoom:2   zoom:1..2   zoom:1..0.5..1   zoom:1..2:ease=inout:2sec
  if parts[0] in animScalar and parts.len >= 2:
    let kf = parseKeyframes(parts[1])
    case parts[0]
    of "zoom":
      for v in kf:
        if v <= 0.0:
          raise newException(ActionParseError, "zoom value must be greater than 0.0")
    of "opacity":
      for v in kf:
        if v < 0.0 or v > 1.0:
          raise newException(ActionParseError, "opacity must be in [0.0, 1.0]")
    of "brightness":
      for v in kf:
        if v < -1.0 or v > 1.0:
          raise newException(ActionParseError, "brightness must be in [-1.0, 1.0]")
    else: discard  # blur: any value

    var hasE = false
    var curve = easeLinear
    var unit = duClip
    var dur = 0.0'f32
    if parts.len >= 3:
      if not parts[2].startsWith("ease=") or parts.len > 4:
        raise newException(ActionParseError, "Unknown action: " & val)
      hasE = true
      curve = parseEasing(parts[2])
      if parts.len == 4:
        (dur, unit) = parseDuration(parts[3])

    case parts[0]
    of "zoom":
      return Action(kind: actZoom, kf: kf, hasEase: hasE, easeCurve: curve,
        easeDurUnit: unit, easeDur: dur)
    of "blur":
      return Action(kind: actBlur, kf: kf, hasEase: hasE, easeCurve: curve,
        easeDurUnit: unit, easeDur: dur)
    of "opacity":
      return Action(kind: actOpacity, kf: kf, hasEase: hasE, easeCurve: curve,
        easeDurUnit: unit, easeDur: dur)
    else:
      return Action(kind: actBrightness, kf: kf, hasEase: hasE, easeCurve: curve,
        easeDurUnit: unit, easeDur: dur)

  if parts.len == 2:
    let effectType = parts[0]
    let effectVal = (
      try:
        parseFloat(parts[1]).float32
      except ValueError:
        raise newException(ActionParseError, "Invalid float value: " & parts[1])
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

func easeSuffix(a: Action): string =
  ## The trailing ":ease=..." for an animated action, or "" if it has none.
  if not a.hasEase: return ""
  result = ":ease=" & easeName(a.easeCurve)
  case a.easeDurUnit
  of duClip: discard
  of duSec: result &= ":" & $a.easeDur & "sec"
  of duFrames: result &= ":" & $a.easeDur

func kfStr(a: Action): string =
  ## Keyframes as "a..b..c", formatted in each effect's native value type.
  var parts: seq[string]
  for v in a.kf:
    case a.kind
    of actOpacity: parts.add $toUnorm16(v)
    of actBrightness: parts.add $toSnorm16(v)
    else: parts.add $v
  parts.join("..")

when not defined(nimscript):
  func `$`*(act: Action): string =
    case act.kind
    of actInvert: "invert"
    of actHflip: "hflip"
    of actVflip: "vflip"
    of actLoop: "loop"
    of actErosion: "erosion"
    of actSpeed: "speed:" & $act.val
    of actVarispeed: "varispeed:" & $act.val
    of actVolume: "volume:" & $act.val
    of actDeesser:
      let i = act.intensity
      let m = act.maxd
      let f = act.freq
      "deesser:" & $i & ":" & $m & ":" & $f
    of actZoom: "zoom:" & kfStr(act) & easeSuffix(act)
    of actOpacity: "opacity:" & kfStr(act) & easeSuffix(act)
    of actBlur: "blur:" & kfStr(act) & easeSuffix(act)
    of actBrightness: "brightness:" & kfStr(act) & easeSuffix(act)
    of actRotate: "rotate:" & $rotDeg(act.rStart)
    of actSpin: "spin:" & $rotDeg(act.sStart) & "/" & $act.sRate
    of actLuv:
      var parts: seq[string]
      if act.brighthue != luvBrighthueId: parts.add "brighthue:" & $act.brighthue
      if act.contrast != luvContrastId: parts.add "contrast:" & $act.contrast
      if act.saturation != luvSaturationId: parts.add "saturation:" & $act.saturation
      if parts.len == 0: "brighthue:0.0" else: parts.join(",")
    of actLens: "lens:" & $act.k1 & ":" & $act.k2
    of actDrawbox:
      "drawbox:" & $act.dbX & ":" & $act.dbY & ":" & $act.dbW & ":" &
        $act.dbH & ":" & act.dbColor.toString
    of actPos: "pos:" & $act.px & ":" & $act.py & ":" & $act.pscale
    of actColorKey: "colorkey:" & act.color.toString & ":" & $act.similar & ":" & $act.blend
    of actChromaKey: "chromakey:" & act.color.toString & ":" & $act.similar & ":" & $act.blend
    of actChoke: "choke:" & $int(act.chokeN)

  func easeBytes(a: Action): int = (if a.hasEase: 6 else: 0)

  func actionByteSize(a: Action): int =
    case a.kind
    of actInvert, actHflip, actVflip, actLoop, actErosion: 1
    of actRotate: 3
    of actLens, actSpeed, actVarispeed, actVolume: 5
    of actDeesser, actSpin: 7
    of actChoke: 2
    of actColorKey, actChromaKey: 8
    of actLuv: 11
    of actPos: 13
    of actDrawbox: 20
    of actBrightness, actOpacity: 2 + easeBytes(a) + a.kf.len * 2
    of actBlur, actZoom: 2 + easeBytes(a) + a.kf.len * 4

  func len*(a: Actions): int =  # byte length
    if int(a) <= 1: 0
    else: int(cast[ptr uint16](int(a))[])

  func firstIsLoop*(a: Actions): bool =
    ## True if the action list begins with `loop`. `parseActions` canonicalizes
    ## `loop` to a single token at the front, so this O(1) header read replaces
    ## scanning a clip's effects for actLoop on every frame.
    if a.len == 0: return false
    let base = cast[ptr UncheckedArray[uint8]](int(a) + sizeof(uint16))
    (base[0] and 0x7f'u8).int == ord(actLoop)

  iterator items*(a: Actions): Action =
    if int(a) > 1:
      let n = a.len
      let base = cast[ptr UncheckedArray[uint8]](int(a) + sizeof(uint16))
      var i = 0
      while i < n:
        let kind = ActionKind((base[i] and 0x7f'u8).int)
        case kind
        of actInvert, actHflip, actVflip, actLoop, actErosion:
          yield Action(kind: kind)
          i += 1
        of actRotate:
          var st: Unorm16
          copyMem(addr st, addr base[i + 1], sizeof(Unorm16))
          yield Action(kind: actRotate, rStart: st)
          i += 3
        of actLens:
          var k1v, k2v: Snorm16
          copyMem(addr k1v, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr k2v, addr base[i + 3], sizeof(Snorm16))
          yield Action(kind: actLens, k1: k1v, k2: k2v)
          i += 5
        of actSpeed, actVarispeed, actVolume:
          var v: float32
          copyMem(addr v, addr base[i + 1], sizeof(float32))
          yield Action(kind: kind, val: v)
          i += 5
        of actDeesser:
          var iu, mu, fu: Unorm16
          copyMem(addr iu, addr base[i + 1], sizeof(Unorm16))
          copyMem(addr mu, addr base[i + 3], sizeof(Unorm16))
          copyMem(addr fu, addr base[i + 5], sizeof(Unorm16))
          yield Action(kind: actDeesser, intensity: iu, maxd: mu, freq: fu)
          i += 7
        of actSpin:
          var st: Unorm16
          var rate: float32
          copyMem(addr st, addr base[i + 1], sizeof(Unorm16))
          copyMem(addr rate, addr base[i + 3], sizeof(float32))
          yield Action(kind: actSpin, sStart: st, sRate: rate)
          i += 7
        of actColorKey, actChromaKey:
          var col: RGBColor
          var sim, blend: Unorm16
          copyMem(addr col, addr base[i + 1], sizeof(RGBColor))
          copyMem(addr sim, addr base[i + 4], sizeof(Unorm16))
          copyMem(addr blend, addr base[i + 6], sizeof(Unorm16))
          yield Action(kind: kind, color: col, similar: sim, blend: blend)
          i += 8
        of actChoke:
          yield Action(kind: actChoke, chokeN: base[i + 1])
          i += 2
        of actLuv:
          var bh: Snorm16
          var c, s: float32
          copyMem(addr bh, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr c, addr base[i + 3], sizeof(float32))
          copyMem(addr s, addr base[i + 7], sizeof(float32))
          yield Action(kind: actLuv, brighthue: bh, contrast: c, saturation: s)
          i += 11
        of actPos:
          var x, y: int32
          var sc: float32
          copyMem(addr x, addr base[i + 1], sizeof(int32))
          copyMem(addr y, addr base[i + 5], sizeof(int32))
          copyMem(addr sc, addr base[i + 9], sizeof(float32))
          yield Action(kind: actPos, px: x, py: y, pscale: sc)
          i += 13
        of actDrawbox:
          var x, y, w, h: int32
          copyMem(addr x, addr base[i + 1], sizeof(int32))
          copyMem(addr y, addr base[i + 5], sizeof(int32))
          copyMem(addr w, addr base[i + 9], sizeof(int32))
          copyMem(addr h, addr base[i + 13], sizeof(int32))
          let col = RGBColor(red: base[i + 17], green: base[i + 18], blue: base[i + 19])
          yield Action(kind: actDrawbox, dbX: x, dbY: y, dbW: w, dbH: h, dbColor: col)
          i += 20
        of actZoom, actBlur, actOpacity, actBrightness:
          let hasEase = (base[i] and easeFlag) != 0'u8
          var pos = i + 1
          var act = Action(kind: kind)
          act.hasEase = hasEase
          if hasEase:
            act.easeCurve = Easing(base[pos].int)
            act.easeDurUnit = DurUnit(base[pos + 1].int)
            copyMem(addr act.easeDur, addr base[pos + 2], sizeof(float32))
            pos += 6
          let count = base[pos].int
          pos += 1
          act.kf = newSeq[float32](count)
          for c in 0 ..< count:
            if kind in {actZoom, actBlur}:
              var v: float32
              copyMem(addr v, addr base[pos], sizeof(float32))
              act.kf[c] = v
              pos += 4
            elif kind == actOpacity:
              var u: Unorm16
              copyMem(addr u, addr base[pos], sizeof(Unorm16))
              act.kf[c] = u.toFloat32
              pos += 2
            else:
              var s: Snorm16
              copyMem(addr s, addr base[pos], sizeof(Snorm16))
              act.kf[c] = s.toFloat32
              pos += 2
          yield act
          i = pos

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
    for a in list: total += actionByteSize(a)
    if total > 65535:
      raise newException(ActionParseError, "atf-8 buffer overflow: too many actions")
    let p = alloc(sizeof(uint16) + total)
    cast[ptr uint16](p)[] = uint16(total)
    let base = cast[ptr UncheckedArray[uint8]](cast[int](p) + sizeof(uint16))
    var i = 0
    for a in list:
      base[i] = uint8(ord(a.kind))
      case a.kind
      of actInvert, actHflip, actVflip, actLoop, actErosion:
        i += 1
      of actRotate:
        base.writeAt(i, 1, a.rStart)
        i += 3
      of actLens:
        base.writeAt(i, 1, a.k1)
        base.writeAt(i, 3, a.k2)
        i += 5
      of actSpeed, actVarispeed, actVolume:
        base.writeAt(i, 1, a.val)
        i += 5
      of actDeesser:
        base.writeAt(i, 1, a.intensity)
        base.writeAt(i, 3, a.maxd)
        base.writeAt(i, 5, a.freq)
        i += 7
      of actSpin:
        base.writeAt(i, 1, a.sStart)
        base.writeAt(i, 3, a.sRate)
        i += 7
      of actColorKey, actChromaKey:
        base.writeAt(i, 1, a.color)
        base.writeAt(i, 4, a.similar)
        base.writeAt(i, 6, a.blend)
        i += 8
      of actChoke:
        base[i + 1] = a.chokeN
        i += 2
      of actLuv:
        base.writeAt(i, 1, a.brighthue)
        base.writeAt(i, 3, a.contrast)
        base.writeAt(i, 7, a.saturation)
        i += 11
      of actPos:
        base.writeAt(i, 1, a.px)
        base.writeAt(i, 5, a.py)
        base.writeAt(i, 9, a.pscale)
        i += 13
      of actDrawbox:
        base.writeAt(i, 1, a.dbX)
        base.writeAt(i, 5, a.dbY)
        base.writeAt(i, 9, a.dbW)
        base.writeAt(i, 13, a.dbH)
        base.writeAt(i, 17, a.dbColor)
        i += 20
      of actZoom, actBlur, actOpacity, actBrightness:
        if a.hasEase: base[i] = base[i] or easeFlag
        var pos = i + 1
        if a.hasEase:
          base[pos] = uint8(ord(a.easeCurve))
          base[pos + 1] = uint8(ord(a.easeDurUnit))
          var d = a.easeDur
          copyMem(addr base[pos + 2], addr d, sizeof(float32))
          pos += 6
        base[pos] = uint8(a.kf.len)
        pos += 1
        for v in a.kf:
          if a.kind in {actZoom, actBlur}:
            var vv = v
            copyMem(addr base[pos], addr vv, sizeof(float32))
            pos += 4
          elif a.kind == actOpacity:
            var u = toUnorm16(v)
            copyMem(addr base[pos], addr u, sizeof(Unorm16))
            pos += 2
          else:
            var s = toSnorm16(v)
            copyMem(addr base[pos], addr s, sizeof(Snorm16))
            pos += 2
        i = pos

    Actions(cast[int](p))

  proc parseActions*(val: string): Actions =
    var list: seq[Action]
    # An `ease:` token sets a pending envelope that is stamped onto the animated
    # actions that follow it (until another `ease` overrides it).
    var pendActive = false
    var pendCurve = easeLinear
    var pendUnit = duClip
    var pendDur = 0.0'f32
    for part in val.strip().split(","):
      let trimmedPart = part.strip()
      if trimmedPart == "nil":
        continue
      if trimmedPart == "cut":
        return aCut

      let segs = trimmedPart.split(":")
      if segs[0] == "ease" and segs.len in {2, 3}:
        pendActive = true
        pendCurve = parseEasing(segs[1])
        if segs.len == 3:
          (pendDur, pendUnit) = parseDuration(segs[2])
        else:
          pendUnit = duClip
          pendDur = 0.0'f32
        continue

      var action = parseAction(trimmedPart)
      if pendActive and action.kind in {actZoom, actBlur, actOpacity, actBrightness} and
          not action.hasEase:
        action.hasEase = true
        action.easeCurve = pendCurve
        action.easeDurUnit = pendUnit
        action.easeDur = pendDur
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

    # Drop any all-identity actLuv (no-op), and canonicalize `loop`: it's a
    # per-clip flag, not an ordered effect, so any number of `loop` tokens
    # collapse into a single one at the front. This lets `firstIsLoop` answer in
    # O(1) instead of rescanning a clip's effects for actLoop every frame.
    var pruned: seq[Action]
    var hasLoop = false
    for a in list:
      if a.kind == actLuv and a.brighthue == luvBrighthueId and
          a.contrast == luvContrastId and a.saturation == luvSaturationId:
        continue
      if a.kind == actLoop:
        hasLoop = true
        continue
      pruned.add a
    if hasLoop:
      pruned.insert(Action(kind: actLoop), 0)
    return newActions(pruned)

  func `$`*(a: Actions): string =
    if a.isCut: return "cut"
    if a.isEmpty: return "nil"
    var parts: seq[string]
    for action in a: parts.add $action
    parts.join(",")
