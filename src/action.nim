import std/[math, strutils, options]
import ./util/[dnorm16, color]

template writeAt(baseBuffer: auto, index: int, offset: int, val: untyped) =
  var temp = val
  copyMem(addr baseBuffer[index + offset], addr temp, sizeof(temp))

type
  # The order is part of the API
  ActionKind* = enum
    actSpeed, actVarispeed,
    # Can add 2 more [VA] actions
    actVolume = 4,
    actDeesser, actDuck,
    # Can add 13 more [A] actions
    actInvert = 20,
    actHflip, actVflip, actZoom, actOpacity, actBlur, actBrightness, actLuv, actLens,
    actRotate, actSpin, actDrawbox, actPos, actColorKey, actChromaKey, actLoop,
    actErosion, actChoke, actAberration, actMask, actConfine
    # Can add 87 more [V] actions

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
    # Easing envelope shared by every animatable action (zoom/blur/opacity/
    # brightness/volume/pos). Defaults (off, linear, whole-clip) make a static
    # action sample trivially, so non-animated actions just ignore these.
    hasEase*: bool
    easeCurve*: Easing
    easeDurUnit*: DurUnit
    easeDur*: float32        # magnitude in easeDurUnit (ignored for duClip)
    case kind*: ActionKind
    of actInvert, actHflip, actVflip, actLoop, actErosion:
      discard
    of actChoke:
      chokeN*: uint8         # matte-erosion passes (px to shrink the alpha matte)
    of actRotate:
      rStart*: Unorm16       # circular [0, 360) static angle (expands the canvas)
    of actSpin:
      sStart*: Unorm16       # circular [0, 360) start angle
      sRate*: float32        # spin rate in degrees/second (continuous)
    of actLens:
      k1*, k2*: Snorm16
    of actSpeed, actVarispeed:
      val*: float32
    of actZoom, actBlur, actOpacity, actBrightness, actVolume:
      kf*: seq[float32]      # keyframes in native units; len >= 1
    of actDeesser:
      intensity*, maxd*, freq*: Unorm16
    of actDuck:
      # Cross-track sidechain: rendered at the mix stage, not in the clip chain.
      duckAmount*, duckThresh*: Unorm16  # 0..1; gain floor = 1 - amount
      duckAttack*, duckRelease*: uint16  # milliseconds
    of actLuv:
      contrast*: float32
      saturation*: float32
      brighthue*: Snorm16
    of actDrawbox:
      dbX*, dbY*, dbW*, dbH*: int32   # rectangle in pixels (x, y, width, height)
      dbColor*: RGBColor              # outline color (RGB only)
    of actPos:
      # Overlay placement ramps: top-left x/y in canvas px and a size multiplier
      # (1.0 = native). Each is a keyframe seq (len 1 = static) like the scalars.
      pxKf*, pyKf*, pscaleKf*: seq[float32]
    of actColorKey, actChromaKey:
      color*: RGBColor
      similar*, blend*: Unorm16
    of actAberration:
      abRh*, abRv*, abGh*, abGv*, abBh*, abBv*: int8
      abWrap*: bool          # edge: wrap around (true) vs smear the border (false)
    of actMask, actConfine:
      # `mask` shapes the clip's alpha; `confine` restricts following effects to
      # this region. Shared geometry, in canvas pixels like drawbox.
      mRadius*: int32        # corner radius px: 0=rect, >0=rounded rect, -1=ellipse
      mReset*: bool          # confine bare: reset to full frame (region fields unused)
      mInvert*: bool         # swap inside/outside
      mFeather*: uint8       # soft-edge width in px (0 = hard edge)
      mX*, mY*, mW*, mH*: int32

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
  ActionDef(name: "volume", flags: {afAudio, afAnimatable}, argSpec: "v[..v...]",
    help: "Scale the audio volume by val. 1.0 = unchanged, 0.5 = half (-6 dB), 2.0 = double (+6 dB). Animatable: accepts keyframes `a..b..c` interpolated across the section, optionally eased with `:ease=`."),
  ActionDef(name: "deesser", flags: {afAudio}, argSpec: "intensity[:max[:freq]]", range: rng(0.0, 1.0, each = true),
    help: """
Reduce harsh "s" and "sh" sibilance in the section. Implemented via ffmpeg's `deesser` filter.
Positional args: `intensity` sets how much to de-ess (0.0 = none, 1.0 = maximum), `max` caps the reduction (default 0.5), and `freq` sets the split frequency (default 0.5)."""),
  ActionDef(name: "duck", flags: {afAudio}, argSpec: "[amount[:threshold[:attack[:release]]]]",
    help: """
Autoduck (sidechain): lower this clip's audio wherever the louder audio layers beneath it (higher track indices) are active, e.g. tuck a music/desktop track under a voice track. Cross-track, so it is applied when the audio layers are mixed; a no-op on the bottom-most layer and on single-layer audio.
Positional args: `amount` is the maximum attenuation (0.0 = none, 1.0 = duck to silence, default 0.85), `threshold` the key loudness 0.0..1.0 that engages the duck (default 0.04), and `attack`/`release` the duck-down/recover times in milliseconds (defaults 100 and 500)."""),
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
  ActionDef(name: "pos", flags: {afVideo, afAnimatable}, argSpec: "x:y[:scale]",
    help: "Place this clip as an overlay when it is composited over a lower video track. `x` and `y` are the top-left corner in canvas pixels; the optional `scale` multiplies the source's native size (default 1.0). Has no effect on the base (bottom) track. Example: `pos:600:300:0.5`. Animatable: each of `x`, `y`, and `scale` accepts a keyframe ramp `a..b..c` interpolated across the section, optionally eased with `:ease=`, e.g. `pos:0..600:300:1..0.5:ease=inout` slides the overlay across while shrinking it."),
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
  ActionDef(name: "aberration", flags: {afVideo}, argSpec: "[h[:v[:edge]]]", range: rng(-127.0, 127.0, each = true),
    help: """
Fake chromatic aberration by shifting the color channels apart, leaving red/cyan fringing for a cheap-lens or glitch look. Implemented via ffmpeg's `rgbashift` filter.
Simple form `aberration[:h[:v[:edge]]]`: split red and blue symmetrically by `h` pixels horizontally (default 5) and `v` pixels vertically (default 0), with green left in place. `edge` is `smear` (extend the border pixel, the default) or `wrap` (wrap around to the far side).
Per-channel form: pass `key=value` pairs drawn from `rh`, `rv`, `gh`, `gv`, `bh`, `bv` (signed pixel shift for each channel/axis, default 0) plus `edge`, e.g. `aberration:rh=8:bh=-8:gv=2:edge=wrap`."""),
  ActionDef(name: "loop", flags: {afVideo},
    help: "Loop the clip's source back to its start when it runs out of frames, instead of ending. Useful for overlays whose source (e.g. a short gif) is shorter than the section it covers, e.g. `add:logo.gif,loop`."),
  ActionDef(name: "mask", flags: {afVideo}, argSpec: "x:y:w:h[:radius][:feather][:invert]",
    help: "Cut the picture to a rounded-rectangle or ellipse, making everything outside the shape transparent. `x`/`y` are the top-left corner and `w`/`h` the size in pixels. `radius` is the corner radius in pixels: `0` (the default) is a sharp rectangle, a positive value rounds the corners, and `-1` is a true ellipse (the `w`x`h` box's inscribed oval). The optional `feather` softens the edge by that many pixels (0 = hard, the default); append `:invert` to hide the inside instead. Every field also takes a keyword form (`x=`, `y=`, `w=`, `h=`, `radius=`/`r=`, `feather=`), so positional and keyword args can be mixed. On the base (bottom) track there is nothing to reveal, so the masked-out area is filled with the timeline background (`-bg`) instead; on an overlay it reveals the track below. Good for circular/rounded picture-in-picture, vignettes, and crop-to-shape. Example: `add:cam.mp4,pos:900:540:0.3,mask:640:360:300:300:-1:40`."),
  ActionDef(name: "confine", flags: {afVideo}, argSpec: "[x:y:w:h[:radius][:feather][:invert]]",
    help: "Restrict the adjustment effects that follow it (`blur`, `brightness`, `brighthue`, `contrast`, `saturation`, `invert`, `erosion`, `aberration`) to a rounded-rectangle or ellipse region, leaving the rest of the picture untouched. Stays in effect until the next `confine` changes the region; a bare `confine` with no arguments resets to the full frame. `x`/`y`/`w`/`h` are in pixels; `radius` is the corner radius (`0` sharp rectangle, positive rounds the corners, `-1` a true ellipse); the optional `feather` fades the effect in over that many edge pixels, and `:invert` affects everything outside the region instead. Every field also takes a keyword form (`x=`, `radius=`/`r=`, `feather=`, ...). Geometry effects (zoom, rotate, pos, ...) are unaffected. Example: `confine:400:300:200:80,blur:30` blurs only the box, e.g. to censor a face or plate."),
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

func clipT*(local, animLen: int): float32 =
  ## Normalized time over an animation of `animLen` steps (frames or samples),
  ## reaching 1.0 on the last step and holding there once the animation
  ## completes.
  let l = min(local, max(animLen - 1, 0))
  float32(l) / float32(max(animLen - 1, 1))

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

proc parseKeyframes*(spec: string): seq[float32] {.raises: [ActionParseError].} =
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

proc parseShapeRegion(parts: seq[string], kind: ActionKind,
    name: string): Action {.raises: [ActionParseError].} =
  ## Shared `x:y:w:h[:radius][:feather][:invert]` geometry for `mask`/`confine`.
  ## Fields take positional or `key=value` form (freely mixed); `invert` is a
  ## bare flag. radius: 0 = rect, >0 = rounded-rect corner px, -1 = ellipse.
  const slots = ["x", "y", "w", "h", "radius", "feather"]  # positional order
  var vals: array[6, int]            # x, y, w, h, radius, feather
  var seen: array[6, bool]
  var inv = false
  var nextPos = 0                    # next unfilled positional slot

  proc slotOf(key: string): int =
    case key
    of "x": 0
    of "y": 1
    of "w", "width": 2
    of "h", "height": 3
    of "radius", "r": 4
    of "feather": 5
    else: -1

  proc setSlot(i: int, raw, ctx: string) {.raises: [ActionParseError].} =
    try:
      vals[i] = parseInt(raw)
    except ValueError:
      raise newException(ActionParseError, name & ": invalid integer: " & ctx)
    seen[i] = true

  for idx in 1 ..< parts.len:
    let p = parts[idx]
    let eq = p.find('=')
    if p == "invert":
      inv = true
    elif eq >= 0:
      let key = p[0 ..< eq]
      let s = slotOf(key)
      if s < 0:
        raise newException(ActionParseError, name & ": unknown key: " & key)
      setSlot(s, p[eq + 1 .. ^1], p)
    else:
      while nextPos < slots.len and seen[nextPos]: inc nextPos
      if nextPos >= slots.len:
        raise newException(ActionParseError, name & ": too many values: " & p)
      setSlot(nextPos, p, p)

  for i in 0 ..< 4:
    if not seen[i]:
      raise newException(ActionParseError, name & " requires " & slots[i])
  if vals[2] <= 0 or vals[3] <= 0:
    raise newException(ActionParseError, name & " width and height must be positive")
  if vals[4] < -1:
    raise newException(ActionParseError, name & " radius must be -1 (ellipse) or >= 0")
  if vals[5] < 0 or vals[5] > 255:
    raise newException(ActionParseError, name & " feather must be in [0, 255]")

  result = Action(kind: kind)  # branch fields assigned after (shared by both kinds)
  result.mX = int32(vals[0])
  result.mY = int32(vals[1])
  result.mW = int32(vals[2])
  result.mH = int32(vals[3])
  result.mRadius = int32(vals[4])
  result.mFeather = uint8(vals[5])
  result.mInvert = inv

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
  if val == "confine":  # bare = reset to full frame
    return Action(kind: actConfine, mReset: true)

  let parts = val.split(":")

  if parts[0] == "mask":
    return parseShapeRegion(parts, actMask, "mask")
  if parts[0] == "confine":
    return parseShapeRegion(parts, actConfine, "confine")

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

  # duck takes positional args: [amount[:threshold[:attack[:release]]]]
  if parts[0] == "duck" and parts.len <= 5:
    var vals = [0.85'f32, 0.04'f32, 100.0'f32, 500.0'f32]
    for idx in 1 ..< parts.len:
      vals[idx - 1] = (
        try:
          parseFloat(parts[idx]).float32
        except ValueError:
          raise newException(ActionParseError, "Invalid float value:" & parts[idx])
      )
    if vals[0] < 0.0 or vals[0] > 1.0:
      raise newException(ActionParseError, "duck amount must be in [0.0, 1.0]")
    if vals[1] < 0.0 or vals[1] > 1.0:
      raise newException(ActionParseError, "duck threshold must be in [0.0, 1.0]")
    if vals[2] < 0.0 or vals[2] > 65535.0 or vals[3] < 0.0 or vals[3] > 65535.0:
      raise newException(ActionParseError, "duck attack/release must be in [0, 65535] ms")
    return Action(kind: actDuck, duckAmount: toUnorm16(vals[0]),
      duckThresh: toUnorm16(vals[1]), duckAttack: uint16(vals[2]),
      duckRelease: uint16(vals[3]))

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

  # aberration: per-channel chromatic split. Positional shorthand (no '=') is the
  # symmetric case `aberration[:h[:v[:edge]]]`; any `key=value` part switches to the
  # explicit per-channel form, which starts every channel at 0.
  if parts[0] == "aberration":
    template chk(n: int): int8 =
      if n < -127 or n > 127:
        raise newException(ActionParseError, "aberration shift must be in [-127, 127]")
      int8(n)
    proc toEdge(v: string): bool {.raises: [ActionParseError].} =
      case v
      of "smear": false
      of "wrap": true
      else: raise newException(ActionParseError, "aberration edge must be smear or wrap")
    var rh, rv, gh, gv, bh, bv = 0
    var wrap = false
    var keyword = false
    for idx in 1 ..< parts.len:
      if '=' in parts[idx]:
        keyword = true
        break

    if parts.len == 1:
      rh = 5; bh = -5
    elif not keyword:
      # Symmetric: up to two bare pixel counts (h, v) plus an optional edge token.
      var nums: seq[int]
      for idx in 1 ..< parts.len:
        let p = parts[idx]
        if p == "smear" or p == "wrap":
          wrap = toEdge(p)
        else:
          try:
            nums.add parseInt(p)
          except ValueError:
            raise newException(ActionParseError, "Invalid aberration value: " & p)
      if nums.len > 2:
        raise newException(ActionParseError, "aberration takes at most h:v positional shifts")
      let h = (if nums.len >= 1: nums[0] else: 5)
      let v = (if nums.len >= 2: nums[1] else: 0)
      rh = h; bh = -h; rv = v; bv = -v
    else:
      for idx in 1 ..< parts.len:
        let p = parts[idx]
        let eq = p.find('=')
        if eq < 0:
          raise newException(ActionParseError, "aberration: expected key=value, got " & p)
        let key = p[0 ..< eq]
        let value = p[eq + 1 .. ^1]
        if key == "edge":
          wrap = toEdge(value)
          continue
        let n = (
          try:
            parseInt(value)
          except ValueError:
            raise newException(ActionParseError, "Invalid aberration value: " & value)
        )
        case key
        of "rh": rh = n
        of "rv": rv = n
        of "gh": gh = n
        of "gv": gv = n
        of "bh": bh = n
        of "bv": bv = n
        else: raise newException(ActionParseError, "Unknown aberration key: " & key)
    return Action(kind: actAberration, abRh: chk(rh), abRv: chk(rv),
      abGh: chk(gh), abGv: chk(gv), abBh: chk(bh), abBv: chk(bv), abWrap: wrap)

  # pos: overlay placement, each field an animatable ramp:
  #   pos:x:y   pos:x:y:scale   pos:0..600:300:1..0.5:ease=inout
  if parts[0] == "pos":
    if parts.len < 3:
      raise newException(ActionParseError, "pos requires x:y[:scale]")
    let xKf = parseKeyframes(parts[1])
    let yKf = parseKeyframes(parts[2])
    # parts[3] is the scale ramp unless it's the ease suffix.
    var sKf = @[1.0'f32]
    var idx = 3
    if parts.len > 3 and not parts[3].startsWith("ease="):
      sKf = parseKeyframes(parts[3])
      idx = 4
    for v in sKf:
      if v <= 0.0'f32:
        raise newException(ActionParseError, "pos scale must be greater than 0.0")
    var hasE = false
    var curve = easeLinear
    var unit = duClip
    var dur = 0.0'f32
    if parts.len > idx:
      if not parts[idx].startsWith("ease=") or parts.len > idx + 2:
        raise newException(ActionParseError, "Unknown action: " & val)
      hasE = true
      curve = parseEasing(parts[idx])
      if parts.len == idx + 2:
        (dur, unit) = parseDuration(parts[idx + 1])
    return Action(kind: actPos, pxKf: xKf, pyKf: yKf, pscaleKf: sKf,
      hasEase: hasE, easeCurve: curve, easeDurUnit: unit, easeDur: dur)

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
    of "volume":
      return Action(kind: actVolume, kf: kf, hasEase: hasE, easeCurve: curve,
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
    of "speed", "varispeed":
      # `not (a and b)` instead of `<= or >=` so NaN fails the check too;
      # speed <= 0 makes the renderer's atempo decomposition loop forever.
      if not (effectVal > 0.0 and effectVal < 99999.0):
        raise newException(ActionParseError,
          effectType & " must be in range (0, 99999)")
      if effectType == "speed":
        return Action(kind: actSpeed, val: effectVal)
      return Action(kind: actVarispeed, val: effectVal)
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

func maskStr(a: Action, name: string): string =
  result = name & ":" & $a.mX & ":" & $a.mY & ":" & $a.mW & ":" & $a.mH
  # radius (0 = rect, default) only needs emitting when set or to hold feather's
  # positional slot; feather then follows so both round-trip positionally.
  if a.mRadius != 0 or a.mFeather > 0'u8: result &= ":" & $a.mRadius
  if a.mFeather > 0'u8: result &= ":" & $int(a.mFeather)
  if a.mInvert: result &= ":invert"

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
    of actVolume: "volume:" & kfStr(act) & easeSuffix(act)
    of actDeesser:
      let i = act.intensity
      let m = act.maxd
      let f = act.freq
      "deesser:" & $i & ":" & $m & ":" & $f
    of actDuck:
      "duck:" & $act.duckAmount & ":" & $act.duckThresh & ":" &
        $int(act.duckAttack) & ":" & $int(act.duckRelease)
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
    of actPos:
      var xs, ys, ss: seq[string]
      for v in act.pxKf: xs.add $int(round(v))   # x/y are whole pixels
      for v in act.pyKf: ys.add $int(round(v))
      for v in act.pscaleKf: ss.add $v
      "pos:" & xs.join("..") & ":" & ys.join("..") & ":" & ss.join("..") &
        easeSuffix(act)
    of actColorKey: "colorkey:" & act.color.toString & ":" & $act.similar & ":" & $act.blend
    of actChromaKey: "chromakey:" & act.color.toString & ":" & $act.similar & ":" & $act.blend
    of actChoke: "choke:" & $int(act.chokeN)
    of actAberration:
      # A symmetric, green-free, smear split round-trips as the positional shorthand.
      if not act.abWrap and act.abGh == 0 and act.abGv == 0 and
          act.abRh >= 0 and act.abBh == -act.abRh and act.abBv == -act.abRv:
        if act.abRv == 0: "aberration:" & $act.abRh
        else: "aberration:" & $act.abRh & ":" & $act.abRv
      else:
        var ps: seq[string]
        if act.abRh != 0: ps.add "rh=" & $act.abRh
        if act.abRv != 0: ps.add "rv=" & $act.abRv
        if act.abGh != 0: ps.add "gh=" & $act.abGh
        if act.abGv != 0: ps.add "gv=" & $act.abGv
        if act.abBh != 0: ps.add "bh=" & $act.abBh
        if act.abBv != 0: ps.add "bv=" & $act.abBv
        if act.abWrap: ps.add "edge=wrap"
        "aberration:" & ps.join(":")
    of actMask: maskStr(act, "mask")
    of actConfine:
      if act.mReset: "confine" else: maskStr(act, "confine")

  func easeBytes(a: Action): int = (if a.hasEase: 6 else: 0)

  func actionByteSize(a: Action): int =
    case a.kind
    of actInvert, actHflip, actVflip, actLoop, actErosion: 1
    of actChoke: 2
    of actRotate: 3
    of actLens, actSpeed, actVarispeed: 5
    of actDeesser, actSpin: 7
    of actDuck: 9
    of actColorKey, actChromaKey, actAberration: 8
    of actLuv: 11
    of actPos: 4 + easeBytes(a) + (a.pxKf.len + a.pyKf.len + a.pscaleKf.len) * 4
    of actDrawbox: 20
    of actBrightness, actOpacity: 2 + easeBytes(a) + a.kf.len * 2
    of actBlur, actZoom, actVolume: 2 + easeBytes(a) + a.kf.len * 4
    of actMask, actConfine: 23  # header + flags + feather + 5x int32 (x,y,w,h,radius)

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
        of actSpeed, actVarispeed:
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
        of actDuck:
          var amt, thr: Unorm16
          var atk, rel: uint16
          copyMem(addr amt, addr base[i + 1], sizeof(Unorm16))
          copyMem(addr thr, addr base[i + 3], sizeof(Unorm16))
          copyMem(addr atk, addr base[i + 5], sizeof(uint16))
          copyMem(addr rel, addr base[i + 7], sizeof(uint16))
          yield Action(kind: actDuck, duckAmount: amt, duckThresh: thr,
            duckAttack: atk, duckRelease: rel)
          i += 9
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
        of actMask, actConfine:
          let flags = base[i + 1]
          let feather = base[i + 2]
          var x, y, w, h, radius: int32
          copyMem(addr x, addr base[i + 3], sizeof(int32))
          copyMem(addr y, addr base[i + 7], sizeof(int32))
          copyMem(addr w, addr base[i + 11], sizeof(int32))
          copyMem(addr h, addr base[i + 15], sizeof(int32))
          copyMem(addr radius, addr base[i + 19], sizeof(int32))
          yield Action(kind: kind, mRadius: radius,
            mReset: (flags and 0x2'u8) != 0, mInvert: (flags and 0x1'u8) != 0,
            mFeather: feather, mX: x, mY: y, mW: w, mH: h)
          i += 23
        of actAberration:
          yield Action(kind: actAberration,
            abRh: cast[int8](base[i + 1]), abRv: cast[int8](base[i + 2]),
            abGh: cast[int8](base[i + 3]), abGv: cast[int8](base[i + 4]),
            abBh: cast[int8](base[i + 5]), abBv: cast[int8](base[i + 6]),
            abWrap: base[i + 7] != 0'u8)
          i += 8
        of actLuv:
          var bh: Snorm16
          var c, s: float32
          copyMem(addr bh, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr c, addr base[i + 3], sizeof(float32))
          copyMem(addr s, addr base[i + 7], sizeof(float32))
          yield Action(kind: actLuv, brighthue: bh, contrast: c, saturation: s)
          i += 11
        of actPos:
          let hasEase = (base[i] and easeFlag) != 0'u8
          var pos = i + 1
          var act = Action(kind: actPos, hasEase: hasEase)
          if hasEase:
            act.easeCurve = Easing(base[pos].int)
            act.easeDurUnit = DurUnit(base[pos + 1].int)
            copyMem(addr act.easeDur, addr base[pos + 2], sizeof(float32))
            pos += 6
          for which in 0 .. 2:  # x, y, scale keyframe seqs in order
            let count = base[pos].int
            pos += 1
            var s = newSeq[float32](count)
            for c in 0 ..< count:
              copyMem(addr s[c], addr base[pos], sizeof(float32))
              pos += 4
            case which
            of 0: act.pxKf = s
            of 1: act.pyKf = s
            else: act.pscaleKf = s
          yield act
          i = pos
        of actDrawbox:
          var x, y, w, h: int32
          copyMem(addr x, addr base[i + 1], sizeof(int32))
          copyMem(addr y, addr base[i + 5], sizeof(int32))
          copyMem(addr w, addr base[i + 9], sizeof(int32))
          copyMem(addr h, addr base[i + 13], sizeof(int32))
          let col = RGBColor(red: base[i + 17], green: base[i + 18], blue: base[i + 19])
          yield Action(kind: actDrawbox, dbX: x, dbY: y, dbW: w, dbH: h, dbColor: col)
          i += 20
        of actZoom, actBlur, actOpacity, actBrightness, actVolume:
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
            if kind in {actZoom, actBlur, actVolume}:
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
      of actSpeed, actVarispeed:
        base.writeAt(i, 1, a.val)
        i += 5
      of actDeesser:
        base.writeAt(i, 1, a.intensity)
        base.writeAt(i, 3, a.maxd)
        base.writeAt(i, 5, a.freq)
        i += 7
      of actDuck:
        base.writeAt(i, 1, a.duckAmount)
        base.writeAt(i, 3, a.duckThresh)
        base.writeAt(i, 5, a.duckAttack)
        base.writeAt(i, 7, a.duckRelease)
        i += 9
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
      of actMask, actConfine:
        base[i + 1] = (if a.mInvert: 0x1'u8 else: 0'u8) or
          (if a.mReset: 0x2'u8 else: 0'u8)
        base[i + 2] = a.mFeather
        base.writeAt(i, 3, a.mX)
        base.writeAt(i, 7, a.mY)
        base.writeAt(i, 11, a.mW)
        base.writeAt(i, 15, a.mH)
        base.writeAt(i, 19, a.mRadius)
        i += 23
      of actAberration:
        base.writeAt(i, 1, a.abRh)
        base.writeAt(i, 2, a.abRv)
        base.writeAt(i, 3, a.abGh)
        base.writeAt(i, 4, a.abGv)
        base.writeAt(i, 5, a.abBh)
        base.writeAt(i, 6, a.abBv)
        base[i + 7] = (if a.abWrap: 1'u8 else: 0'u8)
        i += 8
      of actLuv:
        base.writeAt(i, 1, a.brighthue)
        base.writeAt(i, 3, a.contrast)
        base.writeAt(i, 7, a.saturation)
        i += 11
      of actPos:
        if a.hasEase: base[i] = base[i] or easeFlag
        var pos = i + 1
        if a.hasEase:
          base[pos] = uint8(ord(a.easeCurve))
          base[pos + 1] = uint8(ord(a.easeDurUnit))
          var d = a.easeDur
          copyMem(addr base[pos + 2], addr d, sizeof(float32))
          pos += 6
        for s in [a.pxKf, a.pyKf, a.pscaleKf]:
          base[pos] = uint8(s.len)
          pos += 1
          for v in s:
            var vv = v
            copyMem(addr base[pos], addr vv, sizeof(float32))
            pos += 4
        i = pos
      of actDrawbox:
        base.writeAt(i, 1, a.dbX)
        base.writeAt(i, 5, a.dbY)
        base.writeAt(i, 9, a.dbW)
        base.writeAt(i, 13, a.dbH)
        base.writeAt(i, 17, a.dbColor)
        i += 20
      of actZoom, actBlur, actOpacity, actBrightness, actVolume:
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
          if a.kind in {actZoom, actBlur, actVolume}:
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
      if pendActive and action.kind in {actZoom, actBlur, actOpacity, actBrightness,
          actVolume, actPos} and not action.hasEase:
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
