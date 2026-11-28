import std/[algorithm, hashes, math, options, sequtils, strformat, strutils]
import ./lib/[dnorm16, escape, suggest, timeunit]
import ./util/color

type
  # The order is part of the API
  ActionKind* = enum
    actSpeed,
    # Can add 3 more [VA] actions
    actVolume = 4,
    actDeesser, actDuck, actPitch, actTone, actConvolve, actHighpass, actLowpass,
    actDehum,
    # Can add 7 more [A] actions
    actInvert = 20,
    actHflip, actVflip, actZoom, actOpacity, actBlur, actBrightness, actLuv, actLens,
    actRotate, actSpin, actDrawbox, actPos, actColorKey, actChromaKey, actLoop,
    actErosion, actChoke, actAberration, actMask, actConfine, actPixelate, actConfetti,
    actScale, actTurn, actBurn, actText, actMaskPoly, actConfinePoly
    # Can add 80 more [V] actions

  Easing* = enum  # interpolation curve for animations
    easeLinear, easeIn, easeOut, easeInOut

  Waveform* = enum  # tone timbre; the order is part of the API
    wSine, wSaw, wSquare, wTriangle

  ConfettiScheme* = enum
    csParty, csNeon, csGold, csDuotone, csWhite
  ConfettiOrigin* = enum
    coBottom, coTop, coCenter, coSides

  BurnPart* = enum  # what a burn's colors override; the order is part of atf-8
    bpColor, # the text
    bpOutline, # its outline
    bpBg # a box behind each subtitle

  DurUnit* = enum  # how an ease duration is measured
    duClip, # the whole clip/section (the default)
    duSec, # seconds
    duFrames # timeline frames

  KfUnit* = enum  # where a timed keyframe sits; the order is part of atf-8
    kuAuto, # between its timed neighbors (the first and last: the section's ends)
    kuPercent, # percent of the section
    kuSec, # seconds from the section's start
    kuFrames # timeline frames from the section's start
  KfTime* = object
    at*: float32
    unit*: KfUnit

  # Represents a full-sized action. Animatable scalar effects hold a list of
  # keyframes (one value = static, several = a ramp interpolated across the
  # section) plus an optional easing curve + duration packed inline.
  Action* = object
    # Easing envelope shared by every animatable action (zoom/blur/opacity/
    # brightness/volume/pos). Defaults (off, linear, whole-clip) make a static
    # action sample trivially, so non-animated actions just ignore these.
    easeDur*: float32 # magnitude in easeDurUnit (ignored for duClip)
    hasEase*: bool
    easeCurve*: Easing
    easeDurUnit*: DurUnit
    case kind*: ActionKind
    of actInvert, actHflip, actVflip, actLoop, actErosion:
      discard
    of actChoke:
      chokeN*: uint8 # matte-erosion passes (px to shrink the alpha matte)
    of actRotate:
      rStart*: Unorm16 # circular [0, 360) static angle (expands the canvas)
    of actScale:
      tScaleW*, tScaleH*: float32 # about the center
      tUniform*: bool # one value for both, as `scale:v` says
    of actTurn:
      tDeg*: float32 # clockwise about the center, without growing the frame
    of actBurn, actText:
      burnFile*: string # the subtitles: an .srt, .ass, or a file with a text stream
      burnFont*: string # a font file to draw them with; "" keeps their own
      burnFace*: string # which face of the font file: its style or full name, or its index; "" leaves it to the weight
      burnWeight*: uint16 # the weight to draw at, 400 regular and 700 bold; 0 keeps their own
      burnSize*: float32 # text height, percent of the frame's; 0 keeps their own
      burnSet*: set[BurnPart] # which of burnColors replace the subtitles' own
      burnColors*: array[BurnPart, uint32] # 0xRRGGBBAA
      burnAlign*: uint8
      burnVertical*: bool
      burnAss*: bool
    of actSpin:
      sStart*: Unorm16 # circular [0, 360) start angle
      sRate*: float32 # spin rate in degrees/second (continuous)
    of actLens:
      k1*, k2*: Snorm16
    of actSpeed:
      val*: float32 # the speed, or a ramp's mean speed over its media
      varispeed*: bool
      sKf*: seq[float32] # a ramp's keyframes across its media; empty if constant
      sKt*: seq[KfTime] # their times (auto or percent), or empty: evenly
    of actZoom, actBlur, actOpacity, actBrightness, actVolume:
      kf*: seq[float32] # keyframes in native units; len >= 1
      kt*: seq[KfTime] # each keyframe's time, or empty: spread evenly
    of actDeesser:
      intensity*, maxd*, freq*: Unorm16
    of actHighpass, actLowpass:
      cutoff*: uint16 # Hz
    of actDehum:
      humHz*: uint16 # the mains frequency
      humHarmonics*: uint8 # notches at humHz and its multiples, this many
    of actPitch:
      # Semitones x 100. Cent buckets round-trip as exact decimal semitones
      pCents*: int16
    of actTone:
      note*: uint8 # MIDI note number; 69 = A4 = 440 Hz
      wave*: Waveform # timbre (sine unless given)
    of actConvolve:
      irPath*: string # impulse response file, or a folder of H_LL/H_LR/H_RL/H_RR.wav
    of actDuck:
      # Cross-track sidechain: rendered at the mix stage, not in the clip chain.
      duckAmount*, duckThresh*: Unorm16  # 0..1; gain floor = 1 - amount
      duckAttack*, duckRelease*: uint16  # milliseconds
    of actLuv:
      contrast*: float32
      saturation*: float32
      brighthue*: Snorm16
    of actDrawbox:
      dbX*, dbY*, dbW*, dbH*: int32 # rectangle in pixels (x, y, width, height)
      dbColor*: RGBColor # outline color (RGB only)
    of actPos:
      # Overlay placement ramps: top-left x/y in canvas px and a size multiplier
      # (1.0 = native). Each is a keyframe seq (len 1 = static) like the scalars.
      pxKf*, pyKf*, pscaleKf*: seq[float32]
      pxKt*, pyKt*, pscaleKt*: seq[KfTime] # as `kt`
    of actColorKey, actChromaKey:
      color*: RGBColor
      similar*, blend*: Unorm16
    of actAberration:
      abRh*, abRv*, abGh*, abGv*, abBh*, abBv*: int8
      abWrap*: bool # edge: wrap around (true) vs smear the border (false)
    of actMask, actConfine, actMaskPoly, actConfinePoly:
      # `mask` shapes the clip's alpha; `confine` restricts following effects to
      # this region. Shared geometry, in canvas pixels like drawbox.
      mRadius*: int32 # corner radius px: 0=rect, >0=rounded rect, -1=ellipse
      mReset*: bool # confine bare: reset to full frame (region fields unused)
      mInvert*: bool # swap inside/outside
      mFeather*: uint8 # soft-edge width in px (0 = hard edge)
      mX*, mY*, mW*, mH*: int32
      mPolyXs*, mPolyYs*: seq[int32]
    of actPixelate:
      # Mosaic block size in px, each an animatable ramp (len 1 = static,
      # square blocks when the two match). Whole pixels: atf-8 packs them as
      # uint16, so a fractional keyframe could not round-trip.
      pixWKf*, pixHKf*: seq[float32]
      pixWKt*, pixHKt*: seq[KfTime] # as `kt`
    of actConfetti:
      cCount*: uint16
      cGravity*: float32
      cScheme*: ConfettiScheme
      cShimmer*: bool
      cOrigin*: ConfettiOrigin
      cSeed*: uint16

  Actions* = distinct int # A fat pointer to a list of action in atf-8 format.

  # atf-8: store actions in as small a space as possible, inspirited by utf-8.

  ActionParseError* = object of CatchableError
  ActionFlag* = enum # capabilities of an action
    afAudio,
    afVideo,
    afAnimatable # value can be a keyframe ramp (`a..b..c`) with easing
    afGenerator # may stand in for a file in `add:`, painting a clear canvas
  ActionFlags* = set[ActionFlag]

  RangeDoc* = object
    ## An interval of allowed values.
    lo*, hi*: float
    loIncl*, hiIncl*: bool # closed (inclusive) bounds
    each*: bool # the interval applies to each positional arg
  ArgKind* = enum
    ## What an action argument is written as.
    akNumber, # a decimal number
    akInteger, # a whole number
    akColor, # a color name, #rgb, #rrggbb, #rrggbbaa, or yuv#YYUUVV where taken
    akChoice, # one of `choices`
    akPath, # a file or folder
    akText, # free text
    akKeyframes, # a number or a ramp `a..b..c`, each optionally `@time`
    akFlag, # present or not, written as its bare name
    akDuration, # a time: a frame count, or with a unit like `2sec`
    akPoints # x/y pairs, `x1/y1/x2/y2/...`
  ArgDef* = object
    ## One argument of an action. Positional arguments come in order;
    ## `keyword` ones are written `name=value`, anywhere after them.
    name*: string
    kind*: ArgKind
    range*: Option[RangeDoc] # every value, for keyframes; parseAction rejects others
    optional*: bool
    default*: string # as written, when leaving it out means a value
    keyword*: bool
    choices*: seq[string]
    unit*: string
  ActionDef* = object
    ## An action: its name, what it applies to, its arguments, and its help.
    name*: string
    flags*: ActionFlags
    argSpec*: string  # storage type ("float32") or positional spec ("k1[:k2]")
    range*: Option[RangeDoc]
    args*: seq[ArgDef]
    help*: string

const
  easeFlag = 0x80'u8  # high bit of an animated action's atf-8 header byte
  varispeedFlag = 0x80'u8  # same bit on a speed action's header byte
  verticalFlag = 0x80'u8
  assFlag = 0x80'u8
  schemeMask = 0x07'u8
  originMask = 0x03'u8
  originShift = 3
  shimmerFlag = 0x80'u8
  yuvFlag = 0x80'u8
static:
  assert ord(high(ConfettiScheme)) <= schemeMask.int, "scheme outgrew 3 bits"
  assert ord(high(ConfettiOrigin)) <= originMask.int, "origin outgrew 2 bits"

const
  easeNames*: array[Easing, string] = ["linear", "in", "out", "inout"]
  alignNames*: array[1 .. 9, string] = ["bottom-left", "bottom",
    "bottom-right", "left", "center", "right", "top-left", "top", "top-right"]
  waveformNames*: array[Waveform, string] =
    ["sine", "saw", "square", "triangle"]
  confettiSchemeNames*: array[ConfettiScheme, string] =
    ["party", "neon", "gold", "duotone", "white"]
  confettiOriginNames*: array[ConfettiOrigin, string] =
    ["bottom", "top", "center", "sides"]
  confettiCountId = 200'u16
  confettiGravityId = 1.4'f32
  confettiOriginId = coSides

func rng(lo, hi: float; loIncl = true, hiIncl = true, each = false): Option[RangeDoc] =
  some(RangeDoc(lo: lo, hi: hi, loIncl: loIncl, hiIncl: hiIncl, each: each))

const
  i32Lo = float(low(int32))
  i32Hi = float(high(int32))

func arg(name: string, kind: ArgKind, lo, hi: float, loIncl, hiIncl: bool,
    default: string, optional, keyword: bool, choices: seq[string] = @[],
    unit = ""): ArgDef =
  result = ArgDef(name: name, kind: kind, optional: optional or default != "",
    default: default, keyword: keyword, choices: choices, unit: unit)
  if lo == lo: # NaN, the wrappers' default, means no range
    result.range = rng(lo, hi, loIncl, hiIncl)

func numArg(name: string, lo = NaN, hi = NaN, loIncl = true, hiIncl = true,
    default = "", optional = false, keyword = false, unit = ""): ArgDef =
  arg(name, akNumber, lo, hi, loIncl, hiIncl, default, optional, keyword, unit = unit)

func intArg(name: string, lo = NaN, hi = NaN, default = "", optional = false,
    keyword = false, unit = ""): ArgDef =
  arg(name, akInteger, lo, hi, true, true, default, optional, keyword, unit = unit)

func kfArg(name: string, lo = NaN, hi = NaN, loIncl = true, hiIncl = true,
    default = "", optional = false, unit = ""): ArgDef =
  arg(name, akKeyframes, lo, hi, loIncl, hiIncl, default, optional, false, unit = unit)

func colorArg(name: string, optional = false, keyword = false): ArgDef =
  arg(name, akColor, NaN, NaN, true, true, "", optional, keyword)

func choiceArg(name: string, choices: openArray[string], default = "",
    optional = false, keyword = false): ArgDef =
  arg(name, akChoice, NaN, NaN, true, true, default, optional, keyword, @choices)

func pathArg(name: string, optional = false, keyword = false): ArgDef =
  arg(name, akPath, NaN, NaN, true, true, "", optional, keyword)

func flagArg(name: string): ArgDef =
  arg(name, akFlag, NaN, NaN, true, true, "", true, true)

func shapeArgs(optional: bool): seq[ArgDef] =
  @[intArg("x", i32Lo, i32Hi, optional = optional, unit = "px"),
    intArg("y", i32Lo, i32Hi, optional = optional, unit = "px"),
    intArg("w", 1, i32Hi, optional = optional, unit = "px"),
    intArg("h", 1, i32Hi, optional = optional, unit = "px"),
    intArg("radius", -1, i32Hi, default = "0", unit = "px"),
    intArg("feather", 0, 255, default = "0", unit = "px"),
    flagArg("invert"),
    arg("poly", akPoints, i32Lo, i32Hi, loIncl = true, hiIncl = true, default = "",
      optional = true, keyword = true)]

func subsArgs(size: string): seq[ArgDef] =
  @[pathArg("font", optional = true, keyword = true),
    numArg("size", 0, 100, loIncl = false, default = size, optional = true,
      keyword = true, unit = "%"),
    colorArg("color", optional = true, keyword = true),
    colorArg("outline", optional = true, keyword = true),
    colorArg("bg", optional = true, keyword = true),
    choiceArg("align", alignNames, optional = true, keyword = true),
    arg("face", akText, NaN, NaN, true, true, "", optional = true, keyword = true),
    numArg("weight", 100, 1000, optional = true, keyword = true)]

func `$`*(r: RangeDoc): string =
  ## e.g. "(0.0, 99999.0)", "each [-1.0, 1.0]"
  let each = (if r.each: "each " else: "")
  let open = (if r.loIncl: "[" else: "(")
  let close = (if r.hiIncl: "]" else: ")")
  &"{each}{open}{r.lo}, {r.hi}{close}"

func `$`*(f: ActionFlags): string =
  if afAudio in f: result &= "A"
  if afVideo in f: result &= "V"
  if afAnimatable in f: result &= "*"
  if afGenerator in f: result &= "G"

const actionDefs*: seq[ActionDef] = @[
  ActionDef(name: "nil", flags: {afAudio, afVideo},
    help: "Do nothing. Keep the section unchanged at normal speed and pitch."),
  ActionDef(name: "cut", flags: {afAudio, afVideo},
    help: "Remove the section completely from the output."),
  ActionDef(name: "speed", flags: {afAudio, afVideo}, argSpec: "float32", range: rng(0.0, 99999.0, loIncl = false, hiIncl = false),
    args: @[kfArg("v", 0, 99999, loIncl = false, hiIncl = false)],
    help: "Change the playback speed while preserving pitch via time-stretching. 1.0 = unchanged, 2.0 = twice as fast, 0.5 = half speed. A ramp like `speed:1..4` or `speed:1@0%..6@50%..1` spreads its keyframes across the section's source, eased with `:ease=curve`."),
  ActionDef(name: "varispeed", flags: {afAudio, afVideo}, argSpec: "float32", range: rng(0.2, 100.0),
    args: @[kfArg("v", 0.2, 100)],
    help: "Change the playback speed by resampling, so pitch shifts along with it, like analog tape or vinyl. 1.0 = unchanged, 2.0 = twice as fast and an octave higher. Ramps like `speed`'s, e.g. `varispeed:1..4`."),
  ActionDef(name: "ease", flags: {afAudio, afVideo}, argSpec: "curve[:duration]",
    args: @[choiceArg("curve", easeNames), arg("duration", akDuration, 0, Inf,
      loIncl = true, hiIncl = false, default = "", optional = true, keyword = false)],
    help: """
Set the easing for the animated actions that follow it (until another `ease` overrides it); equivalent to adding `:ease=curve` to each. `curve` is one of `linear`, `in`, `out`, or `inout`.
The optional `duration` (e.g. `2sec` or a bare frame count) is how long the animation takes before holding at its end value; omitted, it spans the whole section. Example: `ease:inout,zoom:1..2`.
Keyframes can also say when they are, as `value@time`: a bare frame count, `sec`, or `%` of the section, e.g. `zoom:1@0..2@1.5sec..1@100%`. The value holds before the first and after the last, a keyframe without a time sits evenly between its timed neighbors, and the curve eases each step between keyframes. A duration can't be given with timed keyframes."""),
  ActionDef(name: "volume", flags: {afAudio, afAnimatable}, argSpec: "v[..v...]",
    args: @[kfArg("v")],
    help: "Scale the audio volume by val. 1.0 = unchanged, 0.5 = half (-6 dB), 2.0 = double (+6 dB). Animatable: accepts keyframes `a..b..c` interpolated across the section, optionally eased with `:ease=`."),
  ActionDef(name: "deesser", flags: {afAudio}, argSpec: "intensity[:max[:freq]]", range: rng(0.0, 1.0, each = true),
    args: @[numArg("intensity", 0, 1), numArg("max", 0, 1, default = "0.5"),
      numArg("freq", 0, 1, default = "0.5")],
    help: """
Reduce harsh "s" and "sh" sibilance in the section. Implemented via ffmpeg's `deesser` filter.
Positional args: `intensity` sets how much to de-ess (0.0 = none, 1.0 = maximum), `max` caps the reduction (default 0.5), and `freq` sets the split frequency (default 0.5)."""),
  ActionDef(name: "highpass", flags: {afAudio}, argSpec: "[hz]", range: rng(10.0, 20000.0),
    args: @[numArg("hz", 10, 20000, default = "80", unit = "Hz")],
    help: "Cut the lows below `hz` (default 80), such as rumble, wind and handling noise under speech. A 12 dB per octave Butterworth filter; chain two for a steeper slope."),
  ActionDef(name: "lowpass", flags: {afAudio}, argSpec: "[hz]", range: rng(10.0, 20000.0),
    args: @[numArg("hz", 10, 20000, default = "10000", unit = "Hz")],
    help: "Cut the highs above `hz` (default 10000), such as hiss. A 12 dB per octave Butterworth filter; chain two for a steeper slope."),
  ActionDef(name: "dehum", flags: {afAudio}, argSpec: "[hz[:harmonics]]",
    args: @[numArg("hz", 20, 1000, default = "60", unit = "Hz"),
      intArg("harmonics", 1, 16, default = "4")],
    help: "Remove mains hum: a narrow notch at `hz` (default 60; use 50 where the mains is 50 Hz) and at each of its first `harmonics` multiples (default 4, up to 16)."),
  ActionDef(name: "duck", flags: {afAudio}, argSpec: "[amount[:threshold[:attack[:release]]]]",
    args: @[numArg("amount", 0, 1, default = "0.85"), numArg("threshold", 0, 1, default = "0.04"),
      numArg("attack", 0, 65535, default = "100", unit = "ms"),
      numArg("release", 0, 65535, default = "500", unit = "ms")],
    help: """
Autoduck (sidechain): lower this clip's audio wherever the louder audio layers beneath it (higher track indices) are active, e.g. tuck a music/desktop track under a voice track. Cross-track, so it is applied when the audio layers are mixed; a no-op on the bottom-most layer and on single-layer audio.
Positional args: `amount` is the maximum attenuation (0.0 = none, 1.0 = duck to silence, default 0.85), `threshold` the key loudness 0.0..1.0 that engages the duck (default 0.04), and `attack`/`release` the duck-down/recover times in milliseconds (defaults 100 and 500)."""),
  ActionDef(name: "pitch", flags: {afAudio}, argSpec: "semitones", range: rng(-24.0, 24.0),
    args: @[numArg("semitones", -24, 24, unit = "semitones")],
    help: "Shift the pitch of the section without changing its speed. `12` is one octave up, `-12` one octave down, `0` leaves it unchanged, and fractional values work (`pitch:0.5` is a quarter tone). Implemented by resampling and then time-stretching back with ffmpeg's `asetrate` and `atempo` filters, so large shifts pick up the usual time-stretch artifacts. To change speed and pitch together, use `varispeed` instead."),
  ActionDef(name: "tone", flags: {afAudio, afGenerator}, argSpec: "midi-note[:waveform]", range: rng(0.0, 127.0),
    args: @[intArg("note", 0, 127), choiceArg("waveform", waveformNames, default = "sine")],
    help: "Synthesize a wave at a MIDI note's pitch, as a generator: it stands in for a file in `add:`, adding its own audio layer rather than altering existing audio. `69` is A4 (440 Hz), `60` middle C; each step is a semitone. `waveform` is `sine` (default), `saw`, `square`, or `triangle`; the harmonic-rich ones are band-limited, so they stay clean instead of aliasing at high notes. It has no envelope of its own — chain the animatable `volume` action for fades and decays, e.g. `add:tone:60,volume:1..0:ease=out`. Stack several `add:tone` layers for a chord; the mix sums them. `speed`/`varispeed` only stretch the tone, they do not change its pitch — change the note instead. Examples: `add:tone:69`, `add:tone:36:saw`, `add:tone:48:square,volume:0.4`."),
  ActionDef(name: "convolve", flags: {afAudio}, argSpec: "path",
    args: @[pathArg("path")],
    help: """
Make headphone audio sound farther from the ears: with Saq's spatial-stereo impulse responses (https://github.com/mTvare6/saqol/tree/main/crates/saq-dsp/assets/spatial-stereo), the processed version feels less "on the ear", so it feels less "blocked" after listening to music for a while. Download that folder and pass it as `path`, e.g. `convolve:spatial-stereo`.
More generally, this runs the audio through any measured impulse response (IR), like a convolution reverb or a cabinet sim. `path` is an audio file or a folder.
A file is one IR per channel: a mono IR is applied to every channel, one with as many channels as the audio is applied channel by channel, and a 4-channel IR on stereo audio is a true-stereo matrix in the order LL, LR, RL, RR, where LR is what the right input contributes to the left output.
A folder holds that matrix as `H_LL.wav`, `H_LR.wav`, `H_RL.wav`, and `H_RR.wav`, as Saq's does; a missing file is silence for that path, so `H_LL.wav` and `H_RR.wav` alone filter each side on its own. On audio that isn't stereo, the matrix is folded to the one IR mono audio would get.
IRs are resampled to the audio's rate and used at their own level, so a normalized reverb IR can be loud; chain `volume` to taste. Each section is convolved alone, so the tail is cut at its end. The path can't contain a comma."""),
  ActionDef(name: "invert", flags: {afVideo},
    help: "Invert every pixel in the section, producing a photo-negative."),
  ActionDef(name: "hflip", flags: {afVideo},
    help: "Flip the section horizontally, mirroring it left to right."),
  ActionDef(name: "vflip", flags: {afVideo},
    help: "Flip the section vertically, mirroring it top to bottom."),
  ActionDef(name: "erosion", flags: {afVideo},
    help: "Erode the picture by replacing each pixel with the darkest of its 3x3 neighborhood. Bright details shrink and dark regions grow, giving a gritty, eaten-away look. Implemented via ffmpeg's `erosion` filter."),
  ActionDef(name: "zoom", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(0.0, 100.0, loIncl = false),
    args: @[kfArg("v", 0, 100, loIncl = false)],
    help: "Scale the picture about its center by val. 1.0 = no zoom, 2.0 = zoom in 2x, 0.5 = zoom out 2x. Animatable: accepts keyframes `a..b..c` interpolated across the section, optionally eased with `:ease=`."),
  ActionDef(name: "opacity", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(0.0, 1.0),
    args: @[kfArg("v", 0, 1)],
    help: "Blend the section against the background. 1.0 = fully opaque, 0.0 = fully transparent. Animatable: accepts keyframes `a..b..c`, optionally eased with `:ease=`."),
  ActionDef(name: "blur", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(0.0, 1024.0),
    args: @[kfArg("v", 0, 1024)],
    help: "Gaussian-blur the picture by sigma = val. 0.0 = no blur; larger values blur more. Animatable: accepts keyframes `a..b..c`, optionally eased with `:ease=`."),
  ActionDef(name: "brightness", flags: {afVideo, afAnimatable}, argSpec: "v[..v...]", range: rng(-1.0, 1.0),
    args: @[kfArg("v", -1, 1)],
    help: "Shift brightness by adding an equal offset to the R, G, and B channels. 0.0 = unchanged, positive brightens, negative darkens. Implemented via ffmpeg's `lutrgb` filter. Animatable: accepts keyframes `a..b..c`, optionally eased with `:ease=`."),
  ActionDef(name: "brighthue", flags: {afVideo}, argSpec: "snorm16", range: rng(-1.0, 1.0),
    args: @[numArg("v", -1, 1)],
    help: "Shift luma by offsetting the Y channel. 0.0 = unchanged, positive brightens, negative darkens."),
  ActionDef(name: "contrast", flags: {afVideo}, argSpec: "float32", range: rng(-2.0, 2.0),
    args: @[numArg("v", -2, 2)],
    help: "Scale contrast around mid-gray. 1.0 = unchanged, higher values increase contrast, lower values reduce it. Implemented via ffmpeg's `lutyuv` filter."),
  ActionDef(name: "saturation", flags: {afVideo}, argSpec: "float32", range: rng(0.0, 3.0),
    args: @[numArg("v", 0, 3)],
    help: "Scale color saturation. 1.0 = unchanged, 0.0 = grayscale, higher values are more vivid. Implemented via ffmpeg's `lutyuv` filter."),
  ActionDef(name: "rotate", flags: {afVideo}, argSpec: "deg",
    args: @[numArg("deg", unit = "degrees")],
    help: "Rotate the picture clockwise about its center by a fixed `deg` angle, expanding the frame so nothing is clipped and filling the exposed corners with the background color. Good for aspect flips, e.g. `rotate:90`. For a continuous spin, use `spin` instead."),
  ActionDef(name: "scale", flags: {afVideo}, argSpec: "v|w:h", range: rng(0.0, 100.0, loIncl = false),
    args: @[numArg("w", 0, 100, loIncl = false), numArg("h", 0, 100, loIncl = false, optional = true)],
    help: "Scale the picture about its center, by `v` both ways or by `w` across and `h` down, e.g. `scale:0.8` or `scale:0.4:1`. On the base (bottom) track what grows past the edge is cut off and what shrinks away shows the background, like `zoom`; an overlay grows or shrinks about the center of where it's placed. Combines with `turn`."),
  ActionDef(name: "turn", flags: {afVideo}, argSpec: "deg",
    args: @[numArg("deg", unit = "degrees")],
    help: "Turn the picture clockwise by `deg` about its center without growing the frame, e.g. `turn:15`. On the base (bottom) track the corners are cut off and the uncovered area shows the background; an overlay turns about the center of where it's placed, its uncovered area transparent. For a turn that grows the frame to fit, use `rotate`; to keep turning, use `spin`."),
  ActionDef(name: "burn", flags: {afVideo, afGenerator},
    argSpec: "[file][:font=f][:size=pct][:color=c][:outline=c][:bg=c][:align=a][:face=f][:weight=w]",
    args: @[pathArg("file", optional = true)] & subsArgs(""),
    help: "Draw a subtitle file with libass: an .srt or .ass, or a file's first text subtitle stream, timed from the start of the layer or section it draws on and styled as it says. Without a file it draws the subtitles of the media under it, timed by that media's own clock so they stay on their words through cuts and speed changes: its first text subtitle stream, else the .srt or .ass beside it with its name, e.g. `--when-active burn:size=6`. As a generator it takes a file's place in `add:`, the subtitles on their own overlay layer, e.g. `add:burn:talk.srt`; as an action it draws over a section's picture. Each override replaces that part of every subtitle's style: `font` is a font file (.ttf, .otf, or .ttc) to draw with, `size` the text's height as a percent of the frame's, `color` the text's color, `outline` its outline's, `bg` a box behind each subtitle, and `align` where they sit (as `text` takes it). A font file can hold several faces: `weight` draws with the one of that weight, 400 regular and 700 bold, e.g. `font=Futura.ttc:weight=700`, and `face` names one outright, by its style (`face=Condensed ExtraBold`), its full name, or its index in the file from 0. Colors are names, `#rgb`, `#rrggbb`, or `#rrggbbaa` with transparency. E.g. `add:burn:talk.srt:size=6:color=yellow:bg=#00000099`. Paths can't contain a comma."),
  ActionDef(name: "text", flags: {afVideo, afGenerator},
    argSpec: "text[:font=f][:size=pct][:color=c][:outline=c][:bg=c][:align=a][:face=f][:weight=w][:vertical][:ass]",
    args: @[arg("text", akText, NaN, NaN, loIncl = true, hiIncl = true,
      default = "", optional = false, keyword = false)] & subsArgs("8") &
      @[flagArg("vertical"), flagArg("ass")],
    help: "Write a line of text with libass, white with a black outline in the frame's center unless told otherwise. As a generator it takes a file's place in `add:`, the text on its own overlay layer, e.g. `add:text:Chapter 1`; as an action it writes over a section's picture. In the text, `\\n` starts a new line, and a backslash before a comma, colon, or backslash keeps it from ending the text or the action: `text:Hello\\, world`. The overrides are `burn`'s, with `size` defaulting to 8, and `align` places the text: `center`, `top`, `bottom`, `left`, `right`, `top-left`, `top-right`, `bottom-left`, or `bottom-right`. Append `:vertical` for tategaki-style vertical layout: each line's characters stack top to bottom, upright, and lines run right to left (so the first `\\n`-separated line sits rightmost); `align` still places the whole block. Append `:ass` to write the text as ASS event text: override blocks like `{\\b1}` and escapes like `\\N` and `\\h` reach libass as written, so part of a text can be bold, italic, or another color. In an action, each of those backslashes doubles: `text:plain {\\\\b1}bold{\\\\b0}:ass`. Without `:ass`, braces and backslashes show as they are. To put it anywhere, chain `pos` onto its layer, e.g. `add:text:Hi:size=12,pos:0:-300`."),
  ActionDef(name: "spin", flags: {afVideo}, argSpec: "deg/rate",
    args: @[numArg("deg", unit = "degrees"), numArg("rate", unit = "degrees/sec")],
    help: "Spin the picture continuously, starting at `deg` and turning at `rate` degrees per second (negative is counter-clockwise), e.g. `spin:0/120`. The picture spins within a constant square that contains every rotation (so it is never clipped); on an overlay the exposed corners are transparent, otherwise they are filled with the background color."),
  ActionDef(name: "drawbox", flags: {afVideo, afGenerator}, argSpec: "x:y:w:h:color",
    args: @[intArg("x", i32Lo, i32Hi, unit = "px"), intArg("y", i32Lo, i32Hi, unit = "px"),
      intArg("w", 1, i32Hi, unit = "px"), intArg("h", 1, i32Hi, unit = "px"), colorArg("color")],
    help: "Draw a filled rectangle onto the picture. Positional args: `x` and `y` are the top-left corner, `w` and `h` the width and height in pixels, and `color` an RGB color (a name like `red` or a hex value like `#ff0000`), or `yuv#YYUUVV` to write those 8-bit Y'CbCr values into a YUV picture as they are. Example: `drawbox:100:100:400:200:red`. As a generator it can take a file's place in `add:`, painting the box on its own overlay layer, e.g. `add:drawbox:100:100:400:200:red`. Implemented via ffmpeg's `drawbox` filter."),
  ActionDef(name: "pos", flags: {afVideo, afAnimatable}, argSpec: "x:y[:scale]",
    args: @[kfArg("x", -2147483648.0, 2147483648.0, false, false, unit = "px"),
      kfArg("y", -2147483648.0, 2147483648.0, false, false, unit = "px"),
      kfArg("scale", 0, Inf, false, false, default = "1")],
    help: "Place this clip as an overlay when it is composited over a lower video track. `x` and `y` are the top-left corner in canvas pixels; the optional `scale` multiplies the source's native size (default 1.0). Has no effect on the base (bottom) track. Example: `pos:600:300:0.5`. Animatable: each of `x`, `y`, and `scale` accepts a keyframe ramp `a..b..c` interpolated across the section, optionally eased with `:ease=`, e.g. `pos:0..600:300:1..0.5:ease=inout` slides the overlay across while shrinking it."),
  ActionDef(name: "lens", flags: {afVideo}, argSpec: "k1[:k2]", range: rng(-1.0, 1.0, each = true),
    args: @[numArg("k1", -1, 1, default = "-0.5"), numArg("k2", -1, 1, default = "0")],
    help: """
Distort the picture like a camera lens. With no arguments, a fun fisheye is applied. Implemented via ffmpeg's `lenscorrection` filter.
Positional args: `k1` is the quadratic correction factor and `k2` the double-quadratic factor. Negative values bulge the image outward (fisheye); positive values pinch it inward (pincushion)."""),
  ActionDef(name: "colorkey", flags: {afVideo}, argSpec: "color[:similar:blend]", range: rng(0.0, 1.0),
    args: @[colorArg("color"), numArg("similar", 0, 1, default = "0.25"),
      numArg("blend", 0, 1, default = "0")],
    help: "Make a color transparent by matching it in RGB space. Best for flat, synthetic backgrounds (a logo's matte, a screen recording, a gif with one clean color); for real green-/blue-screen camera footage use `chromakey` instead. On the base (bottom) video track there is nothing to reveal, so the matched color is replaced with the timeline background (`-bg`) instead. Positional args: `color` is the key color (a name like `green`, a hex value, or `yuv#YYUUVV`), `similar` how close a pixel must be to be keyed (default 0.25), and `blend` how soft the edge is (default 0.0). Implemented via ffmpeg's `colorkey` filter."),
  ActionDef(name: "chromakey", flags: {afVideo}, argSpec: "color[:similar:blend]", range: rng(0.0, 1.0),
    args: @[colorArg("color"), numArg("similar", 0, 1, default = "0.25"),
      numArg("blend", 0, 1, default = "0")],
    help: "Make a color transparent by matching it in chroma (YUV) space, tolerating lighting variation, shadows, and soft edges. This is the green-/blue-screen keyer for real camera footage; for flat synthetic backgrounds use `colorkey` instead. On the base (bottom) video track there is nothing to reveal, so the matched color is replaced with the timeline background (`-bg`) instead. Positional args: `color` is the key color (a name like `green`, a hex value, or `yuv#YYUUVV`), `similar` how close a pixel must be to be keyed (default 0.25), and `blend` how soft the edge is (default 0.0). Implemented via ffmpeg's `chromakey` filter."),
  ActionDef(name: "choke", flags: {afVideo}, argSpec: "[n]", range: rng(1.0, 16.0),
    args: @[intArg("n", 1, 16, default = "1", unit = "px")],
    help: "Shrink (choke) the alpha matte left by a `colorkey`/`chromakey` inward by `n` pixels (default 1), cutting off the ring of key-color spill and ragged edge pixels around the subject. Must come after the key in the chain, e.g. `add:fg.mp4,chromakey:green,choke:2`. Only meaningful on overlay tracks (where keying produces alpha); a no-op on the base track. Implemented by eroding only the alpha plane via ffmpeg's `erosion` filter."),
  ActionDef(name: "aberration", flags: {afVideo}, argSpec: "[h[:v[:edge]]]", range: rng(-127.0, 127.0, each = true),
    args: @[intArg("h", -127, 127, default = "5", unit = "px"),
      intArg("v", -127, 127, default = "0", unit = "px"),
      choiceArg("edge", ["smear", "wrap"], default = "smear"),
      intArg("rh", -127, 127, default = "0", keyword = true, unit = "px"),
      intArg("rv", -127, 127, default = "0", keyword = true, unit = "px"),
      intArg("gh", -127, 127, default = "0", keyword = true, unit = "px"),
      intArg("gv", -127, 127, default = "0", keyword = true, unit = "px"),
      intArg("bh", -127, 127, default = "0", keyword = true, unit = "px"),
      intArg("bv", -127, 127, default = "0", keyword = true, unit = "px")],
    help: """
Fake chromatic aberration by shifting the color channels apart, leaving red/cyan fringing for a cheap-lens or glitch look. Implemented via ffmpeg's `rgbashift` filter.
Simple form `aberration[:h[:v[:edge]]]`: split red and blue symmetrically by `h` pixels horizontally (default 5) and `v` pixels vertically (default 0), with green left in place. `edge` is `smear` (extend the border pixel, the default) or `wrap` (wrap around to the far side).
Per-channel form: pass `key=value` pairs drawn from `rh`, `rv`, `gh`, `gv`, `bh`, `bv` (signed pixel shift for each channel/axis, default 0) plus `edge`, e.g. `aberration:rh=8:bh=-8:gv=2:edge=wrap`."""),
  ActionDef(name: "loop", flags: {afVideo},
    help: "Loop the clip's source back to its start when it runs out of frames, instead of ending. Useful for overlays whose source (e.g. a short gif) is shorter than the section it covers, e.g. `add:logo.gif,loop`."),
  ActionDef(name: "mask", flags: {afVideo},
    argSpec: "x:y:w:h[:radius][:feather][:invert] | poly=x1/y1/x2/y2/...[:feather=N][:invert]",
    args: shapeArgs(false),
    help: """
Cut the picture to a rounded-rectangle, ellipse, or arbitrary polygon, making everything outside the shape transparent. `x`/`y` are the top-left corner and `w`/`h` the size in pixels. `radius` is the corner radius in pixels: `0` (the default) is a sharp rectangle, a positive value rounds the corners, and `-1` is a true ellipse (the `w`x`h` box's inscribed oval). The optional `feather` softens the edge by that many pixels (0 = hard, the default); append `:invert` to hide the inside instead. Every field also takes a keyword form (`x=`, `y=`, `w=`, `h=`, `radius=`/`r=`, `feather=`), so positional and keyword args can be mixed.
The `poly=` form cuts to an arbitrary closed polygon instead: `x1/y1/x2/y2/...` is at least 3 points (canvas pixels, up to a few hundred, enough for a GUI to flatten Bezier curves into), filled with the nonzero winding rule, closing back to the first point. It takes `feather=` (keyword only here) and `:invert` same as above. Example: `mask:poly=960/200/1100/500/1300/520/1150/700/960/900/770/700/620/520/820/500`.
On the base (bottom) track there is nothing to reveal, so the masked-out area is filled with the timeline background (`-bg`) instead; on an overlay it reveals the track below. Good for circular/rounded picture-in-picture, vignettes, crop-to-shape, and star/sign/custom cutouts. Example: `add:cam.mp4,pos:900:540:0.3,mask:640:360:300:300:-1:40`."""),
  ActionDef(name: "confine", flags: {afVideo},
    argSpec: "[x:y:w:h[:radius][:feather][:invert] | poly=x1/y1/x2/y2/...[:feather=N][:invert]]",
    args: shapeArgs(true),
    help: "Restrict the adjustment effects that follow it (`blur`, `brightness`, `brighthue`, `contrast`, `saturation`, `invert`, `erosion`, `aberration`, `pixelate`) to a rounded-rectangle, ellipse, or arbitrary polygon region (`mask`'s geometry, including its `poly=` form), leaving the rest of the picture untouched. Stays in effect until the next `confine` changes the region; a bare `confine` with no arguments resets to the full frame. Geometry effects (zoom, rotate, pos, ...) are unaffected. Example: `confine:400:300:200:80,blur:30` blurs only the box, e.g. to censor a face or plate."),
  ActionDef(name: "pixelate", flags: {afVideo, afAnimatable}, argSpec: "[w[..w...][:h[..h...]]]", range: rng(1.0, 1024.0, each = true),
    args: @[kfArg("w", 1, 1024, default = "16", unit = "px"),
      kfArg("h", 1, 1024, optional = true, unit = "px")],
    help: "Pixelate the picture into a coarse mosaic of blocks, the classic censoring look. With no argument, uses 16px blocks; `pixelate:n` sets square n×n blocks and `pixelate:w:h` rectangular ones (px). Pair it with `confine` to censor just a face or plate, e.g. `confine:400:300:200:80,pixelate:24`. Implemented via ffmpeg's `pixelize` filter. Animatable: `w` and `h` each accept a keyframe ramp `a..b..c` of whole pixel sizes interpolated across the section, optionally eased with `:ease=`, e.g. `pixelate:1..48:ease=in` dissolves the picture into ever-coarser blocks."),
  ActionDef(name: "confetti", flags: {afVideo, afGenerator}, argSpec: "[count[:gravity][:scheme][:origin][:seed=N][:no-shimmer]]",
    args: @[intArg("count", 1, 400, default = "200"), numArg("gravity", 0, 20, default = "1.4"),
      choiceArg("scheme", confettiSchemeNames, default = "party"),
      choiceArg("origin", confettiOriginNames, default = "sides"),
      intArg("seed", 0, 65535, default = "0", keyword = true), flagArg("no-shimmer")],
    help: """
Throw colorful confetti over the picture. The whole charge fires in one burst when the section starts, like a party popper, and is not replenished as the pieces fall out of frame, so put the action on a short section where you want the pop. Each piece is a small four-sided chip that arcs over and flutters down, spinning and tumbling in 3D.
Every argument is optional and they may be given in any order, so `confetti:neon:top` and `confetti:top:neon` are the same; bare numbers fill `count` first, then `gravity`.
`count` is 1 to 400 (default 200). `gravity` is 0 to 20 (default 1.4), in frame-heights per second squared so it looks the same at any resolution. It sets how fast the pieces come back rather than how high they go: each is thrown to its own fraction of the way up the frame, and each catches its own amount of air, so they do not come down together. `seed=N` (0 to 65535, default 0) reshuffles the arrangement and changes nothing else, so bump it if you do not like how one landed.
`scheme` is `party` (default), `neon`, `gold`, `duotone`, or `white`. A chip flashes white as it turns edge-on, catching the light like foil; add `no-shimmer` to keep every piece its flat color. `origin` is `sides` (default, two cannons at the bottom corners firing inward), `bottom`, `top` (a shower from just above the frame), or `center`.
Drawn onto the frame, so it is not carried into video-editor exports. As a generator it can take a file's place in `add:`, painting the confetti on its own overlay layer, e.g. `add:confetti:300`. Examples: `confetti`, `confetti:250:3`, `confetti:60:0.8:white:center`."""),
]

func findArg(action, name: string): ArgDef =
  for d in actionDefs:
    if d.name == action:
      for a in d.args:
        if a.name == name: return a
  doAssert false, &"{action} has no argument {name}"

func inRange(r: RangeDoc, v: float): bool =
  (if r.loIncl: v >= r.lo else: v > r.lo) and (if r.hiIncl: v <= r.hi else: v < r.hi)

func rangeMsg(action: string, d: ArgDef, whole: bool): string =
  ## "zoom must be in (0.0, 100.0]", naming the argument when there are several.
  var count = 0
  for a in actionDefs:
    if a.name == action:
      count = a.args.len
      break
  let r = d.range.get
  func bound(v: float): string =
    if whole and abs(v) < 1e15: $int(v) else: $v
  let label = if count == 1: action else: &"{action} {d.name}"
  let what = if whole: "a whole number in" else: "in"
  let unit = if d.unit == "": "" else: " " & d.unit
  if r.hi == Inf:
    let what = if r.loIncl: "at least" else: "greater than"
    return &"{label} must be {what} {bound(r.lo)}{unit}"
  &"""{label} must be {what} {(if r.loIncl: "[" else: "(")}{bound(r.lo)}, """ &
    &"""{bound(r.hi)}{(if r.hiIncl: "]" else: ")")}{unit}"""

template checkArg(action, name: static string, v: float32 | float | int,
    alsoWhole = false) =
  ## Reject `v` outside the range actionDefs gives this argument.
  const d = findArg(action, name)
  const whole = d.kind == akInteger or alsoWhole
  const msg = rangeMsg(action, d, whole)
  let x = float(v)
  if not (inRange(d.range.get, x) and (not whole or x == round(x))):
    raise newException(ActionParseError, msg)

const actionNames* = block:
  var names: seq[string]
  for a in actionDefs:
    names.add a.name
  names

func actionDidYouMean*(val: string): string =
  let colon = val.find(':')
  let name = if colon == -1: val else: val[0 ..< colon]
  &"{val}{didYouMean(name, actionNames)}"

# Effects whose value can be a keyframe ramp (the `afAnimatable` actions).
const animScalar* = block:
  var names: seq[string]
  for a in actionDefs:
    if afAnimatable in a.flags:
      names.add a.name
  names

# Actions that can take a file's place in `add:` (the `afGenerator` actions).
const generatorActions* = block:
  var names: seq[string]
  for a in actionDefs:
    if afGenerator in a.flags:
      names.add a.name
  names

# Generators that paint audio rather than pixels: they land on an audio layer.
const audioGeneratorActions* = block:
  var names: seq[string]
  for a in actionDefs:
    if afGenerator in a.flags and afVideo notin a.flags:
      names.add a.name
  names

const aNil* = Actions(0)
const aCut* = Actions(1)

func isCut*(a: Actions): bool = int(a) == 1
func isEmpty*(a: Actions): bool = int(a) == 0

proc free*(a: Actions) =
  ## Release the buffer allocated by `newActions`.
  ##
  ## `aNil` and `aCut` are sentinel values and do not own a buffer.
  when not defined(nimscript):
    if int(a) > 1:
      dealloc(cast[pointer](int(a)))

const
  luvBrighthueId* = toSnorm16(0.0'f32)
  luvContrastId* = 1.0'f32
  luvSaturationId* = 1.0'f32

func brightnessLutExpr*(brightness: float32): string =
  ## FFmpeg LUT expression used by the renderer and editor exports.
  &"val+{brightness * 255.0'f32}"

func luvLutExprs*(brightness, contrast, saturation: float32): tuple[y, u, v: string] =
  ## Keep exported color adjustment math identical to the renderer.
  let shift = brightness * 255.0'f32
  result.y = &"(val-128)*{contrast}+128+{shift}"
  result.u = &"(val-128)*{saturation}+128"
  result.v = result.u

func clipT*(local, animLen: int): float32 =
  ## Normalized time over an animation of `animLen` steps (frames or samples),
  ## reaching 1.0 on the last step and holding there once the animation completes.
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

proc pFloat(s: string): float32 {.raises: [ActionParseError].} =
  # parseFloat accepts "nan" and "inf", which slip past `v < lo or v > hi`
  # checks and are UB when converted to an int.
  result =
    try: parseFloat(s).float32
    except ValueError: raise newException(ActionParseError, &"Invalid float value: {s}")
  if classify(result) in {fcNan, fcInf, fcNegInf}:
    raise newException(ActionParseError, &"Invalid float value: {s}")

proc pInt(s: string, what = "integer value"): int {.raises: [ActionParseError].} =
  try: parseInt(s)
  except ValueError: raise newException(ActionParseError, &"Invalid {what}: {s}")

proc parseDuration(spec: string): (float32, DurUnit) {.raises: [ActionParseError].} =
  ## "2s" or "2sec" -> (2, duSec); "30", "30f" or "30frames" -> (30, duFrames).
  ## The same units as times on the command line.
  let (num, suffix) = splitTimeUnit(spec)
  var tu: TimeUnit
  if not parseTimeUnit(suffix, tu):
    raise newException(ActionParseError, &"Invalid duration: {spec}")
  let n =
    try: parseFloat(num)
    except ValueError: raise newException(ActionParseError, &"Invalid duration: {spec}")
  result =
    if tu == tuFrames: (n.float32, duFrames)
    else: (float32(n * tu.seconds), duSec)
  # `not (a and b)` so NaN fails too; inf would write a timeline that can't
  # be read back.
  if not (result[0] >= 0 and result[0] < Inf):
    raise newException(ActionParseError, &"Duration can't be negative or infinite: {spec}")

proc parseKfTime*(spec: string): KfTime {.raises: [ActionParseError].} =
  ## "50%" -> percent of the section; otherwise a duration, as parseDuration.
  if spec.endsWith("%"):
    result = KfTime(at: pFloat(spec[0 ..< spec.len - 1]), unit: kuPercent)
    if not (result.at >= 0.0'f32 and result.at <= 100.0'f32):
      raise newException(ActionParseError, &"Keyframe time must be in [0%, 100%]: {spec}")
  else:
    let (at, unit) = parseDuration(spec)
    result = KfTime(at: at, unit: (if unit == duSec: kuSec else: kuFrames))
    if not (result.at >= 0.0'f32):
      raise newException(ActionParseError, &"Keyframe time must not be negative: {spec}")

func rotDeg*(code: Unorm16): float32 =
  ## Decode a circular rotate angle back into [0, 360) degrees.
  uint16(code).float32 / 65536.0'f32 * 360.0'f32

func pixCode(v: float32): uint16 =
  ## Quantize a pixelate block size for the atf-8 form. Parsing already bounds
  ## keyframes to whole pixels in [1, 1024]; the guard keeps a programmatically
  ## built Action off uint16(NaN), which is UB.
  if v != v: return 1
  uint16(max(1.0'f32, min(1024.0'f32, round(v))))

func rotCode(deg: float32): uint16 =
  ## Quantize degrees into a circular [0, 360) bucket (see the rotate action).
  let turns = deg / 360.0'f32
  let frac = turns - floor(turns)
  uint16(int(round(frac * 65536.0'f32)) and 0xFFFF)

proc parseKeyframes*(spec: string): seq[float32] {.raises: [ActionParseError].} =
  ## "2" -> @[2]; "1..0.5..1" -> @[1, 0.5, 1] (keyframes spread across the section).
  for part in spec.split(".."):
    result.add pFloat(part)
  # The packed action form stores the keyframe count in a single byte.
  if result.len > 255:
    raise newException(ActionParseError, "Too many keyframes (max 255)")

proc parseRamp*(spec: string): tuple[kf: seq[float32], kt: seq[KfTime]] {.
    raises: [ActionParseError].} =
  ## parseKeyframes, where a keyframe may say when it is: "1@0..2@1.5sec..1@100%".
  ## A keyframe without a time, in a ramp where another has one, sits evenly
  ## between its timed neighbors. `kt` is empty when none has a time.
  var timed = false
  for part in spec.split(".."):
    let at = part.find('@')
    if at < 0:
      result.kf.add pFloat(part)
      result.kt.add KfTime(unit: kuAuto)
    else:
      timed = true
      result.kf.add pFloat(part[0 ..< at])
      result.kt.add parseKfTime(part[at + 1 .. ^1])
  if result.kf.len > 255:
    raise newException(ActionParseError, "Too many keyframes (max 255)")
  if not timed: result.kt.setLen(0)

func sampleKf*(kf: seq[float32], p: float32): float32 =
  ## Piecewise-linear sample of keyframes at progress p in [0, 1].
  if kf.len <= 1:
    return (if kf.len == 1: kf[0] else: 0.0'f32)
  let x = clamp(p, 0.0'f32, 1.0'f32) * float32(kf.len - 1)
  let seg = min(int(x), kf.len - 2)
  kf[seg] + (kf[seg + 1] - kf[seg]) * (x - float32(seg))

func speedAt*(a: Action, u: float64): float64 =
  ## A speed action's speed `u` (0 to 1) of the way through its media.
  if a.sKf.len == 0: return a.val
  let u = clamp(u, 0.0, 1.0)
  if a.sKt.len == 0:
    return sampleKf(a.sKf, applyEase(a.easeCurve, u.float32))
  # Timed: auto keyframes sit evenly between their timed neighbors, and each
  # step between two keyframes is eased on its own.
  var at = newSeq[float64](a.sKf.len)
  var known = newSeq[bool](a.sKf.len)
  for i, t in a.sKt:
    if t.unit == kuPercent:
      at[i] = t.at / 100
      known[i] = true
  if not known[0]: (at[0], known[0]) = (0.0, true)
  if not known[^1]: (at[^1], known[^1]) = (1.0, true)
  var i = 1
  while i < at.len:
    if not known[i]:
      var j = i
      while not known[j]: inc j
      for k in i ..< j:
        at[k] = at[i - 1] + (at[j] - at[i - 1]) * float64(k - i + 1) / float64(j - i + 1)
      i = j
    inc i
  for k in 1 ..< at.len: at[k] = max(at[k], at[k - 1])
  if u <= at[0]: return a.sKf[0]
  for k in 1 ..< at.len:
    if u < at[k]:
      let t = float32((u - at[k - 1]) / (at[k] - at[k - 1]))
      return a.sKf[k - 1] + (a.sKf[k] - a.sKf[k - 1]) * applyEase(a.easeCurve, t)
  a.sKf[^1]

const speedSteps* = 512 ## samples across a ramp's media for its mean and map

func meanSpeed*(a: Action): float64 =
  ## The speed that covers a ramp's media in the same time: the harmonic mean
  ## across it.
  if a.sKf.len == 0: return a.val
  var inv = 0.0
  for i in 0 ..< speedSteps:
    inv += 1 / a.speedAt((i.float64 + 0.5) / speedSteps)
  speedSteps / inv

type
  AnimSpan* = object
    ## A section an animation plays over, measured in steps: frames when
    ## rendering video, samples for audio.
    len*: int
    perSec*, perFrame*: float64 # steps in a second, and in a timeline frame
  Ramp* = object
    ## One keyframe ramp of an action, ready to sample across an AnimSpan.
    kf: seq[float32]
    at: seq[float64] # each keyframe's step; empty when spread evenly
    curve: Easing
    easeLen: int

func frameSpan*(len: int, fps: float64): AnimSpan =
  AnimSpan(len: len, perSec: fps, perFrame: 1.0)

func kfSteps*(kt: seq[KfTime], span: AnimSpan): seq[float64] =
  ## Each timed keyframe's step from the section's start: untimed ones are
  ## spread between their neighbors, and none comes before the one before it.
  if kt.len == 0: return
  let last = float64(max(span.len - 1, 0))
  result = newSeq[float64](kt.len)
  var known = newSeq[bool](kt.len)
  for i, t in kt:
    known[i] = t.unit != kuAuto
    case t.unit
    of kuAuto: discard
    of kuPercent: result[i] = t.at.float64 / 100.0 * last
    of kuSec: result[i] = t.at.float64 * span.perSec
    of kuFrames: result[i] = t.at.float64 * span.perFrame
  if not known[0]: (result[0], known[0]) = (0.0, true)
  if not known[^1]: (result[^1], known[^1]) = (last, true)
  var i = 1
  while i < kt.len:
    if not known[i]:
      var j = i
      while not known[j]: inc j
      let a = i - 1
      for k in i ..< j:
        result[k] = result[a] + (result[j] - result[a]) * float64(k - a) / float64(j - a)
      i = j
    inc i
  for k in 1 ..< result.len:
    result[k] = max(result[k], result[k - 1])

func ramp*(a: Action, kf: seq[float32], kt: seq[KfTime], span: AnimSpan): Ramp =
  ## `kf` (with its times `kt`) as `a` animates it. An untimed ramp spreads
  ## across the ease duration (the section by default), eased as a whole; a
  ## timed one eases each step between keyframes.
  result = Ramp(kf: kf, curve: a.easeCurve, at: kfSteps(kt, span))
  result.easeLen = case a.easeDurUnit
    of duClip: span.len
    of duSec: max(1, int(round(a.easeDur.float64 * span.perSec)))
    of duFrames: max(1, int(round(a.easeDur.float64 * span.perFrame)))

func at*(r: Ramp, local: int): float32 =
  ## The ramp's value `local` steps into the section.
  if r.at.len == 0 or r.kf.len <= 1:
    return sampleKf(r.kf, applyEase(r.curve, clipT(local, r.easeLen)))
  let x = local.float64
  if x <= r.at[0]: return r.kf[0]
  for i in 1 ..< r.kf.len:
    if x < r.at[i]:
      let u = float32((x - r.at[i - 1]) / (r.at[i] - r.at[i - 1]))
      return r.kf[i - 1] + (r.kf[i] - r.kf[i - 1]) * applyEase(r.curve, u)
  r.kf[^1]

func timedKeys*(a: Action, kf: seq[float32], kt: seq[KfTime], clipDur: int,
    fps: float64): seq[(int, float32)] =
  ## Control points (frame, value) that trace a timed ramp over a clip of
  ## `clipDur` frames when joined linearly, as editors do: its keyframes, and
  ## when it's eased, samples between them.
  let last = max(1, clipDur - 1)
  let r = a.ramp(kf, kt, frameSpan(clipDur, fps))
  var frames = @[0, last]
  for s in r.at: frames.add clamp(int(round(s)), 0, last)
  if a.easeCurve != easeLinear:
    let samples = min(last, 60)
    for s in 0 .. samples:
      frames.add int(round(s.float / samples.float * last.float))
  frames.sort()
  for f in frames:
    if result.len == 0 or result[^1][0] != f: result.add (f, r.at(f))

proc parseEasing(spec: string): Easing {.raises: [ActionParseError].} =
  let name = if spec.startsWith("ease="): spec[5 .. ^1] else: spec
  if name == "in-out":
    return easeInOut
  for e, n in easeNames:
    if n == name:
      return e
  raise newException(ActionParseError, &"Unknown easing: {spec}")

func isTimed*(a: Action): bool =
  ## Whether any of the action's keyframes says when it is.
  case a.kind
  of actZoom, actBlur, actOpacity, actBrightness, actVolume: a.kt.len > 0
  of actPos: a.pxKt.len > 0 or a.pyKt.len > 0 or a.pscaleKt.len > 0
  of actPixelate: a.pixWKt.len > 0 or a.pixHKt.len > 0
  else: false

proc parseRgba(spec, what: string): uint32 {.raises: [ActionParseError].} =
  ## A color as 0xRRGGBBAA: a name, #rgb, #rrggbb, or #rrggbbaa.
  if spec.startsWith("#") and spec.len == 9:
    try: return uint32(parseHexInt(spec[1 .. ^1]))
    except ValueError: discard
    raise newException(ActionParseError, &"{what}: invalid color {spec}")
  let c = try: parseColor(spec)
    except ValueError as e: raise newException(ActionParseError, &"{what}: {e.msg}")
  if c.yuv:
    raise newException(ActionParseError, &"{what}: YUV colors aren't supported here")
  (c.red.uint32 shl 24) or (c.green.uint32 shl 16) or (c.blue.uint32 shl 8) or 0xff

func rgbaStr*(c: uint32): string =
  ## #rrggbb, or #rrggbbaa when it's see-through.
  result = "#" & toHex(int(c shr 8), 6).toLowerAscii
  if (c and 0xff) != 0xff: result &= toHex(int(c and 0xff), 2).toLowerAscii

const subsKeys = ["file", "font", "size", "color", "outline", "bg", "align", "face",
  "weight"]

func textPart(text: string): string =
  result = escapeText(text)
  let eq = text.find('=')
  let head = if eq > 0: text[0 ..< eq] else: text
  if head in subsKeys or head in ["vertical", "ass"]: result = "\\" & result

type
  ArgValue* = object
    ## One written argument, typed by its ArgDef's kind.
    case kind*: ArgKind
    of akNumber, akInteger: num*: float64
    of akKeyframes:
      kf*: seq[float64]
      kt*: seq[KfTime] # each keyframe's time, or empty when none has one
    of akColor, akChoice, akPath, akText:
      str*: string # as written, after it parses; text and paths unescaped
    of akDuration:
      dur*: float64 # seconds for duSec, frames for duFrames
      durUnit*: DurUnit
    of akFlag: on*: bool # confetti's `shimmer` is a `no-shimmer` that's off
    of akPoints: pts*: seq[int32] # x1, y1, x2, y2, ...
  SpecEase* = object
    ## An animated action's `:ease=curve[:duration]`.
    curve*: Easing
    dur*: float64 # in `unit`; 0 for duClip
    unit*: DurUnit # duClip when no duration is written
  ActionSpec* = object
    ## An action as written, before toAction packs it. `args` lines up with
    ## its ActionDef's, none where an argument isn't written. Numbers are
    ## float64 and colors are kept as written; `$` doesn't normalize them.
    name*: string
    args*: seq[Option[ArgValue]]
    ease*: Option[SpecEase]

func `==`*(a, b: ArgValue): bool =
  ## Values compare as numbers, so `16` equals `16.0`.
  if a.kind != b.kind: return false
  case a.kind
  of akNumber, akInteger: a.num == b.num
  of akKeyframes: a.kf == b.kf and a.kt == b.kt
  of akColor, akChoice, akPath, akText: a.str == b.str
  of akDuration: a.dur == b.dur and a.durUnit == b.durUnit
  of akFlag: a.on == b.on
  of akPoints: a.pts == b.pts

func `==`*(a, b: ActionSpec): bool =
  ## Equal as written: an argument left out isn't equal to one given its
  ## default, so `lens:-0.5` isn't `lens`.
  a.name == b.name and a.args == b.args and a.ease == b.ease

func argIndex*(action, arg: string): int =
  ## Where `arg` sits in `action`'s ActionDef.args and an ActionSpec's
  ## args, or -1 when it has no such argument.
  for d in actionDefs:
    if d.name == action:
      for i, a in d.args:
        if a.name == arg: return i
  -1

template ix(action, arg: static string): int =
  const i = argIndex(action, arg)
  static: doAssert i >= 0, action & " has no argument " & arg
  i

func initSpec*(name: string): ActionSpec =
  ## A spec for `name` with nothing written, its args sized to the action's.
  ## An unknown name has no args.
  result = ActionSpec(name: name)
  for d in actionDefs:
    if d.name == name:
      result.args.setLen(d.args.len)

func numV(v: float64): Option[ArgValue] = some(ArgValue(kind: akNumber, num: v))
func intV(v: int): Option[ArgValue] = some(ArgValue(kind: akInteger, num: float64(v)))
func kfV(r: tuple[kf: seq[float64], kt: seq[KfTime]]): Option[ArgValue] =
  some(ArgValue(kind: akKeyframes, kf: r.kf, kt: r.kt))
func strV(kind: ArgKind, s: string): Option[ArgValue] =
  case kind
  of akColor: some(ArgValue(kind: akColor, str: s))
  of akChoice: some(ArgValue(kind: akChoice, str: s))
  of akPath: some(ArgValue(kind: akPath, str: s))
  else: some(ArgValue(kind: akText, str: s))
func flagV(on = true): Option[ArgValue] = some(ArgValue(kind: akFlag, on: on))

proc pNum(s: string): float64 {.raises: [ActionParseError].} =
  ## A number that's finite as the float32 it's packed into.
  result =
    try: parseFloat(s)
    except ValueError: raise newException(ActionParseError, &"Invalid float value: {s}")
  if classify(float32(result)) in {fcNan, fcInf, fcNegInf}:
    raise newException(ActionParseError, &"Invalid float value: {s}")

proc pDur(spec: string): (float64, DurUnit) {.raises: [ActionParseError].} =
  ## parseDuration, kept as a float64.
  let (num, suffix) = splitTimeUnit(spec)
  var tu: TimeUnit
  if not parseTimeUnit(suffix, tu):
    raise newException(ActionParseError, &"Invalid duration: {spec}")
  let n =
    try: parseFloat(num)
    except ValueError: raise newException(ActionParseError, &"Invalid duration: {spec}")
  result = if tu == tuFrames: (n, duFrames) else: (n * tu.seconds, duSec)
  # `not (a and b)` so NaN fails too; inf would write a timeline that can't
  # be read back.
  let f = float32(result[0])
  if not (f >= 0 and f < Inf):
    raise newException(ActionParseError, &"Duration can't be negative or infinite: {spec}")

proc pRamp(spec: string): tuple[kf: seq[float64], kt: seq[KfTime]] {.
    raises: [ActionParseError].} =
  ## parseRamp, kept as float64s.
  var timed = false
  for part in spec.split(".."):
    let at = part.find('@')
    if at < 0:
      result.kf.add pNum(part)
      result.kt.add KfTime(unit: kuAuto)
    else:
      timed = true
      result.kf.add pNum(part[0 ..< at])
      result.kt.add parseKfTime(part[at + 1 .. ^1])
  if result.kf.len > 255:
    raise newException(ActionParseError, "Too many keyframes (max 255)")
  if not timed: result.kt.setLen(0)

proc easeTail(s: var ActionSpec, parts: seq[string], idx: int,
    val: string) {.raises: [ActionParseError].} =
  ## Consume an animatable action's trailing ":ease=curve[:duration]", which
  ## starts at parts[idx]; anything else trailing there is not a valid action.
  if idx >= parts.len:
    return
  if not parts[idx].startsWith("ease=") or parts.len > idx + 2:
    raise newException(ActionParseError, &"Unknown action: {actionDidYouMean(val)}")
  var e = SpecEase(curve: parseEasing(parts[idx]))
  if parts.len == idx + 2:
    (e.dur, e.unit) = pDur(parts[idx + 1])
  s.ease = some(e)

func isTimed(s: ActionSpec): bool =
  for a in s.args:
    if a.isSome and a.get.kind == akKeyframes and a.get.kt.len > 0: return true

proc checkTimedEase(s: ActionSpec) {.raises: [ActionParseError].} =
  # Timed keyframes say how long the animation takes; an ease duration would
  # say it again.
  if s.isTimed and s.ease.isSome and s.ease.get.unit != duClip:
    raise newException(ActionParseError,
      "An ease duration can't be given with timed keyframes")

proc subsSpec(parts: seq[string], text: bool): ActionSpec {.raises: [ActionParseError].} =
  # The subtitle file comes first, unnamed, then key=value overrides. A part
  # that isn't one goes back onto what came before it, so the colon of a
  # Windows drive stays in a path.
  let name = parts[0]
  var given: array[subsKeys.len, string]
  var seen: array[subsKeys.len, bool]
  var vertical, ass = false
  var cur = 0
  for part in parts[1 .. ^1]:
    if part in ["vertical", "ass"]:
      if not text:
        raise newException(ActionParseError, &"{name}: {part} only applies to text")
      if part == "vertical": vertical = true else: ass = true
    else:
      let eq = part.find('=')
      let key = if eq > 0: subsKeys.find(part[0 ..< eq]) else: -1
      if key > 0 or key == 0 and not text:
        if seen[key]:
          raise newException(ActionParseError, &"{name}: {subsKeys[key]} given twice")
        (cur, seen[key], given[key]) = (key, true, part[eq + 1 .. ^1])
      elif seen[cur] or cur == 0 and given[0].len > 0:
        given[cur] &= ":" & part
      else:
        (seen[cur], given[cur]) = (true, part)
  if text: given[0] = decodeString(given[0])
  if text and given[0].len == 0:
    raise newException(ActionParseError, "text needs something to say")
  if given[0].len > 4096 or given[1].len > 4096:
    raise newException(ActionParseError,
      if text: "text is too long" else: "burn path is too long")
  result = initSpec(name)
  if given[0].len > 0:
    result.args[0] = strV(if text: akText else: akPath, given[0])
  if seen[1]: result.args[ix("burn", "font")] = strV(akPath, given[1])
  if seen[2]:
    let size = pNum(given[2])
    if text: checkArg("text", "size", float32(size))
    else: checkArg("burn", "size", float32(size))
    result.args[ix("burn", "size")] = numV(size)
  for k in 3 .. 5:
    if seen[k]:
      discard parseRgba(given[k], &"{name} {subsKeys[k]}")
      result.args[k] = strV(akColor, given[k])
  static: doAssert ix("burn", "color") == 3 and ix("burn", "bg") == 5
  if seen[6]:
    if alignNames.find(given[6]) < 0:
      raise newException(ActionParseError, &"{name}: unknown align: {given[6]}")
    result.args[ix("burn", "align")] = strV(akChoice, given[6])
  if seen[7]:
    if given[7].len == 0 or given[7].len > 255:
      raise newException(ActionParseError, &"{name}: face needs a face's name or index")
    result.args[ix("burn", "face")] = strV(akText, given[7])
  if seen[8]:
    let weight = pNum(given[8])
    if text: checkArg("text", "weight", float32(weight))
    else: checkArg("burn", "weight", float32(weight))
    result.args[ix("burn", "weight")] = numV(weight)
  if vertical: result.args[ix("text", "vertical")] = flagV()
  if ass: result.args[ix("text", "ass")] = flagV()

proc shapeSpec(parts: seq[string], name: string): ActionSpec {.
    raises: [ActionParseError].} =
  ## Shared `x:y:w:h[:radius][:feather][:invert]` geometry for `mask`/`confine`.
  ## Fields take positional or `key=value` form (freely mixed); `invert` is a
  ## bare flag. radius: 0 = rect, >0 = rounded-rect corner px, -1 = ellipse.
  const slots = ["x", "y", "w", "h", "radius", "feather"]  # positional order
  var vals: array[6, int] # x, y, w, h, radius, feather
  var seen: array[6, bool]
  var inv = false
  var nextPos = 0 # next unfilled positional slot

  func slotOf(key: string): int =
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
      raise newException(ActionParseError, &"{name}: invalid integer: {ctx}")
    if vals[i] < low(int32).int or vals[i] > high(int32).int:
      raise newException(ActionParseError, &"{name}: value out of range: {ctx}")
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
        raise newException(ActionParseError, &"{name}: unknown key: {key}")
      setSlot(s, p[eq + 1 .. ^1], p)
    else:
      while nextPos < slots.len and seen[nextPos]: inc nextPos
      if nextPos >= slots.len:
        raise newException(ActionParseError, &"{name}: too many values: {p}")
      setSlot(nextPos, p, p)

  for i in 0 ..< 4:
    if not seen[i]:
      raise newException(ActionParseError, &"{name} requires {slots[i]}")
  template check(action: static string) =
    checkArg(action, "w", vals[2])
    checkArg(action, "h", vals[3])
    checkArg(action, "radius", vals[4])
    checkArg(action, "feather", vals[5])
  if name == "mask": check("mask") else: check("confine")

  result = initSpec(name)
  static: doAssert ix("mask", "feather") == 5 and ix("confine", "feather") == 5
  for i in 0 ..< 6:
    if seen[i]: result.args[i] = intV(vals[i])
  if inv: result.args[ix("mask", "invert")] = flagV()

const maxPolyPoints = 1000

proc polySpec(parts: seq[string], name: string): ActionSpec {.
    raises: [ActionParseError].} =
  var pts: seq[int32]
  var feather = -1
  var inv = false
  var gotPoly = false

  proc addPoint(raw, ctx: string): int32 {.raises: [ActionParseError].} =
    let v = try: parseInt(raw)
      except ValueError: raise newException(ActionParseError,
        &"{name}: invalid integer: {ctx}")
    if v < low(int32).int or v > high(int32).int:
      raise newException(ActionParseError, &"{name}: value out of range: {ctx}")
    int32(v)

  for idx in 1 ..< parts.len:
    let p = parts[idx]
    if p == "invert":
      inv = true
    elif p.startsWith("poly="):
      if gotPoly:
        raise newException(ActionParseError, &"{name}: poly given twice")
      gotPoly = true
      let nums = p[5 .. ^1].split('/')
      if nums.len mod 2 != 0:
        raise newException(ActionParseError, &"{name}: poly needs x/y pairs")
      let n = nums.len div 2
      if n < 3:
        raise newException(ActionParseError, &"{name}: poly needs at least 3 points")
      if n > maxPolyPoints:
        raise newException(ActionParseError,
          &"{name}: poly has too many points (max {maxPolyPoints})")
      for num in nums:
        pts.add addPoint(num, p)
    elif p.startsWith("feather="):
      let v = try: parseInt(p[8 .. ^1])
        except ValueError: raise newException(ActionParseError, &"{name}: invalid feather: {p}")
      if name == "mask": checkArg("mask", "feather", v)
      else: checkArg("confine", "feather", v)
      feather = v
    else:
      raise newException(ActionParseError, &"{name}: unknown key: {p}")

  if not gotPoly:
    raise newException(ActionParseError, &"{name} poly requires at least 3 points")

  result = initSpec(name)
  result.args[ix("mask", "poly")] = some(ArgValue(kind: akPoints, pts: pts))
  if feather >= 0: result.args[ix("mask", "feather")] = intV(feather)
  if inv: result.args[ix("mask", "invert")] = flagV()

func checkSpeed(name: string, v: float32) {.raises: [ActionParseError].} =
  # Speed <= 0 makes the renderer's atempo decomposition loop forever, and its
  # asetrate holds varispeed to its range.
  if name == "varispeed": checkArg("varispeed", "v", v)
  else: checkArg("speed", "v", v)

func parseActionSpec*(val: string): ActionSpec {.raises: [ActionParseError].} =
  ## Parse an action as written, with every check parseAction makes. Also
  ## takes `cut`, `nil` and `ease:curve[:duration]`, which toAction refuses.
  if val in ["invert", "hflip", "vflip", "loop", "erosion", "cut", "nil", "confine"]:
    # A bare confine resets to the full frame.
    return initSpec(val)

  if val.startsWith("text:"):
    return subsSpec(splitUnescaped(val, ':'), true)

  let parts = val.split(":")
  let name = parts[0]

  if name in ["mask", "confine"]:
    if parts.anyIt(it.startsWith("poly=")):
      return polySpec(parts, name)
    return shapeSpec(parts, name)

  if name == "burn":
    return subsSpec(parts, false)

  if name == "convolve":
    # The path is everything after the name, so a Windows drive colon stays put.
    let path = parts[1 .. ^1].join(":")
    if path.len == 0:
      raise newException(ActionParseError, "convolve needs a path")
    if path.len > 4096:
      raise newException(ActionParseError, "convolve path is too long")
    result = initSpec(name)
    result.args[0] = strV(akPath, path)
    return

  if name == "ease" and parts.len in 2..3:
    result = initSpec(name)
    result.args[0] = strV(akChoice, easeNames[parseEasing(parts[1])])
    if parts.len == 3:
      let (dur, unit) = pDur(parts[2])
      result.args[1] = some(ArgValue(kind: akDuration, dur: dur, durUnit: unit))
    return

  result = initSpec(name)

  # deesser takes positional args: intensity[:max[:freq]]
  if parts.len >= 2 and parts.len <= 4 and name == "deesser":
    for idx in 1 ..< parts.len:
      let v = pNum(parts[idx])
      case idx
      of 1: checkArg("deesser", "intensity", float32(v))
      of 2: checkArg("deesser", "max", float32(v))
      else: checkArg("deesser", "freq", float32(v))
      result.args[idx - 1] = numV(v)
    return

  if name in ["highpass", "lowpass"] and parts.len <= 2:
    if parts.len == 2:
      let hz = pNum(parts[1])
      if name == "highpass": checkArg("highpass", "hz", float32(hz))
      else: checkArg("lowpass", "hz", float32(hz))
      result.args[0] = numV(hz)
    return

  if name == "dehum" and parts.len <= 3:
    var hz = 60.0
    var n = 4.0
    if parts.len >= 2:
      hz = pNum(parts[1])
      result.args[0] = numV(hz)
    if parts.len == 3:
      n = pNum(parts[2])
      result.args[1] = some(ArgValue(kind: akInteger, num: n))
    checkArg("dehum", "hz", float32(hz))
    checkArg("dehum", "harmonics", float32(n))
    return

  # duck takes positional args: [amount[:threshold[:attack[:release]]]]
  if name == "duck" and parts.len <= 5:
    var vals = [0.85, 0.04, 100.0, 500.0]
    for idx in 1 ..< parts.len:
      vals[idx - 1] = pNum(parts[idx])
      result.args[idx - 1] = numV(vals[idx - 1])
    checkArg("duck", "amount", float32(vals[0]))
    checkArg("duck", "threshold", float32(vals[1]))
    checkArg("duck", "attack", float32(vals[2]))
    checkArg("duck", "release", float32(vals[3]))
    return

  # lens takes positional args: [k1[:k2]]; bare, a fun fisheye.
  if name == "lens" and parts.len <= 3:
    var k = [0.0, 0.0]
    for idx in 1 ..< parts.len:
      k[idx - 1] = pNum(parts[idx])
      result.args[idx - 1] = numV(k[idx - 1])
    checkArg("lens", "k1", float32(k[0]))
    checkArg("lens", "k2", float32(k[1]))
    return

  # tone: a MIDI note plus an optional waveform name, "tone:note[:waveform]".
  if name == "tone" and parts.len <= 3:
    if parts.len == 1:
      raise newException(ActionParseError, "tone requires a MIDI note (tone:69 is A4)")
    let n = pNum(parts[1])
    # Whole notes only: a fraction would round away silently and stop
    # round-tripping.
    checkArg("tone", "note", float32(n))
    result.args[0] = some(ArgValue(kind: akInteger, num: n))
    if parts.len == 3:
      if waveformNames.find(parts[2]) < 0:
        raise newException(ActionParseError, &"tone: unknown waveform: {parts[2]}" &
          didYouMean(parts[2], @waveformNames))
      result.args[1] = strV(akChoice, parts[2])
    return

  # rotate: a fixed angle "rotate:deg" (static, expands the canvas).
  if name == "rotate" and parts.len == 2:
    if '/' in parts[1]:
      raise newException(ActionParseError,
        "rotate takes a fixed angle (rotate:deg); use spin:deg/rate for a continuous spin")
    result.args[0] = numV(pNum(parts[1]))
    return

  if name == "scale" and parts.len in 2..3:
    let w = pNum(parts[1])
    let h = (if parts.len == 3: pNum(parts[2]) else: w)
    checkArg("scale", "w", float32(w))
    checkArg("scale", "h", float32(h))
    result.args[0] = numV(w)
    if parts.len == 3: result.args[1] = numV(h)
    return
  if name == "turn" and parts.len == 2:
    result.args[0] = numV(pNum(parts[1]))
    return

  # spin: a continuous rotation "spin:deg/rate", starting at `deg` and turning
  # `rate` degrees/second.
  if name == "spin" and parts.len == 2:
    let spec = parts[1]
    let slash = spec.find('/')
    if slash < 0:
      raise newException(ActionParseError, "spin requires spin:deg/rate")
    result.args[0] = numV(pNum(spec[0 ..< slash]))
    result.args[1] = numV(pNum(spec[slash + 1 .. ^1]))
    return

  # drawbox takes positional args: x:y:w:h:color (color is RGB only).
  if name == "drawbox":
    if parts.len != 6:
      raise newException(ActionParseError, "drawbox requires x:y:w:h:color")
    for idx in 0 ..< 4:
      let n = pInt(parts[idx + 1])
      case idx
      of 0: checkArg("drawbox", "x", n)
      of 1: checkArg("drawbox", "y", n)
      of 2: checkArg("drawbox", "w", n)
      else: checkArg("drawbox", "h", n)
      result.args[idx] = intV(n)
    try: discard parseColor(parts[5])
    except ValueError: raise newException(ActionParseError, &"Invalid color: {parts[5]}")
    result.args[4] = strV(akColor, parts[5])
    return

  if name in ["colorkey", "chromakey"]:
    if parts.len < 2 or parts.len > 4:
      raise newException(ActionParseError, &"{name} requires color[:similar:blend]")
    try: discard parseColor(parts[1])
    except ValueError: raise newException(ActionParseError, &"Invalid color: {parts[1]}")
    result.args[0] = strV(akColor, parts[1])
    for idx in 2 ..< parts.len:
      let v = pNum(parts[idx])
      # Both keyers take the same ranges.
      if idx == 2: checkArg("colorkey", "similar", float32(v))
      else: checkArg("colorkey", "blend", float32(v))
      result.args[idx - 1] = numV(v)
    return

  # choke: shrink the alpha matte inward by `n` pixels (default 1).
  if name == "choke" and parts.len <= 2:
    if parts.len == 2:
      let n = pInt(parts[1])
      checkArg("choke", "n", n)
      result.args[0] = intV(n)
    return

  # pixelate: bare = 16px blocks; pixelate:n = n square; pixelate:w:h =
  # rectangular. Each size is a ramp with an optional ease suffix:
  #   pixelate:24   pixelate:1..48   pixelate:8..40:8:ease=inout
  if name == "pixelate":
    proc blockKf(spec: string, isW: bool): tuple[kf: seq[float64], kt: seq[KfTime]] {.
        raises: [ActionParseError].} =
      # Whole pixels: atf-8 packs them as uint16.
      result = pRamp(spec)
      for v in result.kf:
        if isW: checkArg("pixelate", "w", float32(v), alsoWhole = true)
        else: checkArg("pixelate", "h", float32(v), alsoWhole = true)

    var idx = 1
    if parts.len > idx and not parts[idx].startsWith("ease="):
      result.args[0] = kfV(blockKf(parts[idx], true))
      inc idx
      if parts.len > idx and not parts[idx].startsWith("ease="):
        result.args[1] = kfV(blockKf(parts[idx], false))
        inc idx
    result.easeTail(parts, idx, val)
    result.checkTimedEase()
    return

  # confetti: [count[:gravity][:scheme][:origin]]. Scheme and origin are name
  # tokens, so every argument can be given in any order; bare numbers fill
  # count then gravity.
  if name == "confetti":
    var numsSeen = 0
    for idx in 1 ..< parts.len:
      let p = parts[idx]
      if confettiSchemeNames.find(p) >= 0:
        if result.args[2].isSome:
          raise newException(ActionParseError, "confetti: scheme given twice")
        result.args[2] = strV(akChoice, p)
      elif confettiOriginNames.find(p) >= 0:
        if result.args[3].isSome:
          raise newException(ActionParseError, "confetti: origin given twice")
        result.args[3] = strV(akChoice, p)
      elif p.startsWith("seed="):
        if result.args[4].isSome:
          raise newException(ActionParseError, "confetti: seed given twice")
        let v = pInt(p[5 .. ^1], "confetti seed")
        checkArg("confetti", "seed", v)
        result.args[4] = intV(v)
      elif p == "shimmer" or p == "no-shimmer":
        if result.args[5].isSome:
          raise newException(ActionParseError, "confetti: shimmer given twice")
        result.args[5] = flagV(p == "no-shimmer")
      elif p.len == 0 or p[0] notin {'0' .. '9', '-', '+', '.'}:
        # Not a number, so it was meant as one of the name tokens.
        raise newException(ActionParseError, &"confetti: unknown value: {p}" &
          didYouMean(p, @confettiSchemeNames & @confettiOriginNames &
            @["shimmer", "no-shimmer"]))
      elif numsSeen == 0:
        let n = pInt(p, "confetti count")
        checkArg("confetti", "count", n)
        result.args[0] = intV(n)
        numsSeen = 1
      elif numsSeen == 1:
        let gravity = pNum(p)
        checkArg("confetti", "gravity", float32(gravity))
        result.args[1] = numV(gravity)
        numsSeen = 2
      else:
        raise newException(ActionParseError, &"confetti: unexpected value: {p}")
    static: doAssert ix("confetti", "scheme") == 2 and ix("confetti", "no-shimmer") == 5
    return

  # aberration: per-channel chromatic split. Positional shorthand (no '=') is the
  # symmetric case `aberration[:h[:v[:edge]]]`; any `key=value` part switches to the
  # explicit per-channel form, which starts every channel at 0.
  if name == "aberration":
    proc toEdge(v: string): string {.raises: [ActionParseError].} =
      if v notin ["smear", "wrap"]:
        raise newException(ActionParseError, "aberration edge must be smear or wrap")
      v
    var keyword = false
    for idx in 1 ..< parts.len:
      if '=' in parts[idx]:
        keyword = true
        break

    if not keyword:
      # Symmetric: up to two bare pixel counts (h, v) plus an optional edge token.
      var nums: seq[int]
      for idx in 1 ..< parts.len:
        let p = parts[idx]
        if p == "smear" or p == "wrap":
          result.args[2] = strV(akChoice, toEdge(p))
        else:
          nums.add pInt(p, "aberration value")
      if nums.len > 2:
        raise newException(ActionParseError, "aberration takes at most h:v positional shifts")
      # Range-checked before negating, which overflows on low(int).
      if nums.len >= 1:
        checkArg("aberration", "h", nums[0])
        result.args[0] = intV(nums[0])
      if nums.len >= 2:
        checkArg("aberration", "v", nums[1])
        result.args[1] = intV(nums[1])
    else:
      # Every channel is written, at 0 where it isn't given, which is what
      # tells this form from the shorthand.
      static: doAssert ix("aberration", "bv") - ix("aberration", "rh") == 5 and
        ix("aberration", "gh") - ix("aberration", "rh") == 2
      for i in ix("aberration", "rh") .. ix("aberration", "bv"):
        result.args[i] = intV(0)
      for idx in 1 ..< parts.len:
        let p = parts[idx]
        let eq = p.find('=')
        if eq < 0:
          raise newException(ActionParseError, &"aberration: expected key=value, got {p}")

        let key = p[0 ..< eq]
        let value = p[eq + 1 .. ^1]
        if key == "edge":
          result.args[2] = strV(akChoice, toEdge(value))
        else:
          let n = pInt(value, "aberration value")
          case key
          of "rh": checkArg("aberration", "rh", n)
          of "rv": checkArg("aberration", "rv", n)
          of "gh": checkArg("aberration", "gh", n)
          of "gv": checkArg("aberration", "gv", n)
          of "bh": checkArg("aberration", "bh", n)
          of "bv": checkArg("aberration", "bv", n)
          else: raise newException(ActionParseError, &"Unknown aberration key: {key}")
          result.args[argIndex("aberration", key)] = intV(n)
    return

  # pos: overlay placement, each field an animatable ramp:
  #   pos:x:y   pos:x:y:scale   pos:0..600:300:1..0.5:ease=inout
  if name == "pos":
    if parts.len < 3:
      raise newException(ActionParseError, "pos requires x:y[:scale]")
    let x = pRamp(parts[1])
    let y = pRamp(parts[2])
    # parts[3] is the scale ramp unless it's the ease suffix.
    var idx = 3
    if parts.len > 3 and not parts[3].startsWith("ease="):
      let s = pRamp(parts[3])
      for v in s.kf: checkArg("pos", "scale", float32(v))
      result.args[2] = kfV(s)
      idx = 4
    # x/y are rounded to an int, which is UB out of range.
    for v in x.kf: checkArg("pos", "x", float32(v))
    for v in y.kf: checkArg("pos", "y", float32(v))
    result.args[0] = kfV(x)
    result.args[1] = kfV(y)
    result.easeTail(parts, idx, val)
    result.checkTimedEase()
    return

  # Animatable scalar effects: a value or keyframe ramp, with optional easing:
  #   zoom:2   zoom:1..2   zoom:1..0.5..1   zoom:1..2:ease=inout:2sec
  if name in animScalar and parts.len >= 2:
    let r = pRamp(parts[1])
    for v in r.kf:
      case name
      of "zoom": checkArg("zoom", "v", float32(v))
      of "opacity": checkArg("opacity", "v", float32(v))
      of "brightness": checkArg("brightness", "v", float32(v))
      of "blur": checkArg("blur", "v", float32(v)) # gblur's sigma tops out at 1024.
      else: discard
    result.args[0] = kfV(r)
    result.easeTail(parts, 2, val)
    result.checkTimedEase()
    return

  if name in ["speed", "varispeed"] and parts.len >= 2 and
      (".." in parts[1] or '@' in parts[1] or parts.len > 2):
    # A ramp across the section's media: speed:1..8, speed:1@0%..4@50%..1
    let r = pRamp(parts[1])
    for v in r.kf:
      checkSpeed(name, float32(v))
    for t in r.kt:
      if t.unit notin {kuAuto, kuPercent}:
        raise newException(ActionParseError,
          &"{name} keyframes are placed by percent of the section's media")
    result.args[0] = kfV(r)
    result.easeTail(parts, 2, val)
    if result.ease.isSome and result.ease.get.unit != duClip:
      raise newException(ActionParseError, &"{name} ramps ease across the whole section")
    return

  if parts.len == 2:
    let v = pNum(parts[1])
    case name
    of "speed", "varispeed":
      checkSpeed(name, float32(v))
      result.args[0] = some(ArgValue(kind: akKeyframes, kf: @[v]))
      return
    of "pitch":
      checkArg("pitch", "semitones", float32(v))
    of "brighthue": checkArg("brighthue", "v", float32(v))
    of "contrast": checkArg("contrast", "v", float32(v))
    of "saturation": checkArg("saturation", "v", float32(v))
    else:
      raise newException(ActionParseError, &"Unknown action: {actionDidYouMean(val)}")
    result.args[0] = numV(v)
    return

  raise newException(ActionParseError, &"Unknown action: {actionDidYouMean(val)}")

func has(s: ActionSpec, i: int): bool = i < s.args.len and s.args[i].isSome
func num(s: ActionSpec, i: int, default: float64): float64 =
  if s.has(i) and s.args[i].get.kind in {akNumber, akInteger}: s.args[i].get.num
  else: default
func str(s: ActionSpec, i: int): string =
  if s.has(i) and s.args[i].get.kind in {akColor, akChoice, akPath, akText}:
    s.args[i].get.str
  else: ""
func kf32(s: ActionSpec, i: int): seq[float32] =
  for v in s.args[i].get.kf: result.add float32(v)
func kts(s: ActionSpec, i: int): seq[KfTime] = s.args[i].get.kt

func packEase(a: var Action, s: ActionSpec) =
  if s.ease.isSome:
    let e = s.ease.get
    a.hasEase = true
    a.easeCurve = e.curve
    a.easeDurUnit = e.unit
    a.easeDur = float32(e.dur)

proc specColor(spec: string): RGBColor {.raises: [ActionParseError].} =
  try: parseColor(spec)
  except ValueError: raise newException(ActionParseError, &"Invalid color: {spec}")

proc toAction*(s: ActionSpec): Action {.raises: [ActionParseError].} =
  ## Pack a spec, which is trusted to be as parseActionSpec makes them.
  ## `cut`, `nil` and `ease` aren't actions on their own, so they're refused.
  case s.name
  of "invert": Action(kind: actInvert)
  of "hflip": Action(kind: actHflip)
  of "vflip": Action(kind: actVflip)
  of "loop": Action(kind: actLoop)
  of "erosion": Action(kind: actErosion)
  of "speed", "varispeed":
    var a = Action(kind: actSpeed, varispeed: s.name == "varispeed")
    let kf = s.kf32(0)
    if kf.len == 1 and s.ease.isNone:
      a.val = kf[0]
    else:
      a.sKf = kf
      a.sKt = s.kts(0)
      a.packEase(s)
      a.val = float32(a.meanSpeed)
    a
  of "zoom", "opacity", "blur", "brightness", "volume":
    var a = case s.name
      of "zoom": Action(kind: actZoom, kf: s.kf32(0), kt: s.kts(0))
      of "opacity": Action(kind: actOpacity, kf: s.kf32(0), kt: s.kts(0))
      of "blur": Action(kind: actBlur, kf: s.kf32(0), kt: s.kts(0))
      of "brightness": Action(kind: actBrightness, kf: s.kf32(0), kt: s.kts(0))
      else: Action(kind: actVolume, kf: s.kf32(0), kt: s.kts(0))
    a.packEase(s)
    a
  of "deesser":
    Action(kind: actDeesser, intensity: toUnorm16(float32(s.num(0, 0))),
      maxd: toUnorm16(float32(s.num(1, 0.5))), freq: toUnorm16(float32(s.num(2, 0.5))))
  of "highpass":
    Action(kind: actHighpass, cutoff: uint16(round(float32(s.num(0, 80)))))
  of "lowpass":
    Action(kind: actLowpass, cutoff: uint16(round(float32(s.num(0, 10000)))))
  of "dehum":
    Action(kind: actDehum, humHz: uint16(round(float32(s.num(0, 60)))),
      humHarmonics: uint8(float32(s.num(1, 4))))
  of "duck":
    Action(kind: actDuck, duckAmount: toUnorm16(float32(s.num(0, 0.85))),
      duckThresh: toUnorm16(float32(s.num(1, 0.04))),
      duckAttack: uint16(float32(s.num(2, 100))), duckRelease: uint16(float32(s.num(3, 500))))
  of "lens":
    if not s.has(0): Action(kind: actLens, k1: toSnorm16(-0.5'f32), k2: toSnorm16(0.0'f32))
    else: Action(kind: actLens, k1: toSnorm16(float32(s.num(0, 0))),
      k2: toSnorm16(float32(s.num(1, 0))))
  of "tone":
    let w = waveformNames.find(s.str(1))
    Action(kind: actTone, note: uint8(float32(s.num(0, 0))),
      wave: (if w < 0: wSine else: Waveform(w)))
  of "pitch":
    Action(kind: actPitch, pCents: int16(round(float32(s.num(0, 0)) * 100.0'f32)))
  of "brighthue":
    Action(kind: actLuv, brighthue: float32(s.num(0, 0)), contrast: luvContrastId,
      saturation: luvSaturationId)
  of "contrast":
    Action(kind: actLuv, brighthue: luvBrighthueId, contrast: float32(s.num(0, 1)),
      saturation: luvSaturationId)
  of "saturation":
    Action(kind: actLuv, brighthue: luvBrighthueId, contrast: luvContrastId,
      saturation: float32(s.num(0, 1)))
  of "rotate": Action(kind: actRotate, rStart: Unorm16(rotCode(float32(s.num(0, 0)))))
  of "turn": Action(kind: actTurn, tDeg: float32(s.num(0, 0)))
  of "scale":
    let w = float32(s.num(0, 1))
    Action(kind: actScale, tScaleW: w, tScaleH: float32(s.num(1, float64(w))),
      tUniform: not s.has(1))
  of "spin":
    Action(kind: actSpin, sStart: Unorm16(rotCode(float32(s.num(0, 0)))),
      sRate: float32(s.num(1, 0)))
  of "convolve": Action(kind: actConvolve, irPath: s.str(0))
  of "drawbox":
    Action(kind: actDrawbox, dbX: int32(s.num(0, 0)), dbY: int32(s.num(1, 0)),
      dbW: int32(s.num(2, 1)), dbH: int32(s.num(3, 1)), dbColor: specColor(s.str(4)))
  of "colorkey", "chromakey":
    let similar = max(toUnorm16(float32(s.num(1, 0.25))), toUnorm16(0.01'f32))
    let blend = toUnorm16(float32(s.num(2, 0)))
    let color = specColor(s.str(0))
    if s.name == "colorkey": Action(kind: actColorKey, color: color, similar: similar,
      blend: blend)
    else: Action(kind: actChromaKey, color: color, similar: similar, blend: blend)
  of "choke": Action(kind: actChoke, chokeN: uint8(s.num(0, 1)))
  of "pixelate":
    var a = Action(kind: actPixelate, pixWKf: @[16.0'f32])
    if s.has(0): (a.pixWKf, a.pixWKt) = (s.kf32(0), s.kts(0))
    if s.has(1): (a.pixHKf, a.pixHKt) = (s.kf32(1), s.kts(1))
    else: (a.pixHKf, a.pixHKt) = (a.pixWKf, a.pixWKt)
    a.packEase(s)
    a
  of "pos":
    var a = Action(kind: actPos, pxKf: s.kf32(0), pyKf: s.kf32(1), pxKt: s.kts(0),
      pyKt: s.kts(1), pscaleKf: @[1.0'f32])
    if s.has(2): (a.pscaleKf, a.pscaleKt) = (s.kf32(2), s.kts(2))
    a.packEase(s)
    a
  of "confetti":
    let scheme = confettiSchemeNames.find(s.str(2))
    let origin = confettiOriginNames.find(s.str(3))
    Action(kind: actConfetti, cCount: uint16(s.num(0, float64(confettiCountId))),
      cGravity: float32(s.num(1, float64(confettiGravityId))),
      cScheme: (if scheme < 0: csParty else: ConfettiScheme(scheme)),
      cOrigin: (if origin < 0: confettiOriginId else: ConfettiOrigin(origin)),
      cShimmer: not (s.has(5) and s.args[5].get.on), cSeed: uint16(s.num(4, 0)))
  of "aberration":
    var ch: array[6, int]
    if s.has(ix("aberration", "rh")):
      for i in 0 ..< 6: ch[i] = int(s.num(ix("aberration", "rh") + i, 0))
    else:
      let h = int(s.num(0, 5))
      let v = int(s.num(1, 0))
      ch = [h, v, 0, 0, -h, -v]
    Action(kind: actAberration, abRh: int8(ch[0]), abRv: int8(ch[1]), abGh: int8(ch[2]),
      abGv: int8(ch[3]), abBh: int8(ch[4]), abBv: int8(ch[5]), abWrap: s.str(2) == "wrap")
  of "mask", "confine":
    let poly = ix("mask", "poly")
    let inv = s.has(ix("mask", "invert"))
    let feather = uint8(s.num(ix("mask", "feather"), 0))
    if s.has(poly):
      var a = Action(kind: (if s.name == "mask": actMaskPoly else: actConfinePoly))
      let pts = s.args[poly].get.pts
      for i in 0 ..< pts.len div 2:
        a.mPolyXs.add pts[2 * i]
        a.mPolyYs.add pts[2 * i + 1]
      a.mFeather = feather
      a.mInvert = inv
      a
    elif not s.has(0):
      Action(kind: actConfine, mReset: true)
    else:
      var a = Action(kind: (if s.name == "mask": actMask else: actConfine))
      a.mX = int32(s.num(0, 0))
      a.mY = int32(s.num(1, 0))
      a.mW = int32(s.num(2, 1))
      a.mH = int32(s.num(3, 1))
      a.mRadius = int32(s.num(4, 0))
      a.mFeather = feather
      a.mInvert = inv
      a
  of "burn", "text":
    var a = if s.name == "text": Action(kind: actText) else: Action(kind: actBurn)
    a.burnFile = s.str(0)
    a.burnFont = s.str(ix("burn", "font"))
    a.burnSize = float32(s.num(ix("burn", "size"), 0))
    a.burnFace = s.str(ix("burn", "face"))
    a.burnWeight = uint16(s.num(ix("burn", "weight"), 0))
    for (k, part) in [(3, bpColor), (4, bpOutline), (5, bpBg)]:
      if s.has(k):
        a.burnSet.incl part
        a.burnColors[part] = parseRgba(s.str(k), &"{s.name} {subsKeys[k]}")
    if s.has(ix("burn", "align")):
      a.burnAlign = uint8(alignNames.find(s.str(ix("burn", "align"))) + 1)
    if s.name == "text":
      a.burnVertical = s.has(ix("text", "vertical"))
      a.burnAss = s.has(ix("text", "ass"))
    a
  else:
    raise newException(ActionParseError, &"Unknown action: {actionDidYouMean(s.name)}")

func parseAction*(val: string): Action {.raises: [ActionParseError].} =
  toAction(parseActionSpec(val))

proc meanSpeed*(s: ActionSpec): float64 {.raises: [ActionParseError].} =
  ## A speed or varispeed ramp's mean speed over its media, as the CLI packs it.
  if s.name notin ["speed", "varispeed"]:
    raise newException(ActionParseError, &"{s.name} has no speed")
  meanSpeed(toAction(s))

proc normalizedColor*(spec: string): string {.raises: [ActionParseError].} =
  ## A color as #rrggbb, or #rrggbbaa when it's see-through; yuv#yyuuvv stays YUV.
  if spec.startsWith("#") and spec.len == 9:
    return rgbaStr(parseRgba(spec, "color"))
  specColor(spec).toString


func easeSuffix(a: Action): string =
  ## The trailing ":ease=..." for an animated action, or "" if it has none.
  if not a.hasEase: return ""
  result = &":ease={easeNames[a.easeCurve]}"
  case a.easeDurUnit
  of duClip: discard
  of duSec: result.add &":{a.easeDur}sec"
  of duFrames: result.add &":{a.easeDur}"

func rampStr(values: seq[string], kt: seq[KfTime]): string =
  ## Formatted keyframes as "a..b..c", each with its time when it has one.
  var parts = values
  if kt.len == values.len:
    for i, t in kt:
      case t.unit
      of kuAuto: discard
      of kuPercent: parts[i].add &"@{t.at}%"
      of kuSec: parts[i].add &"@{t.at}sec"
      of kuFrames: parts[i].add &"@{t.at}"
  parts.join("..")

func kfStr(a: Action): string =
  ## Keyframes as "a..b..c", formatted in each effect's native value type.
  var parts: seq[string]
  for v in a.kf:
    case a.kind
    of actOpacity: parts.add $toUnorm16(v)
    of actBrightness: parts.add $toSnorm16(v)
    else: parts.add $v
  rampStr(parts, a.kt)

func maskStr(a: Action, name: string): string =
  result = &"{name}:{a.mX}:{a.mY}:{a.mW}:{a.mH}"
  # radius (0 = rect, default) only needs emitting when set or to hold feather's
  # positional slot; feather then follows so both round-trip positionally.
  if a.mRadius != 0 or a.mFeather > 0'u8: result.add &":{a.mRadius}"
  if a.mFeather > 0'u8: result.add &":{a.mFeather}"
  if a.mInvert: result.add ":invert"

func maskPolyStr(a: Action, name: string): string =
  var nums: seq[string]
  for i in 0 ..< a.mPolyXs.len:
    nums.add $a.mPolyXs[i]
    nums.add $a.mPolyYs[i]
  result = &"""{name}:poly={nums.join("/")}"""
  if a.mFeather > 0'u8: result.add &":feather={a.mFeather}"
  if a.mInvert: result.add ":invert"

func numStr(v: float64): string =
  if v == floor(v) and abs(v) < 1e15: $int64(v) else: $v

func rampStr(v: ArgValue): string =
  var parts: seq[string]
  for x in v.kf: parts.add numStr(x)
  rampStr(parts, v.kt)

func durStr(dur: float64, unit: DurUnit): string =
  case unit
  of duClip: ""
  of duSec: numStr(dur) & "sec"
  of duFrames: numStr(dur)

func `$`*(s: ActionSpec): string =
  ## The action's text, which parseActionSpec reads back to an equal spec.
  func val(v: ArgValue): string =
    case v.kind
    of akNumber, akInteger: numStr(v.num)
    of akKeyframes: rampStr(v)
    of akColor, akChoice, akPath, akText: v.str
    of akDuration: durStr(v.dur, v.durUnit)
    of akFlag: ""
    of akPoints: v.pts.mapIt($it).join("/")
  template a(i: int): ArgValue = s.args[i].get

  result = s.name
  case s.name
  of "burn", "text":
    if s.name == "text": result = "text:" & textPart(s.str(0))
    elif s.has(0): result &= ":" & s.str(0)
    for k in 1 ..< subsKeys.len:
      if s.has(k): result &= &":{subsKeys[k]}={val(a(k))}"
    if s.name == "text":
      if s.has(ix("text", "vertical")): result &= ":vertical"
      if s.has(ix("text", "ass")): result &= ":ass"
  of "mask", "confine":
    let feather = ix("mask", "feather")
    if s.has(ix("mask", "poly")):
      result &= ":poly=" & val(a(ix("mask", "poly")))
      if s.has(feather): result &= ":feather=" & val(a(feather))
    elif s.has(0):
      for i in 0 ..< 4:
        if s.has(i): result &= ":" & val(a(i))
      if s.has(4):
        result &= ":" & val(a(4))
        if s.has(feather): result &= ":" & val(a(feather))
      elif s.has(feather): result &= ":feather=" & val(a(feather))
    if s.has(ix("mask", "invert")): result &= ":invert"
  of "spin":
    if s.has(0) and s.has(1): result &= &":{val(a(0))}/{val(a(1))}"
  of "aberration":
    if s.has(ix("aberration", "rh")):
      var ps: seq[string]
      for key in ["rh", "rv", "gh", "gv", "bh", "bv"]:
        let v = s.num(argIndex("aberration", key), 0)
        if v != 0: ps.add &"{key}={numStr(v)}"
      if s.has(2): ps.add "edge=" & s.str(2)
      if ps.len == 0: ps.add "rh=0"
      result &= ":" & ps.join(":")
    else:
      for i in 0 ..< 3:
        if s.has(i): result &= ":" & val(a(i))
  of "confetti":
    for i in 0 ..< 4:
      if s.has(i): result &= ":" & val(a(i))
    if s.has(4): result &= ":seed=" & val(a(4))
    if s.has(5) and a(5).kind == akFlag:
      result &= (if a(5).on: ":no-shimmer" else: ":shimmer")
  else:
    for i in 0 ..< s.args.len:
      if s.has(i): result &= ":" & val(a(i))
  if s.ease.isSome:
    let e = s.ease.get
    result &= ":ease=" & easeNames[e.curve]
    if e.unit != duClip: result &= ":" & durStr(e.dur, e.unit)

when not defined(nimscript):
  func `$`*(act: Action): string =
    case act.kind
    of actInvert: "invert"
    of actHflip: "hflip"
    of actVflip: "vflip"
    of actLoop: "loop"
    of actErosion: "erosion"
    of actSpeed:
      let name = (if act.varispeed: "varispeed" else: "speed")
      if act.sKf.len == 0: &"{name}:{act.val}"
      else:
        var parts: seq[string]
        for v in act.sKf: parts.add $v
        &"{name}:{rampStr(parts, act.sKt)}{easeSuffix(act)}"
    of actVolume: &"volume:{kfStr(act)}{easeSuffix(act)}"
    of actDeesser: &"deesser:{act.intensity}:{act.maxd}:{act.freq}"
    of actHighpass: &"highpass:{act.cutoff}"
    of actLowpass: &"lowpass:{act.cutoff}"
    of actDehum: &"dehum:{act.humHz}:{act.humHarmonics}"
    of actPitch: &"pitch:{act.pCents.float32 / 100.0'f32}"
    of actTone:
      if act.wave == wSine: &"tone:{act.note}"
      else: &"tone:{act.note}:{waveformNames[act.wave]}"
    of actDuck: &"duck:{act.duckAmount}:{act.duckThresh}:{act.duckAttack}:{act.duckRelease}"
    of actConvolve: &"convolve:{act.irPath}"
    of actZoom: &"zoom:{kfStr(act)}{easeSuffix(act)}"
    of actOpacity: &"opacity:{kfStr(act)}{easeSuffix(act)}"
    of actBlur: &"blur:{kfStr(act)}{easeSuffix(act)}"
    of actBrightness: &"brightness:{kfStr(act)}{easeSuffix(act)}"
    of actRotate: &"rotate:{rotDeg(act.rStart)}"
    of actSpin: &"spin:{rotDeg(act.sStart)}/{act.sRate}"
    of actScale:
      if act.tUniform: &"scale:{act.tScaleW}" else: &"scale:{act.tScaleW}:{act.tScaleH}"
    of actTurn: &"turn:{act.tDeg}"
    of actBurn, actText:
      var s = if act.kind == actText: "text:" & textPart(act.burnFile)
              elif act.burnFile.len > 0: "burn:" & act.burnFile
              else: "burn"
      if act.burnFont.len > 0: s &= ":font=" & act.burnFont
      if act.burnSize > 0: s &= &":size={act.burnSize}"
      for (part, key) in [(bpColor, "color"), (bpOutline, "outline"), (bpBg, "bg")]:
        if part in act.burnSet: s &= &":{key}={rgbaStr(act.burnColors[part])}"
      if act.burnAlign in 1'u8 .. 9'u8: s &= ":align=" & alignNames[act.burnAlign]
      if act.burnFace.len > 0: s &= ":face=" & act.burnFace
      if act.burnWeight > 0: s &= &":weight={act.burnWeight}"
      if act.burnVertical: s &= ":vertical"
      if act.burnAss: s &= ":ass"
      s
    of actLuv:
      var parts: seq[string]
      let hue = act.brighthue
      if hue != luvBrighthueId: parts.add &"brighthue:{hue}"
      if act.contrast != luvContrastId: parts.add &"contrast:{act.contrast}"
      if act.saturation != luvSaturationId: parts.add &"saturation:{act.saturation}"
      if parts.len == 0: "brighthue:0.0" else: parts.join(",")
    of actLens: &"lens:{act.k1}:{act.k2}"
    of actDrawbox: &"drawbox:{act.dbX}:{act.dbY}:{act.dbW}:{act.dbH}:{act.dbColor.toString}"
    of actPos:
      var xs, ys, ss: seq[string]
      for v in act.pxKf: xs.add $int(round(v))   # x/y are whole pixels
      for v in act.pyKf: ys.add $int(round(v))
      for v in act.pscaleKf: ss.add $v
      &"pos:{rampStr(xs, act.pxKt)}:{rampStr(ys, act.pyKt)}:" &
        &"{rampStr(ss, act.pscaleKt)}{easeSuffix(act)}"
    of actColorKey, actChromaKey:
      let name = (if act.kind == actColorKey: "colorkey" else: "chromakey")
      &"{name}:{act.color.toString}:{act.similar}:{act.blend}"
    of actChoke: &"choke:{act.chokeN}"
    of actAberration:
      # A symmetric, green-free, smear split round-trips as the positional shorthand.
      if not act.abWrap and act.abGh == 0 and act.abGv == 0 and act.abRh >= 0 and
          act.abBh == -act.abRh and act.abBv == -act.abRv:
        if act.abRv == 0: &"aberration:{act.abRh}"
        else: &"aberration:{act.abRh}:{act.abRv}"
      else:
        var ps: seq[string]
        if act.abRh != 0: ps.add &"rh={act.abRh}"
        if act.abRv != 0: ps.add &"rv={act.abRv}"
        if act.abGh != 0: ps.add &"gh={act.abGh}"
        if act.abGv != 0: ps.add &"gv={act.abGv}"
        if act.abBh != 0: ps.add &"bh={act.abBh}"
        if act.abBv != 0: ps.add &"bv={act.abBv}"
        if act.abWrap: ps.add "edge=wrap"
        &"""aberration:{ps.join(":")}"""
    of actMask: maskStr(act, "mask")
    of actConfine:
      if act.mReset: "confine" else: maskStr(act, "confine")
    of actMaskPoly: maskPolyStr(act, "mask")
    of actConfinePoly: maskPolyStr(act, "confine")
    of actPixelate:
      var ws, hs: seq[string]
      for v in act.pixWKf: ws.add $int(round(v))   # block sizes are whole px
      for v in act.pixHKf: hs.add $int(round(v))
      let w = rampStr(ws, act.pixWKt)
      let h = rampStr(hs, act.pixHKt)
      let sizes = (if w == h: w else: &"{w}:{h}")
      &"pixelate:{sizes}{easeSuffix(act)}"
    of actConfetti:
      &"confetti:{act.cCount}:{act.cGravity}:" &
        &"{confettiSchemeNames[act.cScheme]}:{confettiOriginNames[act.cOrigin]}" &
        (if act.cSeed == 0'u16: "" else: &":seed={act.cSeed}") &
        (if act.cShimmer: "" else: ":no-shimmer")

  # atf-8's layout, one description per kind: `code` walks an action's fields
  # in their packed order, and the codec's mode sizes, writes, or reads them,
  # so the three can't disagree. Sizing and writing only read the action. The
  # mode is static, so each is compiled without the others' branches.
  type
    CodecMode = enum cmSize, cmWrite, cmRead
    Codec[M: static CodecMode] = object
      base: ptr UncheckedArray[uint8]
      head, pos: int # the action's header byte, and the next field
      tooMany, unpaired: bool # ramps that can't be packed, found when sizing
    KfStore = enum ksF32, ksUnorm16, ksSnorm16, ksPixel

  proc raw[M, T](c: var Codec[M], v: var T) =
    case M
    of cmSize: discard
    of cmWrite: copyMem(addr c.base[c.pos], addr v, sizeof(T))
    of cmRead: copyMem(addr v, addr c.base[c.pos], sizeof(T))
    c.pos += sizeof(T)

  proc byte8[M; T: enum](c: var Codec[M], v: var T) =
    # A bare Nim enum is int-sized, so it's narrowed to a byte.
    var b = uint8(ord(v))
    c.raw(b)
    if M == cmRead: v = T(b)

  proc bit[M](c: var Codec[M], at: int, v: var bool, mask: uint8) =
    ## `v` as the `mask` bit of the byte at `at`, which holds another field.
    case M
    of cmSize: discard
    of cmWrite:
      if v: c.base[at] = c.base[at] or mask
    of cmRead: v = (c.base[at] and mask) != 0'u8

  proc bits[M](c: var Codec[M], fields: openArray[(ptr bool, uint8)]) =
    ## Bools in a byte of their own, each its mask's bit.
    var b = 0'u8
    if M == cmWrite:
      for (f, m) in fields:
        if f[]: b = b or m
    c.raw(b)
    if M == cmRead:
      for (f, m) in fields: f[] = (b and m) != 0'u8

  proc str16[M](c: var Codec[M], s: var string) =
    var n = uint16(s.len)
    c.raw(n)
    if M == cmRead: s = newString(n.int)
    if n > 0:
      case M
      of cmSize: discard
      of cmWrite: copyMem(addr c.base[c.pos], addr s[0], n.int)
      of cmRead: copyMem(addr s[0], addr c.base[c.pos], n.int)
    c.pos += n.int

  proc rgb[M](c: var Codec[M], col: var RGBColor) =
    c.bit(c.head, col.yuv, yuvFlag)
    c.raw(col.red)
    c.raw(col.green)
    c.raw(col.blue)

  proc ease[M](c: var Codec[M], a: var Action) =
    ## An animated action's easing, flagged in its header.
    c.bit(c.head, a.hasEase, easeFlag)
    if a.hasEase:
      c.byte8(a.easeCurve)
      c.byte8(a.easeDurUnit)
      c.raw(a.easeDur)

  proc ramp[M](c: var Codec[M], kf: var seq[float32], kt: var seq[KfTime],
      store: KfStore) =
    ## Keyframes behind a one-byte count. A timed ramp is marked by a zero
    ## before its count, and is followed by each keyframe's unit and time. An
    ## untimed ramp's count is never zero: an empty ramp takes the mark too,
    ## with no times.
    if M == cmSize:
      c.tooMany = c.tooMany or kf.len > 255
      c.unpaired = c.unpaired or kt.len notin [0, kf.len]
    let timed =
      if M == cmRead: c.base[c.pos] == 0'u8
      else: kt.len > 0 or kf.len == 0
    if timed:
      var mark = 0'u8
      c.raw(mark)
    var n = uint8(min(kf.len, 255))
    c.raw(n)
    if M == cmRead:
      kf.setLen(n.int)
      if timed: kt.setLen(n.int)
    for v in kf.mitems:
      case store
      of ksF32: c.raw(v)
      of ksUnorm16:
        var u = toUnorm16(v)
        c.raw(u)
        if M == cmRead: v = u.toFloat32
      of ksSnorm16:
        var s = toSnorm16(v)
        c.raw(s)
        if M == cmRead: v = s.toFloat32
      of ksPixel:
        var u = pixCode(v)
        c.raw(u)
        if M == cmRead: v = u.float32
    for t in kt.mitems:
      c.byte8(t.unit)
      c.raw(t.at)

  proc code[M](c: var Codec[M], a: var Action) =
    case a.kind
    of actInvert, actHflip, actVflip, actLoop, actErosion: discard
    of actChoke: c.raw(a.chokeN)
    of actRotate: c.raw(a.rStart)
    of actScale:
      c.raw(a.tScaleW)
      c.raw(a.tScaleH)
      c.bits([(addr a.tUniform, 1'u8)])
    of actTurn: c.raw(a.tDeg)
    of actPitch: c.raw(a.pCents)
    of actTone:
      c.raw(a.note)
      c.byte8(a.wave)
    of actLens:
      c.raw(a.k1)
      c.raw(a.k2)
    of actSpeed:
      c.bit(c.head, a.varispeed, varispeedFlag)
      if M == cmSize and a.sKf.len == 0:
        c.unpaired = c.unpaired or a.sKt.len > 0
      # A ramp stores its mean negated, then its easing and keyframes.
      var v = (if a.sKf.len > 0: -a.val else: a.val)
      c.raw(v)
      if M == cmRead: a.val = (if v < 0: -v else: v)
      if (if M == cmRead: v < 0 else: a.sKf.len > 0):
        c.bits([(addr a.hasEase, 1'u8)])
        if a.hasEase: c.byte8(a.easeCurve)
        c.ramp(a.sKf, a.sKt, ksF32)
    of actDeesser:
      c.raw(a.intensity)
      c.raw(a.maxd)
      c.raw(a.freq)
    of actHighpass, actLowpass: c.raw(a.cutoff)
    of actDehum:
      c.raw(a.humHz)
      c.raw(a.humHarmonics)
    of actDuck:
      c.raw(a.duckAmount)
      c.raw(a.duckThresh)
      c.raw(a.duckAttack)
      c.raw(a.duckRelease)
    of actConvolve: c.str16(a.irPath)
    of actBurn, actText:
      c.bit(c.head, a.burnVertical, verticalFlag)
      c.str16(a.burnFile)
      c.str16(a.burnFont)
      c.str16(a.burnFace)
      c.raw(a.burnWeight)
      c.raw(a.burnSize)
      c.raw(a.burnSet)
      let alignAt = c.pos
      c.raw(a.burnAlign)
      c.bit(alignAt, a.burnAss, assFlag)
      if M == cmRead: a.burnAlign = a.burnAlign and not assFlag
      c.raw(a.burnColors)
    of actSpin:
      c.raw(a.sStart)
      c.raw(a.sRate)
    of actColorKey, actChromaKey:
      c.rgb(a.color)
      c.raw(a.similar)
      c.raw(a.blend)
    of actMask, actConfine:
      c.bits([(addr a.mInvert, 0x1'u8), (addr a.mReset, 0x2'u8)])
      c.raw(a.mFeather)
      c.raw(a.mX)
      c.raw(a.mY)
      c.raw(a.mW)
      c.raw(a.mH)
      c.raw(a.mRadius)
    of actMaskPoly, actConfinePoly:
      c.bits([(addr a.mInvert, 0x1'u8)])
      c.raw(a.mFeather)
      var n = uint16(a.mPolyXs.len)
      c.raw(n)
      if M == cmRead:
        a.mPolyXs.setLen(n.int)
        a.mPolyYs.setLen(n.int)
      for k in 0 ..< n.int:
        c.raw(a.mPolyXs[k])
        c.raw(a.mPolyYs[k])
    of actPixelate:
      c.ease(a)
      c.ramp(a.pixWKf, a.pixWKt, ksPixel)
      c.ramp(a.pixHKf, a.pixHKt, ksPixel)
    of actConfetti:
      c.raw(a.cCount)
      c.raw(a.cGravity)
      var flags = uint8(ord(a.cScheme)) or (uint8(ord(a.cOrigin)) shl originShift) or
        (if a.cShimmer: shimmerFlag else: 0'u8)
      c.raw(flags)
      if M == cmRead:
        a.cScheme = ConfettiScheme((flags and schemeMask).int)
        a.cOrigin = ConfettiOrigin(((flags shr originShift) and originMask).int)
        a.cShimmer = (flags and shimmerFlag) != 0'u8
      c.raw(a.cSeed)
    of actAberration:
      c.raw(a.abRh)
      c.raw(a.abRv)
      c.raw(a.abGh)
      c.raw(a.abGv)
      c.raw(a.abBh)
      c.raw(a.abBv)
      c.bits([(addr a.abWrap, 1'u8)])
    of actLuv:
      c.raw(a.brighthue)
      c.raw(a.contrast)
      c.raw(a.saturation)
    of actPos:
      c.ease(a)
      c.ramp(a.pxKf, a.pxKt, ksF32)
      c.ramp(a.pyKf, a.pyKt, ksF32)
      c.ramp(a.pscaleKf, a.pscaleKt, ksF32)
    of actDrawbox:
      c.raw(a.dbX)
      c.raw(a.dbY)
      c.raw(a.dbW)
      c.raw(a.dbH)
      c.rgb(a.dbColor)
    of actZoom, actBlur, actVolume:
      c.ease(a)
      c.ramp(a.kf, a.kt, ksF32)
    of actOpacity:
      c.ease(a)
      c.ramp(a.kf, a.kt, ksUnorm16)
    of actBrightness:
      c.ease(a)
      c.ramp(a.kf, a.kt, ksSnorm16)

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

  proc decodeAt(base: ptr UncheckedArray[uint8], i: var int): Action =
    # The bytes come from our own pack (newActions), so the kind byte is
    # always a declared ActionKind despite the enum's reserved holes.
    {.push warning[HoleEnumConv]: off.}
    let kind = ActionKind((base[i] and 0x7f'u8).int)
    {.pop.}
    result = Action(kind: kind)
    var c = Codec[cmRead](base: base, head: i, pos: i + 1)
    c.code(result)
    i = c.pos

  iterator items*(a: Actions): Action =
    if int(a) > 1:
      let n = a.len
      let base = cast[ptr UncheckedArray[uint8]](int(a) + sizeof(uint16))
      var i = 0
      while i < n:
        yield decodeAt(base, i)

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

  func hash*(a: Actions): Hash =
    ## Over the packed bytes, as `==` compares them.
    let ia = int(a)
    if ia <= 1: return hash(ia)
    let p = cast[ptr UncheckedArray[uint8]](ia + sizeof(uint16))
    hash(toOpenArray(p, 0, a.len - 1))

  proc newActions*(list: openArray[Action]): Actions =
    if list.len == 0: return aNil
    var total = 0
    for a in list:
      # Sizing only reads the action, so it goes by address, not a copy.
      var c = Codec[cmSize](pos: 1)
      c.code((addr a)[])
      # Keyframe counts are packed into one byte; a wrapped count would
      # misalign every later field on decode.
      if c.tooMany:
        raise newException(ActionParseError, "Too many keyframes (max 255)")
      # Times pair with keyframes one to one; packing trusts that.
      if c.unpaired:
        raise newException(ActionParseError, "Keyframe times don't match the keyframes")
      total += c.pos
    if total > 65535:
      raise newException(ActionParseError, "atf-8 buffer overflow: too many actions")
    let p = alloc(sizeof(uint16) + total)
    cast[ptr uint16](p)[] = uint16(total)
    let base = cast[ptr UncheckedArray[uint8]](cast[int](p) + sizeof(uint16))
    var i = 0
    for a in list:
      base[i] = uint8(ord(a.kind))
      var c = Codec[cmWrite](base: base, head: i, pos: i + 1)
      c.code((addr a)[])
      i = c.pos
    Actions(cast[int](p))

  proc parseActions*(val: string): Actions =
    var list: seq[Action]
    # An `ease:` token sets a pending envelope that is stamped onto the animated
    # actions that follow it (until another `ease` overrides it).
    var pendActive = false
    var pendCurve = easeLinear
    var pendUnit = duClip
    var pendDur = 0.0'f32
    for part in splitUnescaped(val.strip(), ',', textOnly = true):
      let trimmedPart = part.strip()
      if trimmedPart != "nil":
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
        else:
          var action = parseAction(trimmedPart)
          if pendActive and action.kind in {actZoom, actBlur, actOpacity, actBrightness,
              actVolume, actPos, actPixelate} and not action.hasEase:
            action.hasEase = true
            action.easeCurve = pendCurve
            # Timed keyframes keep their own timing; they take only the curve.
            if not action.isTimed:
              action.easeDurUnit = pendUnit
              action.easeDur = pendDur
          # Adjacent-fusion: collapse this actLuv into previous one if it's also actLuv.
          # Per field, the non-identity value wins; later wins on genuine conflicts.
          if action.kind == actLuv and list.len > 0 and list[^1].kind == actLuv:
            var prev = list[^1]
            if action.brighthue != luvBrighthueId: prev.brighthue = action.brighthue
            if action.contrast != luvContrastId: prev.contrast = action.contrast
            if action.saturation != luvSaturationId: prev.saturation = action.saturation
            list[^1] = prev
          else:
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
        discard
      elif a.kind == actLoop:
        hasLoop = true
      else:
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
