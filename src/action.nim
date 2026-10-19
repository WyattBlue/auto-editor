import std/[algorithm, math, sequtils, strformat, strutils, options]
import ./util/[color, suggest]
import ./lib/[dnorm16, escape]

template writeAt(baseBuffer: auto, index: int, offset: int, val: untyped) =
  var temp = val
  copyMem(addr baseBuffer[index + offset], addr temp, sizeof(temp))

type
  # The order is part of the API
  ActionKind* = enum
    actSpeed,
    # Can add 3 more [VA] actions
    actVolume = 4,
    actDeesser, actDuck, actPitch, actTone, actConvolve,
    # Can add 10 more [A] actions
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
    bpColor,   # the text
    bpOutline, # its outline
    bpBg       # a box behind each subtitle

  DurUnit* = enum  # how an ease duration is measured
    duClip,    # the whole clip/section (the default)
    duSec,     # seconds
    duFrames   # timeline frames

  KfUnit* = enum  # where a timed keyframe sits; the order is part of atf-8
    kuAuto,    # between its timed neighbors (the first and last: the section's ends)
    kuPercent, # percent of the section
    kuSec,     # seconds from the section's start
    kuFrames   # timeline frames from the section's start
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
    of actScale:
      tScaleW*, tScaleH*: float32 # about the center
      tUniform*: bool        # one value for both, as `scale:v` says
    of actTurn:
      tDeg*: float32         # clockwise about the center, without growing the frame
    of actBurn, actText:
      burnFile*: string      # the subtitles: an .srt, .ass, or a file with a text stream
      burnFont*: string      # a font file to draw them with; "" keeps their own
      burnSize*: float32     # text height, percent of the frame's; 0 keeps their own
      burnSet*: set[BurnPart] # which of burnColors replace the subtitles' own
      burnColors*: array[BurnPart, uint32] # 0xRRGGBBAA
      burnAlign*: uint8
      burnVertical*: bool
    of actSpin:
      sStart*: Unorm16       # circular [0, 360) start angle
      sRate*: float32        # spin rate in degrees/second (continuous)
    of actLens:
      k1*, k2*: Snorm16
    of actSpeed:
      val*: float32
      varispeed*: bool
    of actZoom, actBlur, actOpacity, actBrightness, actVolume:
      kf*: seq[float32]      # keyframes in native units; len >= 1
      kt*: seq[KfTime]       # each keyframe's time, or empty: spread evenly
    of actDeesser:
      intensity*, maxd*, freq*: Unorm16
    of actPitch:
      # Semitones x 100. Cent buckets round-trip as exact decimal semitones
      pCents*: int16
    of actTone:
      note*: uint8           # MIDI note number; 69 = A4 = 440 Hz
      wave*: Waveform        # timbre (sine unless given)
    of actConvolve:
      irPath*: string        # impulse response file, or a folder of H_LL/H_LR/H_RL/H_RR.wav
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
      pxKt*, pyKt*, pscaleKt*: seq[KfTime] # as `kt`
    of actColorKey, actChromaKey:
      color*: RGBColor
      similar*, blend*: Unorm16
    of actAberration:
      abRh*, abRv*, abGh*, abGv*, abBh*, abBv*: int8
      abWrap*: bool          # edge: wrap around (true) vs smear the border (false)
    of actMask, actConfine, actMaskPoly, actConfinePoly:
      # `mask` shapes the clip's alpha; `confine` restricts following effects to
      # this region. Shared geometry, in canvas pixels like drawbox.
      mRadius*: int32        # corner radius px: 0=rect, >0=rounded rect, -1=ellipse
      mReset*: bool          # confine bare: reset to full frame (region fields unused)
      mInvert*: bool         # swap inside/outside
      mFeather*: uint8       # soft-edge width in px (0 = hard edge)
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
  ActionFlag* = enum   # capabilities of an action
    afAudio,
    afVideo,
    afAnimatable       # value can be a keyframe ramp (`a..b..c`) with easing
    afGenerator        # may stand in for a file in `add:`, painting a clear canvas
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

const
  easeFlag = 0x80'u8  # high bit of an animated action's atf-8 header byte
  varispeedFlag = 0x80'u8  # same bit on a speed action's header byte
  verticalFlag = 0x80'u8
  schemeMask = 0x07'u8
  originMask = 0x03'u8
  originShift = 3
  shimmerFlag = 0x80'u8
static:
  assert ord(high(ConfettiScheme)) <= schemeMask.int, "scheme outgrew 3 bits"
  assert ord(high(ConfettiOrigin)) <= originMask.int, "origin outgrew 2 bits"

const
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
    help: "Change the playback speed while preserving pitch via time-stretching. 1.0 = unchanged, 2.0 = twice as fast, 0.5 = half speed."),
  ActionDef(name: "varispeed", flags: {afAudio, afVideo}, argSpec: "float32", range: rng(0.2, 100.0),
    help: "Change the playback speed by resampling, so pitch shifts along with it, like analog tape or vinyl. 1.0 = unchanged, 2.0 = twice as fast and an octave higher."),
  ActionDef(name: "ease", flags: {afAudio, afVideo}, argSpec: "curve[:duration]",
    help: """
Set the easing for the animated actions that follow it (until another `ease` overrides it); equivalent to adding `:ease=curve` to each. `curve` is one of `linear`, `in`, `out`, or `inout`.
The optional `duration` (e.g. `2sec` or a bare frame count) is how long the animation takes before holding at its end value; omitted, it spans the whole section. Example: `ease:inout,zoom:1..2`.
Keyframes can also say when they are, as `value@time`: a bare frame count, `sec`, or `%` of the section, e.g. `zoom:1@0..2@1.5sec..1@100%`. The value holds before the first and after the last, a keyframe without a time sits evenly between its timed neighbors, and the curve eases each step between keyframes. A duration can't be given with timed keyframes."""),
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
  ActionDef(name: "pitch", flags: {afAudio}, argSpec: "semitones", range: rng(-24.0, 24.0),
    help: "Shift the pitch of the section without changing its speed. `12` is one octave up, `-12` one octave down, `0` leaves it unchanged, and fractional values work (`pitch:0.5` is a quarter tone). Implemented by resampling and then time-stretching back with ffmpeg's `asetrate` and `atempo` filters, so large shifts pick up the usual time-stretch artifacts. To change speed and pitch together, use `varispeed` instead."),
  ActionDef(name: "tone", flags: {afAudio, afGenerator}, argSpec: "midi-note[:waveform]", range: rng(0.0, 127.0),
    help: "Synthesize a wave at a MIDI note's pitch, as a generator: it stands in for a file in `add:`, adding its own audio layer rather than altering existing audio. `69` is A4 (440 Hz), `60` middle C; each step is a semitone. `waveform` is `sine` (default), `saw`, `square`, or `triangle`; the harmonic-rich ones are band-limited, so they stay clean instead of aliasing at high notes. It has no envelope of its own — chain the animatable `volume` action for fades and decays, e.g. `add:tone:60,volume:1..0:ease=out`. Stack several `add:tone` layers for a chord; the mix sums them. `speed`/`varispeed` only stretch the tone, they do not change its pitch — change the note instead. Examples: `add:tone:69`, `add:tone:36:saw`, `add:tone:48:square,volume:0.4`."),
  ActionDef(name: "convolve", flags: {afAudio}, argSpec: "path",
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
  ActionDef(name: "scale", flags: {afVideo}, argSpec: "v|w:h", range: rng(0.0, 100.0, loIncl = false),
    help: "Scale the picture about its center, by `v` both ways or by `w` across and `h` down, e.g. `scale:0.8` or `scale:0.4:1`. On the base (bottom) track what grows past the edge is cut off and what shrinks away shows the background, like `zoom`; an overlay grows or shrinks about the center of where it's placed. Combines with `turn`."),
  ActionDef(name: "turn", flags: {afVideo}, argSpec: "deg",
    help: "Turn the picture clockwise by `deg` about its center without growing the frame, e.g. `turn:15`. On the base (bottom) track the corners are cut off and the uncovered area shows the background; an overlay turns about the center of where it's placed, its uncovered area transparent. For a turn that grows the frame to fit, use `rotate`; to keep turning, use `spin`."),
  ActionDef(name: "burn", flags: {afVideo, afGenerator},
    argSpec: "[file][:font=f][:size=pct][:color=c][:outline=c][:bg=c][:align=a]",
    help: "Draw a subtitle file with libass: an .srt or .ass, or a file's first text subtitle stream, timed from the start of the layer or section it draws on and styled as it says. Without a file it draws the subtitles of the media under it, timed by that media's own clock so they stay on their words through cuts and speed changes: its first text subtitle stream, else the .srt or .ass beside it with its name, e.g. `--when-active burn:size=6`. As a generator it takes a file's place in `add:`, the subtitles on their own overlay layer, e.g. `add:burn:talk.srt`; as an action it draws over a section's picture. Each override replaces that part of every subtitle's style: `font` is a font file (.ttf, .otf, or .ttc) to draw with, `size` the text's height as a percent of the frame's, `color` the text's color, `outline` its outline's, `bg` a box behind each subtitle, and `align` where they sit (as `text` takes it). Colors are names, `#rgb`, `#rrggbb`, or `#rrggbbaa` with transparency. E.g. `add:burn:talk.srt:size=6:color=yellow:bg=#00000099`. Paths can't contain a comma."),
  ActionDef(name: "text", flags: {afVideo, afGenerator},
    argSpec: "text[:font=f][:size=pct][:color=c][:outline=c][:bg=c][:align=a][:vertical]",
    help: "Write a line of text with libass, white with a black outline in the frame's center unless told otherwise. As a generator it takes a file's place in `add:`, the text on its own overlay layer, e.g. `add:text:Chapter 1`; as an action it writes over a section's picture. In the text, `\\n` starts a new line, and a backslash before a comma, colon, or backslash keeps it from ending the text or the action: `text:Hello\\, world`. The overrides are `burn`'s, with `size` defaulting to 8, and `align` places the text: `center`, `top`, `bottom`, `left`, `right`, `top-left`, `top-right`, `bottom-left`, or `bottom-right`. Append `:vertical` for tategaki-style vertical layout: each line's characters stack top to bottom, upright, and lines run right to left (so the first `\\n`-separated line sits rightmost); `align` still places the whole block. To put it anywhere, chain `pos` onto its layer, e.g. `add:text:Hi:size=12,pos:0:-300`."),
  ActionDef(name: "spin", flags: {afVideo}, argSpec: "deg/rate",
    help: "Spin the picture continuously, starting at `deg` and turning at `rate` degrees per second (negative is counter-clockwise), e.g. `spin:0/120`. The picture spins within a constant square that contains every rotation (so it is never clipped); on an overlay the exposed corners are transparent, otherwise they are filled with the background color."),
  ActionDef(name: "drawbox", flags: {afVideo, afGenerator}, argSpec: "x:y:w:h:color",
    help: "Draw a filled rectangle onto the picture. Positional args: `x` and `y` are the top-left corner, `w` and `h` the width and height in pixels, and `color` an RGB color (a name like `red` or a hex value like `#ff0000`). Example: `drawbox:100:100:400:200:red`. As a generator it can take a file's place in `add:`, painting the box on its own overlay layer, e.g. `add:drawbox:100:100:400:200:red`. Implemented via ffmpeg's `drawbox` filter."),
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
  ActionDef(name: "mask", flags: {afVideo},
    argSpec: "x:y:w:h[:radius][:feather][:invert] | poly=x1/y1/x2/y2/...[:feather=N][:invert]",
    help: """
Cut the picture to a rounded-rectangle, ellipse, or arbitrary polygon, making everything outside the shape transparent. `x`/`y` are the top-left corner and `w`/`h` the size in pixels. `radius` is the corner radius in pixels: `0` (the default) is a sharp rectangle, a positive value rounds the corners, and `-1` is a true ellipse (the `w`x`h` box's inscribed oval). The optional `feather` softens the edge by that many pixels (0 = hard, the default); append `:invert` to hide the inside instead. Every field also takes a keyword form (`x=`, `y=`, `w=`, `h=`, `radius=`/`r=`, `feather=`), so positional and keyword args can be mixed.
The `poly=` form cuts to an arbitrary closed polygon instead: `x1/y1/x2/y2/...` is at least 3 points (canvas pixels, up to a few hundred, enough for a GUI to flatten Bezier curves into), filled with the nonzero winding rule, closing back to the first point. It takes `feather=` (keyword only here) and `:invert` same as above. Example: `mask:poly=960/200/1100/500/1300/520/1150/700/960/900/770/700/620/520/820/500`.
On the base (bottom) track there is nothing to reveal, so the masked-out area is filled with the timeline background (`-bg`) instead; on an overlay it reveals the track below. Good for circular/rounded picture-in-picture, vignettes, crop-to-shape, and star/sign/custom cutouts. Example: `add:cam.mp4,pos:900:540:0.3,mask:640:360:300:300:-1:40`."""),
  ActionDef(name: "confine", flags: {afVideo},
    argSpec: "[x:y:w:h[:radius][:feather][:invert] | poly=x1/y1/x2/y2/...[:feather=N][:invert]]",
    help: "Restrict the adjustment effects that follow it (`blur`, `brightness`, `brighthue`, `contrast`, `saturation`, `invert`, `erosion`, `aberration`, `pixelate`) to a rounded-rectangle, ellipse, or arbitrary polygon region (`mask`'s geometry, including its `poly=` form), leaving the rest of the picture untouched. Stays in effect until the next `confine` changes the region; a bare `confine` with no arguments resets to the full frame. Geometry effects (zoom, rotate, pos, ...) are unaffected. Example: `confine:400:300:200:80,blur:30` blurs only the box, e.g. to censor a face or plate."),
  ActionDef(name: "pixelate", flags: {afVideo, afAnimatable}, argSpec: "[w[..w...][:h[..h...]]]", range: rng(1.0, 1024.0, each = true),
    help: "Pixelate the picture into a coarse mosaic of blocks, the classic censoring look. With no argument, uses 16px blocks; `pixelate:n` sets square n×n blocks and `pixelate:w:h` rectangular ones (px). Pair it with `confine` to censor just a face or plate, e.g. `confine:400:300:200:80,pixelate:24`. Implemented via ffmpeg's `pixelize` filter. Animatable: `w` and `h` each accept a keyframe ramp `a..b..c` of whole pixel sizes interpolated across the section, optionally eased with `:ease=`, e.g. `pixelate:1..48:ease=in` dissolves the picture into ever-coarser blocks."),
  ActionDef(name: "confetti", flags: {afVideo, afGenerator}, argSpec: "[count[:gravity][:scheme][:origin][:seed=N][:no-shimmer]]",
    help: """
Throw colorful confetti over the picture. The whole charge fires in one burst when the section starts, like a party popper, and is not replenished as the pieces fall out of frame, so put the action on a short section where you want the pop. Each piece is a small four-sided chip that arcs over and flutters down, spinning and tumbling in 3D.
Every argument is optional and they may be given in any order, so `confetti:neon:top` and `confetti:top:neon` are the same; bare numbers fill `count` first, then `gravity`.
`count` is 1 to 400 (default 200). `gravity` is 0 to 20 (default 1.4), in frame-heights per second squared so it looks the same at any resolution. It sets how fast the pieces come back rather than how high they go: each is thrown to its own fraction of the way up the frame, and each catches its own amount of air, so they do not come down together. `seed=N` (0 to 65535, default 0) reshuffles the arrangement and changes nothing else, so bump it if you do not like how one landed.
`scheme` is `party` (default), `neon`, `gold`, `duotone`, or `white`. A chip flashes white as it turns edge-on, catching the light like foil; add `no-shimmer` to keep every piece its flat color. `origin` is `sides` (default, two cannons at the bottom corners firing inward), `bottom`, `top` (a shower from just above the frame), or `center`.
Drawn onto the frame, so it is not carried into video-editor exports. As a generator it can take a file's place in `add:`, painting the confetti on its own overlay layer, e.g. `add:confetti:300`. Examples: `confetti`, `confetti:250:3`, `confetti:60:0.8:white:center`."""),
]

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

func easeName(e: Easing): string =
  case e
  of easeLinear: "linear"
  of easeIn: "in"
  of easeOut: "out"
  of easeInOut: "inout"

proc pFloat(s: string): float32 {.raises: [ActionParseError].} =
  try: parseFloat(s).float32
  except ValueError: raise newException(ActionParseError, &"Invalid float value: {s}")

proc pInt(s: string, what = "integer value"): int {.raises: [ActionParseError].} =
  try: parseInt(s)
  except ValueError: raise newException(ActionParseError, &"Invalid {what}: {s}")

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
  try: (parseFloat(s).float32, unit)
  except ValueError: raise newException(ActionParseError, &"Invalid duration: {spec}")

proc parseKfTime(spec: string): KfTime {.raises: [ActionParseError].} =
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
  case name
  of "linear": easeLinear
  of "in": easeIn
  of "out": easeOut
  of "inout", "in-out": easeInOut
  else: raise newException(ActionParseError, &"Unknown easing: {spec}")

proc parseEaseTail(act: var Action, parts: seq[string], idx: int,
    val: string) {.raises: [ActionParseError].} =
  ## Consume an animatable action's trailing ":ease=curve[:duration]", which
  ## starts at parts[idx]; anything else trailing there is not a valid action.
  if idx >= parts.len:
    return
  if not parts[idx].startsWith("ease=") or parts.len > idx + 2:
    raise newException(ActionParseError, &"Unknown action: {actionDidYouMean(val)}")
  act.hasEase = true
  act.easeCurve = parseEasing(parts[idx])
  if parts.len == idx + 2:
    (act.easeDur, act.easeDurUnit) = parseDuration(parts[idx + 1])

func isTimed*(a: Action): bool =
  ## Whether any of the action's keyframes says when it is.
  case a.kind
  of actZoom, actBlur, actOpacity, actBrightness, actVolume: a.kt.len > 0
  of actPos: a.pxKt.len > 0 or a.pyKt.len > 0 or a.pscaleKt.len > 0
  of actPixelate: a.pixWKt.len > 0 or a.pixHKt.len > 0
  else: false

proc checkTimedEase(a: Action) {.raises: [ActionParseError].} =
  # Timed keyframes say how long the animation takes; an ease duration would
  # say it again.
  if a.isTimed and a.easeDurUnit != duClip:
    raise newException(ActionParseError,
      "An ease duration can't be given with timed keyframes")

proc parseRgba(spec, what: string): uint32 {.raises: [ActionParseError].} =
  ## A color as 0xRRGGBBAA: a name, #rgb, #rrggbb, or #rrggbbaa.
  if spec.startsWith("#") and spec.len == 9:
    try: return uint32(parseHexInt(spec[1 .. ^1]))
    except ValueError: discard
    raise newException(ActionParseError, &"{what}: invalid color {spec}")
  let c = try: parseColor(spec)
    except ValueError as e: raise newException(ActionParseError, &"{what}: {e.msg}")
  (c.red.uint32 shl 24) or (c.green.uint32 shl 16) or (c.blue.uint32 shl 8) or 0xff

func rgbaStr*(c: uint32): string =
  ## #rrggbb, or #rrggbbaa when it's see-through.
  result = "#" & toHex(int(c shr 8), 6).toLowerAscii
  if (c and 0xff) != 0xff: result &= toHex(int(c and 0xff), 2).toLowerAscii

const alignNames*: array[1 .. 9, string] = ["bottom-left", "bottom",
  "bottom-right", "left", "center", "right", "top-left", "top", "top-right"]

proc parseSubs(parts: seq[string], kind: ActionKind): Action {.raises: [ActionParseError].} =
  # The subtitle file comes first, unnamed, then key=value overrides. A part
  # that isn't one goes back onto what came before it, so the colon of a
  # Windows drive stays in a path.
  let name = parts[0]
  const keys = ["file", "font", "size", "color", "outline", "bg", "align"]
  var given: array[keys.len, string]
  var seen: array[keys.len, bool]
  var vertical = false
  var cur = 0
  for part in parts[1 .. ^1]:
    if part == "vertical":
      if kind != actText:
        raise newException(ActionParseError, &"{name}: vertical only applies to text")
      vertical = true
      continue
    let eq = part.find('=')
    let key = if eq > 0: keys.find(part[0 ..< eq]) else: -1
    if key > 0 or key == 0 and kind == actBurn:
      if seen[key]:
        raise newException(ActionParseError, &"{name}: {keys[key]} given twice")
      (cur, seen[key], given[key]) = (key, true, part[eq + 1 .. ^1])
    elif seen[cur] or cur == 0 and given[0].len > 0:
      given[cur] &= ":" & part
    else:
      (seen[cur], given[cur]) = (true, part)
  if kind == actText: given[0] = decodeString(given[0])
  if kind == actText and given[0].len == 0:
    raise newException(ActionParseError, "text needs something to say")
  if given[0].len > 4096 or given[1].len > 4096:
    raise newException(ActionParseError,
      if kind == actText: "text is too long" else: "burn path is too long")
  result = if kind == actText: Action(kind: actText) else: Action(kind: actBurn)
  (result.burnFile, result.burnFont) = (given[0], given[1])
  if seen[2]:
    result.burnSize = pFloat(given[2])
    if not (result.burnSize > 0 and result.burnSize <= 100):
      raise newException(ActionParseError, &"{name} size must be in (0, 100]")
  for (k, part) in [(3, bpColor), (4, bpOutline), (5, bpBg)]:
    if seen[k]:
      result.burnSet.incl part
      result.burnColors[part] = parseRgba(given[k], &"{name} {keys[k]}")
  if seen[6]:
    let a = alignNames.find(given[6])
    if a < 0:
      raise newException(ActionParseError, &"{name}: unknown align: {given[6]}")
    result.burnAlign = uint8(a + 1)
  result.burnVertical = vertical

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
  if vals[2] <= 0 or vals[3] <= 0:
    raise newException(ActionParseError, &"{name} width and height must be positive")
  if vals[4] < -1:
    raise newException(ActionParseError, &"{name} radius must be -1 (ellipse) or >= 0")
  if vals[5] < 0 or vals[5] > 255:
    raise newException(ActionParseError, &"{name} feather must be in [0, 255]")

  result = Action(kind: kind)  # branch fields assigned after (shared by both kinds)
  result.mX = int32(vals[0])
  result.mY = int32(vals[1])
  result.mW = int32(vals[2])
  result.mH = int32(vals[3])
  result.mRadius = int32(vals[4])
  result.mFeather = uint8(vals[5])
  result.mInvert = inv

const maxPolyPoints = 1000

proc parsePolyMask(parts: seq[string], kind: ActionKind,
    name: string): Action {.raises: [ActionParseError].} =
  var xs, ys: seq[int32]
  var feather = 0'u8
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
      for i in 0 ..< n:
        xs.add addPoint(nums[2 * i], p)
        ys.add addPoint(nums[2 * i + 1], p)
    elif p.startsWith("feather="):
      let v = try: parseInt(p[8 .. ^1])
        except ValueError: raise newException(ActionParseError, &"{name}: invalid feather: {p}")
      if v < 0 or v > 255:
        raise newException(ActionParseError, &"{name} feather must be in [0, 255]")
      feather = uint8(v)
    else:
      raise newException(ActionParseError, &"{name}: unknown key: {p}")

  if not gotPoly:
    raise newException(ActionParseError, &"{name} poly requires at least 3 points")

  result = Action(kind: kind)
  result.mPolyXs = xs
  result.mPolyYs = ys
  result.mFeather = feather
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

  if val.startsWith("text:"):
    return parseSubs(splitUnescaped(val, ':'), actText)

  let parts = val.split(":")

  if parts[0] == "mask":
    if parts.anyIt(it.startsWith("poly=")):
      return parsePolyMask(parts, actMaskPoly, "mask")
    return parseShapeRegion(parts, actMask, "mask")
  if parts[0] == "confine":
    if parts.anyIt(it.startsWith("poly=")):
      return parsePolyMask(parts, actConfinePoly, "confine")
    return parseShapeRegion(parts, actConfine, "confine")

  if parts[0] == "burn":
    return parseSubs(parts, actBurn)

  if parts[0] == "convolve":
    # The path is everything after the name, so a Windows drive colon stays put.
    let path = parts[1 .. ^1].join(":")
    if path.len == 0:
      raise newException(ActionParseError, "convolve needs a path")
    if path.len > 4096:
      raise newException(ActionParseError, "convolve path is too long")
    return Action(kind: actConvolve, irPath: path)

  # deesser takes positional args: intensity[:max[:freq]]
  if parts.len >= 2 and parts.len <= 4 and parts[0] == "deesser":
    var vals = [toUnorm16(0.0), halfUnorm16, halfUnorm16]
    for idx in 1 ..< parts.len:
      vals[idx - 1] = toUnorm16(pFloat(parts[idx]))
    return Action(kind: actDeesser, intensity: vals[0], maxd: vals[1], freq: vals[2])

  # duck takes positional args: [amount[:threshold[:attack[:release]]]]
  if parts[0] == "duck" and parts.len <= 5:
    var vals = [0.85'f32, 0.04'f32, 100.0'f32, 500.0'f32]
    for idx in 1 ..< parts.len:
      vals[idx - 1] = pFloat(parts[idx])
    # `not (a and b)` so NaN fails the checks too; uint16(NaN) is UB.
    if not (vals[0] >= 0.0 and vals[0] <= 1.0):
      raise newException(ActionParseError, "duck amount must be in [0.0, 1.0]")
    if not (vals[1] >= 0.0 and vals[1] <= 1.0):
      raise newException(ActionParseError, "duck threshold must be in [0.0, 1.0]")
    if not (vals[2] >= 0.0 and vals[2] <= 65535.0 and
        vals[3] >= 0.0 and vals[3] <= 65535.0):
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
      k[idx - 1] = pFloat(parts[idx])
    for v in k:
      if v < -1.0 or v > 1.0:
        raise newException(ActionParseError, "lens factors must be in [-1.0, 1.0]")
    return Action(kind: actLens, k1: toSnorm16(k[0]), k2: toSnorm16(k[1]))

  # tone: a MIDI note plus an optional waveform name, "tone:note[:waveform]".
  if parts[0] == "tone" and parts.len <= 3:
    if parts.len == 1:
      raise newException(ActionParseError, "tone requires a MIDI note (tone:69 is A4)")
    let n = pFloat(parts[1])
    # `not (a and b)` so NaN fails the check too; uint8(NaN) is UB. Whole notes
    # only: a fraction would round away silently and stop round-tripping.
    if not (n >= 0.0 and n <= 127.0 and n == round(n)):
      raise newException(ActionParseError, "tone must be a whole MIDI note in [0, 127]")
    var wave = wSine
    if parts.len == 3:
      let idx = waveformNames.find(parts[2])
      if idx < 0:
        raise newException(ActionParseError, &"tone: unknown waveform: {parts[2]}" &
          didYouMean(parts[2], @waveformNames))
      wave = Waveform(idx)
    return Action(kind: actTone, note: uint8(n), wave: wave)

  # rotate: a fixed angle "rotate:deg" (static, expands the canvas).
  if parts[0] == "rotate" and parts.len == 2:
    if '/' in parts[1]:
      raise newException(ActionParseError,
        "rotate takes a fixed angle (rotate:deg); use spin:deg/rate for a continuous spin")
    return Action(kind: actRotate, rStart: Unorm16(rotCode(pFloat(parts[1]))))

  if parts[0] == "scale" and parts.len in 2..3:
    let w = pFloat(parts[1])
    let h = (if parts.len == 3: pFloat(parts[2]) else: w)
    for v in [w, h]:
      if not (v > 0.0 and v <= 100.0):
        raise newException(ActionParseError, "scale must be in (0.0, 100.0]")
    return Action(kind: actScale, tScaleW: w, tScaleH: h, tUniform: parts.len == 2)
  if parts[0] == "turn" and parts.len == 2:
    let deg = pFloat(parts[1])
    if classify(deg) in {fcNan, fcInf, fcNegInf}:
      raise newException(ActionParseError, "turn takes an angle in degrees")
    return Action(kind: actTurn, tDeg: deg)

  # spin: a continuous rotation "spin:deg/rate", starting at `deg` and turning
  # `rate` degrees/second.
  if parts[0] == "spin" and parts.len == 2:
    let spec = parts[1]
    let slash = spec.find('/')
    if slash < 0:
      raise newException(ActionParseError, "spin requires spin:deg/rate")
    return Action(kind: actSpin,
      sStart: Unorm16(rotCode(pFloat(spec[0 ..< slash]))),
      sRate: pFloat(spec[slash + 1 .. ^1]))

  # drawbox takes positional args: x:y:w:h:color (color is RGB only).
  if parts[0] == "drawbox":
    if parts.len != 6:
      raise newException(ActionParseError, "drawbox requires x:y:w:h:color")
    var coords: array[4, int32]
    for idx in 0 ..< 4:
      let n = pInt(parts[idx + 1])
      if n < low(int32).int or n > high(int32).int:
        raise newException(ActionParseError,
          &"drawbox value out of range: {parts[idx + 1]}")
      coords[idx] = int32(n)
    if coords[2] <= 0 or coords[3] <= 0:
      raise newException(ActionParseError, "drawbox width and height must be positive")
    let col = (
      try:
        parseColor(parts[5])
      except ValueError:
        raise newException(ActionParseError, &"Invalid color: {parts[5]}")
    )
    return Action(kind: actDrawbox, dbX: coords[0], dbY: coords[1],
      dbW: coords[2], dbH: coords[3], dbColor: col)

  if parts[0] in ["colorkey", "chromakey"]:
    if parts.len < 2 or parts.len > 4:
      raise newException(ActionParseError,
        &"{parts[0]} requires color[:similar:blend]")
    let col = (
      try:
        parseColor(parts[1])
      except ValueError:
        raise newException(ActionParseError, &"Invalid color: {parts[1]}")
    )
    var vals = [toUnorm16(0.25'f32), toUnorm16(0.0'f32)]
    for idx in 2 ..< parts.len:
      vals[idx - 2] = toUnorm16(pFloat(parts[idx]))
    if vals[0] < toUnorm16(0.01'f32):
      vals[0] = toUnorm16(0.01'f32)

    if parts[0] == "colorkey":
      return Action(kind: actColorKey, color: col, similar: vals[0], blend: vals[1])
    return Action(kind: actChromaKey, color: col, similar: vals[0], blend: vals[1])

  # choke: shrink the alpha matte inward by `n` pixels (default 1).
  if parts[0] == "choke" and parts.len <= 2:
    if parts.len == 1:
      return Action(kind: actChoke, chokeN: 1)
    let n = pInt(parts[1])
    if n < 1 or n > 16:
      raise newException(ActionParseError, "choke must be in [1, 16]")
    return Action(kind: actChoke, chokeN: uint8(n))

  # pixelate: bare = 16px blocks; pixelate:n = n square; pixelate:w:h =
  # rectangular. Each size is a ramp with an optional ease suffix:
  #   pixelate:24   pixelate:1..48   pixelate:8..40:8:ease=inout
  if parts[0] == "pixelate":
    proc blockKf(spec: string): tuple[kf: seq[float32], kt: seq[KfTime]] {.
        raises: [ActionParseError].} =
      result = parseRamp(spec)
      for v in result.kf:
        # `not (a and b)` so NaN fails the check too; uint16(NaN) is UB.
        if not (v >= 1.0'f32 and v <= 1024.0'f32 and v == round(v)):
          raise newException(ActionParseError,
            "pixelate block size must be a whole number in [1, 1024]")

    var idx = 1
    var w = (kf: @[16.0'f32], kt: newSeq[KfTime]())
    var h = (kf: newSeq[float32](), kt: newSeq[KfTime]())
    if parts.len > idx and not parts[idx].startsWith("ease="):
      w = blockKf(parts[idx])
      inc idx
      if parts.len > idx and not parts[idx].startsWith("ease="):
        h = blockKf(parts[idx])
        inc idx
    if h.kf.len == 0:  # one ramp given: square blocks
      h = w
    result = Action(kind: actPixelate, pixWKf: w.kf, pixHKf: h.kf,
      pixWKt: w.kt, pixHKt: h.kt)
    result.parseEaseTail(parts, idx, val)
    result.checkTimedEase()
    return result

  # confetti: [count[:gravity][:scheme][:origin]]. Scheme and origin are name
  # tokens, so every argument can be given in any order; bare numbers fill
  # count then gravity.
  if parts[0] == "confetti":
    var count = confettiCountId
    var gravity = confettiGravityId
    var scheme = csParty
    var origin = confettiOriginId
    var shimmer = true
    var seed = 0'u16
    var numsSeen = 0
    var schemeSeen = false
    var originSeen = false
    var shimmerSeen = false
    var seedSeen = false
    for idx in 1 ..< parts.len:
      let p = parts[idx]
      let asScheme = confettiSchemeNames.find(p)
      let asOrigin = confettiOriginNames.find(p)
      if asScheme >= 0:
        if schemeSeen:
          raise newException(ActionParseError, "confetti: scheme given twice")
        scheme = ConfettiScheme(asScheme)
        schemeSeen = true
      elif asOrigin >= 0:
        if originSeen:
          raise newException(ActionParseError, "confetti: origin given twice")
        origin = ConfettiOrigin(asOrigin)
        originSeen = true
      elif p.startsWith("seed="):
        if seedSeen:
          raise newException(ActionParseError, "confetti: seed given twice")
        let v = pInt(p[5 .. ^1], "confetti seed")
        if v < 0 or v > 65535:
          raise newException(ActionParseError, "confetti seed must be in [0, 65535]")
        seed = uint16(v)
        seedSeen = true
      elif p == "shimmer" or p == "no-shimmer":
        if shimmerSeen:
          raise newException(ActionParseError, "confetti: shimmer given twice")
        shimmer = p == "shimmer"
        shimmerSeen = true
      elif p.len == 0 or p[0] notin {'0' .. '9', '-', '+', '.'}:
        # Not a number, so it was meant as one of the name tokens.
        raise newException(ActionParseError, &"confetti: unknown value: {p}" &
          didYouMean(p, @confettiSchemeNames & @confettiOriginNames &
            @["shimmer", "no-shimmer"]))
      elif numsSeen == 0:
        let n = pInt(p, "confetti count")
        if n < 1 or n > 400:
          raise newException(ActionParseError, "confetti count must be in [1, 400]")
        count = uint16(n)
        numsSeen = 1
      elif numsSeen == 1:
        gravity = pFloat(p)
        # `not (a and b)` so NaN fails the check too.
        if not (gravity >= 0.0'f32 and gravity <= 20.0'f32):
          raise newException(ActionParseError, "confetti gravity must be in [0.0, 20.0]")
        numsSeen = 2
      else:
        raise newException(ActionParseError, &"confetti: unexpected value: {p}")
    return Action(kind: actConfetti, cCount: count, cGravity: gravity,
      cScheme: scheme, cOrigin: origin, cShimmer: shimmer, cSeed: seed)

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
          nums.add pInt(p, "aberration value")
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
          raise newException(ActionParseError, &"aberration: expected key=value, got {p}")

        let key = p[0 ..< eq]
        let value = p[eq + 1 .. ^1]
        if key == "edge":
          wrap = toEdge(value)
          continue
        let n = pInt(value, "aberration value")
        case key
        of "rh": rh = n
        of "rv": rv = n
        of "gh": gh = n
        of "gv": gv = n
        of "bh": bh = n
        of "bv": bv = n
        else: raise newException(ActionParseError, &"Unknown aberration key: {key}")
    return Action(kind: actAberration, abRh: chk(rh), abRv: chk(rv), abGh: chk(gh),
        abGv: chk(gv), abBh: chk(bh), abBv: chk(bv), abWrap: wrap)

  # pos: overlay placement, each field an animatable ramp:
  #   pos:x:y   pos:x:y:scale   pos:0..600:300:1..0.5:ease=inout
  if parts[0] == "pos":
    if parts.len < 3:
      raise newException(ActionParseError, "pos requires x:y[:scale]")
    let x = parseRamp(parts[1])
    let y = parseRamp(parts[2])
    # parts[3] is the scale ramp unless it's the ease suffix.
    var s = (kf: @[1.0'f32], kt: newSeq[KfTime]())
    var idx = 3
    if parts.len > 3 and not parts[3].startsWith("ease="):
      s = parseRamp(parts[3])
      idx = 4
    for v in s.kf:
      if v <= 0.0'f32:
        raise newException(ActionParseError, "pos scale must be greater than 0.0")
    result = Action(kind: actPos, pxKf: x.kf, pyKf: y.kf, pscaleKf: s.kf,
      pxKt: x.kt, pyKt: y.kt, pscaleKt: s.kt)
    result.parseEaseTail(parts, idx, val)
    result.checkTimedEase()
    return result

  # Animatable scalar effects: a value or keyframe ramp, with optional easing:
  #   zoom:2   zoom:1..2   zoom:1..0.5..1   zoom:1..2:ease=inout:2sec
  if parts[0] in animScalar and parts.len >= 2:
    let (kf, kt) = parseRamp(parts[1])
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

    result = case parts[0]
      of "zoom": Action(kind: actZoom, kf: kf, kt: kt)
      of "blur": Action(kind: actBlur, kf: kf, kt: kt)
      of "opacity": Action(kind: actOpacity, kf: kf, kt: kt)
      of "volume": Action(kind: actVolume, kf: kf, kt: kt)
      else: Action(kind: actBrightness, kf: kf, kt: kt)
    result.parseEaseTail(parts, 2, val)
    result.checkTimedEase()
    return result

  if parts.len == 2:
    let effectType = parts[0]
    let effectVal = pFloat(parts[1])
    case effectType
    of "speed", "varispeed":
      # `not (a and b)` instead of `<= or >=` so NaN fails the check too;
      # speed <= 0 makes the renderer's atempo decomposition loop forever.
      if not (effectVal > 0.0 and effectVal < 99999.0):
        raise newException(ActionParseError, &"{effectType} must be in range (0, 99999)")
      return Action(kind: actSpeed, val: effectVal,
        varispeed: effectType == "varispeed")
    of "pitch":
      # `not (a and b)` so NaN fails the check too; int16(NaN) is UB.
      if not (effectVal >= -24.0 and effectVal <= 24.0):
        raise newException(ActionParseError, "pitch must be in [-24.0, 24.0] semitones")
      return Action(kind: actPitch, pCents: int16(round(effectVal * 100.0'f32)))
    of "brighthue":
      return Action(kind: actLuv, brighthue: effectVal, contrast: luvContrastId,
        saturation: luvSaturationId)
    of "contrast":
      if effectVal < -2.0 or effectVal > 2.0:
        raise newException(ActionParseError, "contrast must be in [-2.0, 2.0]")
      return Action(kind: actLuv, brighthue: luvBrighthueId, contrast: effectVal,
        saturation: luvSaturationId)
    of "saturation":
      if effectVal < 0.0 or effectVal > 3.0:
        raise newException(ActionParseError, "saturation must be in [0.0, 3.0]")
      return Action(kind: actLuv, brighthue: luvBrighthueId, contrast: luvContrastId,
        saturation: effectVal)
    else: discard

  raise newException(ActionParseError, &"Unknown action: {actionDidYouMean(val)}")

func easeSuffix(a: Action): string =
  ## The trailing ":ease=..." for an animated action, or "" if it has none.
  if not a.hasEase: return ""
  result = &":ease={easeName(a.easeCurve)}"
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

when not defined(nimscript):
  func `$`*(act: Action): string =
    case act.kind
    of actInvert: "invert"
    of actHflip: "hflip"
    of actVflip: "vflip"
    of actLoop: "loop"
    of actErosion: "erosion"
    of actSpeed:
      if act.varispeed: &"varispeed:{act.val}" else: &"speed:{act.val}"
    of actVolume: &"volume:{kfStr(act)}{easeSuffix(act)}"
    of actDeesser: &"deesser:{act.intensity}:{act.maxd}:{act.freq}"
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
      var s = if act.kind == actText: "text:" & escapeText(act.burnFile)
              elif act.burnFile.len > 0: "burn:" & act.burnFile
              else: "burn"
      if act.burnFont.len > 0: s &= ":font=" & act.burnFont
      if act.burnSize > 0: s &= &":size={act.burnSize}"
      for (part, key) in [(bpColor, "color"), (bpOutline, "outline"), (bpBg, "bg")]:
        if part in act.burnSet: s &= &":{key}={rgbaStr(act.burnColors[part])}"
      if act.burnAlign in 1'u8 .. 9'u8: s &= ":align=" & alignNames[act.burnAlign]
      if act.burnVertical: s &= ":vertical"
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

  func easeBytes(a: Action): int = (if a.hasEase: 6 else: 0)

  # A timed ramp is marked by a zero before its keyframe count, and is followed
  # by each keyframe's unit and time. An untimed ramp's count is never zero: an
  # empty ramp takes the mark too, with no times.
  func marked(n: int, kt: seq[KfTime]): bool = kt.len > 0 or n == 0

  func timeBytes(n: int, kt: seq[KfTime]): int =
    (if marked(n, kt): 1 else: 0) + kt.len * 5

  func timeBytes(a: Action): int =
    case a.kind
    of actPos: timeBytes(a.pxKf.len, a.pxKt) + timeBytes(a.pyKf.len, a.pyKt) +
      timeBytes(a.pscaleKf.len, a.pscaleKt)
    of actPixelate: timeBytes(a.pixWKf.len, a.pixWKt) + timeBytes(a.pixHKf.len, a.pixHKt)
    of actZoom, actBlur, actOpacity, actBrightness, actVolume: timeBytes(a.kf.len, a.kt)
    else: 0

  proc packCount(base: ptr UncheckedArray[uint8], pos: var int, n: int,
      kt: seq[KfTime]) =
    if marked(n, kt):
      base[pos] = 0'u8
      pos += 1
    base[pos] = uint8(n)
    pos += 1

  proc packTimes(base: ptr UncheckedArray[uint8], pos: var int, kt: seq[KfTime]) =
    for t in kt:
      base[pos] = uint8(ord(t.unit))
      var at = t.at
      copyMem(addr base[pos + 1], addr at, sizeof(float32))
      pos += 5

  proc unpackCount(base: ptr UncheckedArray[uint8], pos: var int): (int, bool) =
    ## The keyframe count, and whether times follow the keyframes.
    let timed = base[pos] == 0'u8
    if timed: pos += 1
    result = (base[pos].int, timed)
    pos += 1

  proc unpackTimes(base: ptr UncheckedArray[uint8], pos: var int,
      n: int): seq[KfTime] =
    result = newSeq[KfTime](n)
    for c in 0 ..< n:
      result[c].unit = KfUnit(base[pos].int)
      copyMem(addr result[c].at, addr base[pos + 1], sizeof(float32))
      pos += 5

  func actionByteSize(a: Action): int =
    case a.kind
    of actInvert, actHflip, actVflip, actLoop, actErosion: 1
    of actChoke: 2
    of actRotate, actPitch, actTone: 3
    of actLens, actSpeed: 5
    of actDeesser, actSpin: 7
    of actColorKey, actChromaKey, actAberration: 8
    of actScale: 10
    of actTurn: 5
    # header, the file and font each a uint16 length + bytes, float32 size,
    # set byte, align byte, three uint32 colors
    of actBurn, actText: 1 + 2 + a.burnFile.len + 2 + a.burnFont.len + 4 + 1 + 1 + 12
    of actDuck: 9
    of actConvolve: 3 + a.irPath.len  # header + uint16 length + bytes
    of actConfetti: 10
    of actLuv: 11
    of actDrawbox: 20
    of actMask, actConfine: 23  # header + flags + feather + 5x int32 (x,y,w,h,radius)
    of actMaskPoly, actConfinePoly: 5 + a.mPolyXs.len * 8
    of actPos: 4 + easeBytes(a) + timeBytes(a) +
      (a.pxKf.len + a.pyKf.len + a.pscaleKf.len) * 4
    of actPixelate: 3 + easeBytes(a) + timeBytes(a) + (a.pixWKf.len + a.pixHKf.len) * 2
    of actBrightness, actOpacity: 2 + easeBytes(a) + timeBytes(a) + a.kf.len * 2
    of actBlur, actZoom, actVolume: 2 + easeBytes(a) + timeBytes(a) + a.kf.len * 4

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
        # The bytes come from our own pack (newActions), so the kind byte is
        # always a declared ActionKind despite the enum's reserved holes.
        {.push warning[HoleEnumConv]: off.}
        let kind = ActionKind((base[i] and 0x7f'u8).int)
        {.pop.}
        case kind
        of actInvert, actHflip, actVflip, actLoop, actErosion:
          yield Action(kind: kind)
          i += 1
        of actRotate:
          var st: Unorm16
          copyMem(addr st, addr base[i + 1], sizeof(Unorm16))
          yield Action(kind: actRotate, rStart: st)
          i += 3
        of actScale:
          var w, h: float32
          copyMem(addr w, addr base[i + 1], sizeof(float32))
          copyMem(addr h, addr base[i + 5], sizeof(float32))
          yield Action(kind: actScale, tScaleW: w, tScaleH: h, tUniform: base[i + 9] != 0)
          i += 10
        of actTurn:
          var v: float32
          copyMem(addr v, addr base[i + 1], sizeof(float32))
          yield Action(kind: actTurn, tDeg: v)
          i += 5
        of actPitch:
          var cents: int16
          copyMem(addr cents, addr base[i + 1], sizeof(int16))
          yield Action(kind: actPitch, pCents: cents)
          i += 3
        of actTone:
          yield Action(kind: actTone, note: base[i + 1],
            wave: Waveform(base[i + 2].int))
          i += 3
        of actLens:
          var k1v, k2v: Snorm16
          copyMem(addr k1v, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr k2v, addr base[i + 3], sizeof(Snorm16))
          yield Action(kind: actLens, k1: k1v, k2: k2v)
          i += 5
        of actSpeed:
          var v: float32
          copyMem(addr v, addr base[i + 1], sizeof(float32))
          yield Action(kind: actSpeed, val: v,
            varispeed: (base[i] and varispeedFlag) != 0'u8)
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
        of actConvolve:
          var n: uint16
          copyMem(addr n, addr base[i + 1], sizeof(uint16))
          var path = newString(n.int)
          if n > 0: copyMem(addr path[0], addr base[i + 3], n.int)
          yield Action(kind: actConvolve, irPath: path)
          i += 3 + n.int
        of actBurn, actText:
          var act = if kind == actText: Action(kind: actText) else: Action(kind: actBurn)
          act.burnVertical = (base[i] and verticalFlag) != 0'u8
          var pos = i + 1
          for path in [addr act.burnFile, addr act.burnFont]:
            var n: uint16
            copyMem(addr n, addr base[pos], sizeof(uint16))
            path[] = newString(n.int)
            if n > 0: copyMem(addr path[][0], addr base[pos + 2], n.int)
            pos += 2 + n.int
          copyMem(addr act.burnSize, addr base[pos], sizeof(float32))
          act.burnSet = cast[set[BurnPart]](base[pos + 4])
          act.burnAlign = base[pos + 5]
          copyMem(addr act.burnColors, addr base[pos + 6], 12)
          yield act
          i = pos + 18
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
        of actMaskPoly, actConfinePoly:
          let invert = (base[i + 1] and 0x1'u8) != 0'u8
          let feather = base[i + 2]
          var n: uint16
          copyMem(addr n, addr base[i + 3], sizeof(uint16))
          var xs = newSeq[int32](n.int)
          var ys = newSeq[int32](n.int)
          var pos = i + 5
          for k in 0 ..< n.int:
            copyMem(addr xs[k], addr base[pos], sizeof(int32))
            copyMem(addr ys[k], addr base[pos + 4], sizeof(int32))
            pos += 8
          yield Action(kind: kind, mFeather: feather, mInvert: invert,
            mPolyXs: xs, mPolyYs: ys)
          i = pos
        of actPixelate:
          let hasEase = (base[i] and easeFlag) != 0'u8
          var pos = i + 1
          var act = Action(kind: actPixelate, hasEase: hasEase)
          if hasEase:
            act.easeCurve = Easing(base[pos].int)
            act.easeDurUnit = DurUnit(base[pos + 1].int)
            copyMem(addr act.easeDur, addr base[pos + 2], sizeof(float32))
            pos += 6
          for which in 0 .. 1:  # width, then height keyframes
            let (count, timed) = unpackCount(base, pos)
            var sizes = newSeq[float32](count)
            for c in 0 ..< count:
              var v: uint16
              copyMem(addr v, addr base[pos], sizeof(uint16))
              sizes[c] = v.float32
              pos += 2
            let times = (if timed: unpackTimes(base, pos, count) else: @[])
            if which == 0: (act.pixWKf, act.pixWKt) = (sizes, times)
            else: (act.pixHKf, act.pixHKt) = (sizes, times)
          yield act
          i = pos
        of actConfetti:
          var count, seed: uint16
          var gravity: float32
          copyMem(addr count, addr base[i + 1], sizeof(uint16))
          copyMem(addr gravity, addr base[i + 3], sizeof(float32))
          copyMem(addr seed, addr base[i + 8], sizeof(uint16))
          let flags = base[i + 7]
          yield Action(kind: actConfetti, cCount: count, cGravity: gravity,
            cScheme: ConfettiScheme((flags and schemeMask).int),
            cShimmer: (flags and shimmerFlag) != 0'u8,
            cOrigin: ConfettiOrigin(((flags shr originShift) and originMask).int),
            cSeed: seed)
          i += 10
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
            let (count, timed) = unpackCount(base, pos)
            var s = newSeq[float32](count)
            for c in 0 ..< count:
              copyMem(addr s[c], addr base[pos], sizeof(float32))
              pos += 4
            let times = (if timed: unpackTimes(base, pos, count) else: @[])
            case which
            of 0: (act.pxKf, act.pxKt) = (s, times)
            of 1: (act.pyKf, act.pyKt) = (s, times)
            else: (act.pscaleKf, act.pscaleKt) = (s, times)
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
          let (count, timed) = unpackCount(base, pos)
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
          if timed: act.kt = unpackTimes(base, pos, count)
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
    for a in list:
      # Keyframe counts are packed into one byte; a wrapped count would
      # misalign every later field on decode.
      let maxKf = case a.kind
        of actPos: max(a.pxKf.len, max(a.pyKf.len, a.pscaleKf.len))
        of actPixelate: max(a.pixWKf.len, a.pixHKf.len)
        of actZoom, actBlur, actOpacity, actBrightness, actVolume: a.kf.len
        else: 0
      if maxKf > 255:
        raise newException(ActionParseError, "Too many keyframes (max 255)")
      # Times pair with keyframes one to one; packing trusts that.
      let paired = case a.kind
        of actPos: (a.pxKt.len in [0, a.pxKf.len]) and
          (a.pyKt.len in [0, a.pyKf.len]) and (a.pscaleKt.len in [0, a.pscaleKf.len])
        of actPixelate: (a.pixWKt.len in [0, a.pixWKf.len]) and
          (a.pixHKt.len in [0, a.pixHKf.len])
        of actZoom, actBlur, actOpacity, actBrightness, actVolume:
          a.kt.len in [0, a.kf.len]
        else: true
      if not paired:
        raise newException(ActionParseError, "Keyframe times don't match the keyframes")
      total += actionByteSize(a)
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
      of actScale:
        base.writeAt(i, 1, a.tScaleW)
        base.writeAt(i, 5, a.tScaleH)
        base[i + 9] = (if a.tUniform: 1'u8 else: 0'u8)
        i += 10
      of actTurn:
        base.writeAt(i, 1, a.tDeg)
        i += 5
      of actPitch:
        base.writeAt(i, 1, a.pCents)
        i += 3
      of actTone:
        base[i + 1] = a.note
        # A bare Nim enum is int-sized, so narrow explicitly like easeCurve.
        base[i + 2] = uint8(ord(a.wave))
        i += 3
      of actLens:
        base.writeAt(i, 1, a.k1)
        base.writeAt(i, 3, a.k2)
        i += 5
      of actSpeed:
        if a.varispeed: base[i] = base[i] or varispeedFlag
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
      of actConvolve:
        base.writeAt(i, 1, uint16(a.irPath.len))
        if a.irPath.len > 0:
          copyMem(addr base[i + 3], unsafeAddr a.irPath[0], a.irPath.len)
        i += 3 + a.irPath.len
      of actBurn, actText:
        if a.burnVertical: base[i] = base[i] or verticalFlag
        var pos = i + 1
        for path in [a.burnFile, a.burnFont]:
          base.writeAt(pos, 0, uint16(path.len))
          if path.len > 0:
            copyMem(addr base[pos + 2], unsafeAddr path[0], path.len)
          pos += 2 + path.len
        base.writeAt(pos, 0, a.burnSize)
        base[pos + 4] = cast[uint8](a.burnSet)
        base[pos + 5] = a.burnAlign
        var colors = a.burnColors
        copyMem(addr base[pos + 6], addr colors, 12)
        i = pos + 18
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
      of actMaskPoly, actConfinePoly:
        base[i + 1] = (if a.mInvert: 0x1'u8 else: 0'u8)
        base[i + 2] = a.mFeather
        base.writeAt(i, 3, uint16(a.mPolyXs.len))
        var pos = i + 5
        for k in 0 ..< a.mPolyXs.len:
          base.writeAt(pos, 0, a.mPolyXs[k])
          base.writeAt(pos, 4, a.mPolyYs[k])
          pos += 8
        i = pos
      of actPixelate:
        if a.hasEase: base[i] = base[i] or easeFlag
        var pos = i + 1
        if a.hasEase:
          base[pos] = uint8(ord(a.easeCurve))
          base[pos + 1] = uint8(ord(a.easeDurUnit))
          var d = a.easeDur
          copyMem(addr base[pos + 2], addr d, sizeof(float32))
          pos += 6
        for (sizes, times) in [(a.pixWKf, a.pixWKt), (a.pixHKf, a.pixHKt)]:
          packCount(base, pos, sizes.len, times)
          for v in sizes:
            var vv = pixCode(v)
            copyMem(addr base[pos], addr vv, sizeof(uint16))
            pos += 2
          packTimes(base, pos, times)
        i = pos
      of actConfetti:
        base.writeAt(i, 1, a.cCount)
        base.writeAt(i, 3, a.cGravity)
        # A bare Nim enum is int-sized, so narrow explicitly like easeCurve.
        base[i + 7] = uint8(ord(a.cScheme)) or
          (uint8(ord(a.cOrigin)) shl originShift) or
          (if a.cShimmer: shimmerFlag else: 0'u8)
        base.writeAt(i, 8, a.cSeed)
        i += 10
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
        for (s, times) in [(a.pxKf, a.pxKt), (a.pyKf, a.pyKt),
            (a.pscaleKf, a.pscaleKt)]:
          packCount(base, pos, s.len, times)
          for v in s:
            var vv = v
            copyMem(addr base[pos], addr vv, sizeof(float32))
            pos += 4
          packTimes(base, pos, times)
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
        packCount(base, pos, a.kf.len, a.kt)
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
        packTimes(base, pos, a.kt)
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
    for part in splitUnescaped(val.strip(), ',', textOnly = true):
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
          actVolume, actPos, actPixelate} and not action.hasEase:
        action.hasEase = true
        action.easeCurve = pendCurve
        # Timed keyframes keep their own timing; they take only the curve.
        if not action.isTimed:
          action.easeDurUnit = pendUnit
          action.easeDur = pendDur
      if action.kind == actLuv:
        # Adjacent-fusion: collapse this actLuv into previous one if it's also actLuv.
        # Per field, the non-identity value wins; later wins on genuine conflicts.
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
