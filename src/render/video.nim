import std/[sets, strformat, tables]
from std/math import round, hypot, ceil, floor, exp, sin, cos, ln, sqrt
from std/algorithm import upperBound

import ../[action, av, ffmpeg, graph, log, timeline]
import ../util/[color, dnorm16, rational]

type VideoFrame = object
  index: int
  src: ptr string
  effects: Actions
  gen: bool      # source-less overlay (`add:confetti`): draw on a clear canvas
  local: int     # frame offset within the clip, for animated effects
  dur: int       # clip length in frames
  x: float32     # overlay placement (canvas pixels, sub-pixel); 0 for the base layer
  y: float32
  scale: float32 # overlay size multiplier; 1.0 for the base layer
  fit: bool      # no explicit `pos`: fit-and-center to the canvas like the base

func envAnimLen(unit: DurUnit, mag: float32, clipDur: int, fps: float): int =
  ## Resolve an ease duration to a frame count for the current clip.
  case unit
  of duClip: clipDur
  of duSec: max(1, int(round(mag.float * fps)))
  of duFrames: max(1, int(round(mag.float)))

# Identity of a configured effect filter graph: everything that determines the
# graph's topology and arguments, as a flat value so the per-frame reuse check
# is a field compare instead of string formatting. Run-constants (bg color,
# graph timebase) are deliberately excluded. A tuple, for structural `==`;
# `valid` is default-false so the zero key never matches a built graph.
type GraphKey = tuple
  valid: bool
  kind: ActionKind
  overlay: bool
  w, h, fmt: cint
  f0, f1, f2: float32
  i0, i1, i2, i3: int32
  col: uint32

func fxId(kind: ActionKind, frame: ptr AVFrame, overlay = false,
    f0 = 0'f32, f1 = 0'f32, f2 = 0'f32,
    i0 = 0'i32, i1 = 0'i32, i2 = 0'i32, i3 = 0'i32, col = 0'u32): GraphKey =
  (valid: true, kind: kind, overlay: overlay,
   w: frame.width, h: frame.height, fmt: frame.format,
   f0: f0, f1: f1, f2: f2, i0: i0, i1: i1, i2: i2, i3: i3, col: col)

func packRGB(c: RGBColor): uint32 =
  uint32(c.red) shl 16 or uint32(c.green) shl 8 or uint32(c.blue)

# Effects `confine` restricts to a region (adjustment effects only; geometry
# effects like zoom/rotate/pos are intentionally left full-frame).
const confinable = {actBlur, actBrightness, actLuv, actInvert, actErosion,
  actAberration, actPixelate}

func maskGray(a: Action): string =
  ## geq luma expression (0..255) for the matte: opaque inside the shape, black
  ## outside, with an optional `feather`-pixel soft edge; `invert` flips it.
  ## Shape from `mRadius`: -1 = ellipse, 0 = sharp rect, >0 = rounded-rect px.
  let f = a.mFeather.float
  let cx = a.mX.float + a.mW.float / 2
  let cy = a.mY.float + a.mH.float / 2
  var cover: string # 0..1 coverage, 1 = fully inside
  if a.mRadius < 0: # ellipse
    let rx = a.mW.float / 2
    let ry = a.mH.float / 2
    let rr2 = &"pow((X-{cx})/{rx},2)+pow((Y-{cy})/{ry},2)"
    if f <= 0:
      cover = &"lte({rr2},1)"
    else:
      # Feather (px) -> a normalized-radius band centered on the edge (r=1).
      let nf = f / ((rx + ry) / 2)
      cover = &"clip(0.5+(1-sqrt({rr2}))/{nf},0,1)"
  else:
    # Rounded-box signed distance (>0 outside, 0 on edge). r=0 is a sharp rect;
    # r is clamped to the half-extent so corners can't over-round.
    let hx = a.mW.float / 2
    let hy = a.mH.float / 2
    let r = min(a.mRadius.float, min(hx, hy))
    let qx = &"(abs(X-{cx})-{hx - r})"
    let qy = &"(abs(Y-{cy})-{hy - r})"
    let sdf = &"(hypot(max({qx},0),max({qy},0))+min(max({qx},{qy}),0)-{r})"
    if f <= 0:
      cover = &"lte({sdf},0)"
    else:
      # Ramp coverage across the f-px band centered on the edge (sdf=0).
      cover = &"clip(0.5-({sdf})/{f},0,1)"
  if a.mInvert: &"255*(1-({cover}))" else: &"255*({cover})"

# Keyframe index built from AVIndexEntry for efficient seeking
type KeyframeIndex = object
  frames: seq[int] # sorted list of keyframe frame numbers
  avgInterval: int # average interval between keyframes (for seek decisions)
  hasIndex: bool   # whether the demuxer provided index entries

func videoFrameToTimestamp*(frame: int, frameRate, streamTimebase: AVRational): int64 =
  ## Convert a source-frame index to the stream timestamp used for seeking.
  ## Keep this rational: truncating the duration of one frame accumulates a
  ## large timestamp error in long videos (e.g. 33 ms instead of 1001/30 ms).
  av_rescale_q(frame.int64, av_inv_q(frameRate), streamTimebase)

type SrcState = ref object
  kfFrames: seq[int]          # indexed keyframe frame numbers
  observedKeyframes: seq[int] # keyframes seen while decoding (for backward seeks)
  decoder: ptr AVCodecContext
  still: ptr AVFrame          # memoized decoded still; nil until first decode
  held: ptr AVFrame           # last decoded frame, held for forward reuse
  frameRate: AVRational       # source frames/second, also used for seek timestamps
  kfInterval: int             # average interval between indexed keyframes
  frameIndex: int             # decoder's current source position; -1 = none yet
  seekThreshold: int          # don't seek-ahead before this frame
  seekFrame: int              # frame we seeked from, for the frames-saved debug
  lastSeekTarget: int         # -1 = no seek performed yet
  lastReqIndex: int           # last obj.index requested (held-frame reuse)
  loopBase: int               # source frames consumed by completed loops
  hasKfIndex: bool            # whether the demuxer provided a keyframe index
  hasSeekFrame: bool          # whether seekFrame holds a pending marker
  isStill: bool               # single-frame image source (logo/watermark)

proc buildKeyframeIndex(stream: ptr AVStream, fps: float,
    defaultInterval: int): KeyframeIndex =
  ## Build a keyframe index from the stream's index entries.
  result.frames = @[]
  result.hasIndex = false
  result.avgInterval = defaultInterval

  let count = avformat_index_get_entries_count(stream)
  if count <= 0:
    return

  result.hasIndex = true
  let tb = stream.time_base
  let reorderDelay = max(stream.codecpar.video_delay.int, 0)

  for i in 0 ..< count:
    let entry = avformat_index_get_entry(stream, i)
    if entry != nil and entry.isKeyframe and entry.timestamp != AV_NOPTS_VALUE:
      let frameNum = int(round(
        float(entry.timestamp) * float(tb.num) / float(tb.den) * fps))

      # Be a bit conservative by adding video_deplay (the worst-case DTS/PTS gap), even
      # if some formats use PTS.
      result.frames.add(max(frameNum + reorderDelay, 0))

  if result.frames.len >= 2:
    var total = 0
    for i in 1 ..< result.frames.len:
      total += result.frames[i] - result.frames[i - 1]
    result.avgInterval = total div (result.frames.len - 1)

func toInt(r: AVRational): int =
  (r.num div r.den).int

proc reformat*(frame: ptr AVFrame, format: AVPixelFormat, width: cint = 0,
    height: cint = 0, ctx: ptr SwsContext = nil): ptr AVFrame =
  if frame == nil:
    return nil

  let srcFormat = AVPixelFormat(frame.format)
  let srcWidth = frame.width
  let srcHeight = frame.height
  let dstWidth = if width > 0: width else: srcWidth
  let dstHeight = if height > 0: height else: srcHeight

  if srcFormat == format and srcWidth == dstWidth and srcHeight == dstHeight:
    return frame

  let newFrame = av_frame_alloc()
  if newFrame == nil:
    error "Failed to allocate new frame"

  newFrame.format = format.cint
  newFrame.width = dstWidth
  newFrame.height = dstHeight
  newFrame.pts = frame.pts
  newFrame.time_base = frame.time_base
  newFrame.color_range = frame.color_range
  newFrame.color_primaries = frame.color_primaries
  newFrame.color_trc = frame.color_trc
  newFrame.colorspace = frame.colorspace

  var ret = av_frame_get_buffer(newFrame, 32)
  if ret < 0:
    error &"Failed to allocate buffer for new frame: {ret}"

  var ownedCtx: ptr SwsContext = nil
  let swsCtx =
    if ctx != nil:
      ctx
    else:
      ownedCtx = sws_alloc_context()
      if ownedCtx == nil:
        error "Failed to allocate sws context"
      # sws_alloc_context defaults to a single thread.
      discard av_opt_set_int(ownedCtx, "threads", 0, 0)
      ownedCtx

  ret = sws_scale_frame(swsCtx, newFrame, frame)

  if ownedCtx != nil:
    sws_free_context(addr ownedCtx)

  if ret < 0:
    error "Failed to scale frame"

  return newFrame

func toYuv(color: RGBColor): tuple[y, u, v: uint8] =
  ## BT.601 RGB -> YUV, shared by every solid-color write into a planar frame.
  let r = color.red.float
  let g = color.green.float
  let b = color.blue.float
  (uint8(clamp(0.299 * r + 0.587 * g + 0.114 * b, 0.0, 255.0)),
   uint8(clamp(-0.169 * r - 0.331 * g + 0.5 * b + 128, 0.0, 255.0)),
   uint8(clamp(0.5 * r - 0.419 * g - 0.081 * b + 128, 0.0, 255.0)))

proc makeClear(width: cint, height: cint): ptr AVFrame =
  ## A transparent RGBA canvas: the starting picture for a generator layer
  ## (`add:confetti`), so only what it draws survives the composite.
  let frame: ptr AVFrame = av_frame_alloc()
  if frame == nil:
    return nil
  frame.format = AV_PIX_FMT_RGBA.cint
  frame.width = width
  frame.height = height
  if av_frame_get_buffer(frame, 32) < 0:
    error "Bad buffer"
  if av_frame_make_writable(frame) < 0:
    error "Can't make frame writable"
  for y in 0 ..< height:
    zeroMem(cast[pointer](cast[int](frame.data[0]) + y.int * frame.linesize[0].int),
      width.int * 4)
  return frame

proc makeSolid(width: cint, height: cint, color: RGBColor): ptr AVFrame =
  let frame: ptr AVFrame = av_frame_alloc()
  if frame == nil:
    return nil

  frame.format = AV_PIX_FMT_YUV420P.cint
  frame.width = width
  frame.height = height

  if av_frame_get_buffer(frame, 32) < 0:
    error "Bad buffer"

  if av_frame_make_writable(frame) < 0:
    error "Can't make frame writable"

  let (yValue, uValue, vValue) = toYuv(color)

  let yData: ptr uint8 = frame.data[0]
  let yLinesize: cint = frame.linesize[0]

  for y in 0 ..< height:
    let row: ptr uint8 = cast[ptr uint8](cast[int](yData) + y.int * yLinesize.int)
    let rowArray = cast[ptr UncheckedArray[uint8]](row)
    for x in 0 ..< width:
      rowArray[x] = yValue

  let uData: ptr uint8 = frame.data[1]
  let uLinesize: cint = frame.linesize[1]

  for y in 0 ..< (height div 2):
    let row: ptr uint8 = cast[ptr uint8](cast[int](uData) + y.int * uLinesize.int)
    let rowArray = cast[ptr UncheckedArray[uint8]](row)
    for x in 0 ..< (width div 2):
      rowArray[x] = uValue

  let vData: ptr uint8 = frame.data[2]
  let vLinesize: cint = frame.linesize[2]

  for y in 0 ..< (height div 2):
    let row: ptr uint8 = cast[ptr uint8](cast[int](vData) + y.int * vLinesize.int)
    let rowArray = cast[ptr UncheckedArray[uint8]](row)
    for x in 0 ..< (width div 2):
      rowArray[x] = vValue

  return frame

# Indexed by ConfettiScheme, so the rows must stay in enum order.
const confettiPalettes: array[ConfettiScheme, seq[uint32]] = [
  @[0xff0040'u32, 0xff7a00'u32, 0xffe000'u32, 0x00e04b'u32, 0x0091ff'u32, 0xc800ff'u32],
  @[0x00fff0'u32, 0xff00d4'u32, 0xb6ff00'u32, 0xff7a00'u32, 0x9d00ff'u32],
  @[0xffd700'u32, 0xffb300'u32, 0xe0a63c'u32],
  @[0xff3366'u32, 0x33ccff'u32],
  @[0xffffff'u32],
]

func unpackRGB(v: uint32): RGBColor =
  RGBColor(red: uint8((v shr 16) and 0xff), green: uint8((v shr 8) and 0xff),
    blue: uint8(v and 0xff))

func towardWhite(c: RGBColor, t: float32): RGBColor =
  ## Mix `c` toward white by `t` in [0, 1].
  let f = clamp(t, 0.0'f32, 1.0'f32)
  func mix(v: uint8): uint8 =
    uint8(float32(v) + (255.0'f32 - float32(v)) * f)
  RGBColor(red: mix(c.red), green: mix(c.green), blue: mix(c.blue))

func hashUnit(i, salt: uint32): float32 =
  ## A value in [0, 1) for piece `i`, channel `salt`. A hash, not an RNG: no
  ## state to seed, and two renders of one command match.
  var h = i * 0x9E3779B1'u32 + salt * 0x85EBCA6B'u32 + 0x165667B1'u32
  h = (h xor (h shr 16)) * 0x7FEB352D'u32
  h = (h xor (h shr 15)) * 0x846CA68B'u32
  h = h xor (h shr 16)
  float32(h shr 8) / 16777216.0'f32

func launchFor(rise, k, vt: float32): float32 =
  ## Upward speed that peaks `rise` frame-heights above the start. Inverts
  ## `rise = (u - vt*ln(1 + u/vt)) / k`, which has no closed form: as x = u/vt it
  ## is `x - ln(1+x) = a`, seeded from its two limits and polished with Newton.
  if vt <= 1e-4'f32:
    return k * rise   # no gravity: the piece just coasts to a stop, at u/k
  let a = k * rise / vt
  var x = a + sqrt(2.0'f32 * a)
  for _ in 0 ..< 2:
    x -= (x - ln(1.0'f32 + x) - a) * (1.0'f32 + x) / x
  vt * x

const tau = 6.2831855'f32

type Chip = array[4, tuple[x, y: float32]]  # a piece's four corners

func chipOutline(n: uint32, rx, ry: float32, v: var Chip) =
  ## The piece's flat shape: a quad cut irregularly, so the burst is not a
  ## screenful of identical rectangles. Corners stay in their own quadrant, which
  ## keeps the outline convex for fillChip.
  const cx = [-1.0'f32, 1.0'f32, 1.0'f32, -1.0'f32]
  const cy = [-1.0'f32, -1.0'f32, 1.0'f32, 1.0'f32]
  for j in 0 ..< 4:
    let u = uint32(j)
    v[j] = (cx[j] * rx * (0.55'f32 + 0.45'f32 * hashUnit(n, 20 + u)),
            cy[j] * ry * (0.55'f32 + 0.45'f32 * hashUnit(n, 24 + u)))

type Cov = array[512, float32]
  ## Per-row coverage scratch. A chip spans at most ~0.05 of the frame height, so
  ## this holds one up to a ~10k-tall frame; wider than that just clips.

func chipArea(poly: Chip): float32 =
  var a = 0.0'f32
  for j in 0 ..< 4:
    let b = poly[(j + 1) and 3]
    a += poly[j].x * b.y - b.x * poly[j].y
  abs(a) * 0.5'f32

func addSpan(poly: Chip, yc: float32, x0, n: int, weight: float32,
    cov: var Cov) =
  ## Add `weight` times the polygon's horizontal coverage at height `yc` into
  ## `cov`, indexed from pixel `x0`. Exact in x: a pixel the span crosses partway
  ## takes only that fraction, which is what softens the left and right edges.
  var lo = 1e30'f32
  var hi = -1e30'f32
  for j in 0 ..< 4:
    let a = poly[j]
    let b = poly[(j + 1) and 3]
    # A horizontal edge fails at both ends, so the slope cannot divide by 0.
    if (a.y <= yc) != (b.y <= yc):
      let x = a.x + (yc - a.y) * (b.x - a.x) / (b.y - a.y)
      lo = min(lo, x)
      hi = max(hi, x)
  if lo >= hi:
    return
  for k in max(int(floor(lo)) - x0, 0) ..< min(int(ceil(hi)) - x0, n):
    let px = float32(x0 + k)
    let overlap = min(hi, px + 1.0'f32) - max(lo, px)
    if overlap > 0.0'f32:
      cov[k] += weight * overlap

proc fillChip(frame: ptr AVFrame, poly: Chip, color: RGBColor) =
  ## Draw the projected outline, blended by how much of each pixel it covers.
  ## Coverage comes from four sub-scanlines a row, each measured exactly in x, so
  ## both the sloped edges and the ends of a turning chip come out smooth.
  var xMin, xMax = poly[0].x
  var yMin, yMax = poly[0].y
  for j in 1 ..< 4:
    xMin = min(xMin, poly[j].x)
    xMax = max(xMax, poly[j].x)
    yMin = min(yMin, poly[j].y)
    yMax = max(yMax, poly[j].y)

  let x0 = max(int(floor(xMin)), 0)
  let y0 = max(int(floor(yMin)), 0)
  let x1 = min(int(ceil(xMax)) + 1, frame.width.int)
  let y1 = min(int(ceil(yMax)) + 1, frame.height.int)
  if x0 >= x1 or y0 >= y1:
    return
  let n = min(x1 - x0, 512)

  # Turned nearly edge-on, so it is thinner than the sub-scanline spacing and
  # sampling can miss it outright. Lay its area over the footprint, so a sliver
  # dims as it turns.
  let flat = xMax - xMin < 1.0'f32 or yMax - yMin < 1.0'f32
  let flatCov =
    if flat: clamp(chipArea(poly) / float32(n * (y1 - y0)), 0.0'f32, 1.0'f32)
    else: 0.0'f32

  let rgba = AVPixelFormat(frame.format) == AV_PIX_FMT_RGBA
  let (yv, uv, vv) = toYuv(color)
  var cov: array[2, Cov]

  # Paired luma rows, because both share one chroma row and it must only be
  # blended once.
  for cy in (y0 div 2) .. ((y1 - 1) div 2):
    var hit = false
    for half in 0 .. 1:
      let y = cy * 2 + half
      for k in 0 ..< n:
        cov[half][k] = 0.0'f32
      if y < y0 or y >= y1:
        continue
      if flat:
        for k in 0 ..< n:
          cov[half][k] = flatCov
        hit = flatCov > 0.0'f32
      else:
        for sub in 0 ..< 4:
          addSpan(poly, float32(y) + (float32(sub) + 0.5'f32) * 0.25'f32,
            x0, n, 0.25'f32, cov[half])
      let row = cast[ptr UncheckedArray[uint8]](
        cast[int](frame.data[0]) + y * frame.linesize[0].int)
      for k in 0 ..< n:
        let c = cov[half][k]
        if c <= 0.002'f32:
          continue
        hit = true
        let x = x0 + k
        if rgba:
          # Non-premultiplied source-over, so pieces layered on the clear canvas
          # of a generator layer keep a correct alpha.
          let dstA = float32(row[x * 4 + 3]) / 255.0'f32
          let outA = dstA + (1.0'f32 - dstA) * c
          if outA <= 0.0'f32:
            continue
          for ch, src in [color.red, color.green, color.blue]:
            let dst = float32(row[x * 4 + ch])
            row[x * 4 + ch] = uint8((float32(src) * c +
              dst * dstA * (1.0'f32 - c)) / outA + 0.5'f32)
          row[x * 4 + 3] = uint8(outA * 255.0'f32 + 0.5'f32)
        else:
          row[x] = uint8(float32(row[x]) * (1.0'f32 - c) +
            float32(yv) * c + 0.5'f32)
    if rgba or not hit:
      continue
    # Chroma is half resolution, so one sample stands for a 2x2 luma block. Take
    # the block's strongest coverage, or a thin sliver would lose its color.
    let uRow = cast[ptr UncheckedArray[uint8]](
      cast[int](frame.data[1]) + cy * frame.linesize[1].int)
    let vRow = cast[ptr UncheckedArray[uint8]](
      cast[int](frame.data[2]) + cy * frame.linesize[2].int)
    for cx in (x0 div 2) .. ((x1 - 1) div 2):
      var c = 0.0'f32
      for k in (cx * 2 - x0) .. (cx * 2 + 1 - x0):
        if k >= 0 and k < n:
          c = max(c, max(cov[0][k], cov[1][k]))
      if c <= 0.002'f32:
        continue
      uRow[cx] = uint8(float32(uRow[cx]) * (1.0'f32 - c) + float32(uv) * c + 0.5'f32)
      vRow[cx] = uint8(float32(vRow[cx]) * (1.0'f32 - c) + float32(vv) * c + 0.5'f32)

proc drawConfetti(frame: ptr AVFrame, act: Action, local: int, fps: float) =
  ## One frame of the confetti animation.
  ##
  ## Linear-drag ballistics: v(t) = vt + (v0 - vt)e^-kt for terminal velocity
  ## vt = g/k, so a piece arcs over and settles into a drift rather than
  ## accelerating off-screen. Lengths and speeds are fractions of the frame
  ## height, so the look is resolution-independent.
  let w = frame.width.float32
  let h = frame.height.float32
  let palette = confettiPalettes[act.cScheme]
  let t0 = float32(local) / float32(max(fps, 1.0))

  for i in 0 ..< act.cCount.int:
    let n = uint32(i) + uint32(act.cSeed) * 7919'u32
    let uPos = hashUnit(n, 1)
    let uSpeed = hashUnit(n, 2)
    let uAim = hashUnit(n, 3)
    let uSize = hashUnit(n, 4)
    let uSway = hashUnit(n, 5)
    let uSpin = hashUnit(n, 6)
    let uWhen = hashUnit(n, 7)
    let uShape = hashUnit(n, 9)
    let uTumble = hashUnit(n, 10)
    let uPhase = hashUnit(n, 11)
    let uRoll = hashUnit(n, 12)

    # Air resistance, 1/s, per piece: spread wide so the burst fans into a
    # ragged front instead of falling as one sheet.
    let k = 1.6'f32 + 3.2'f32 * hashUnit(n, 13)
    # Equal shove for all, so draggier pieces leave faster and brake sooner.
    let shove = 0.55'f32 + 0.45'f32 * (k / 3.2'f32)
    let vt = act.cGravity / k     # terminal fall speed, frame-heights/s

    # Apex as a fraction of the climb to just past the top edge. Solving the
    # throw from this keeps the height independent of gravity; squaring it piles
    # the burst low, so only the strongest pieces clear the frame.
    const overTop = 0.03'f32
    let reach = 0.52'f32 + 0.48'f32 * uSpeed * uSpeed

    var x0, y0, vx0, vy0: float32
    case act.cOrigin
    of coBottom:
      x0 = w * (0.02'f32 + 0.96'f32 * uPos)
      y0 = h * 1.02'f32
      vy0 = -launchFor(reach * (1.02'f32 + overTop), k, vt)
      vx0 = (uAim * 2.0'f32 - 1.0'f32) * 0.7'f32
    of coSides:
      # A wide fan, down to almost no sideways push, so some pieces climb and
      # fall along the edge instead of the sides emptying out.
      let right = (i mod 2) == 1
      let top = 0.90'f32 + 0.14'f32 * uPos
      x0 = (if right: w * 1.02'f32 else: w * -0.02'f32)
      y0 = h * top
      vy0 = -launchFor(reach * (top + overTop), k, vt)
      vx0 = (0.15'f32 + 3.0'f32 * uAim) * (if right: -1.0'f32 else: 1.0'f32)
    of coCenter:
      # Radial: the reach is measured against the piece thrown straight up.
      x0 = w * 0.5'f32
      y0 = h * 0.5'f32
      let angle = uPos * tau
      let speed = launchFor(reach * (0.5'f32 + overTop), k, vt)
      vx0 = cos(angle) * speed
      vy0 = sin(angle) * speed
    of coTop:
      x0 = w * (0.02'f32 + 0.96'f32 * uPos)
      y0 = h * -0.06'f32
      vy0 = (0.6'f32 + 0.5'f32 * uSpeed) * shove  # a release, not a throw
      vx0 = (uAim * 2.0'f32 - 1.0'f32) * 0.15'f32

    # Sideways only: scaling the climb would undo launchFor's fixed apex.
    vx0 *= shove

    # Fired once per section, nothing replaced after it falls out. The stagger is
    # short against the whole burst, so it rips out but still reads as one pop.
    let t = t0 - uWhen * 0.4'f32
    if t <= 0.0'f32:
      continue

    let decay = (1.0'f32 - exp(-k * t)) / k
    let sway = h * (0.010'f32 + 0.020'f32 * uSway)
    let freq = 0.5'f32 + uSpin
    let px = x0 + vx0 * decay * h + sway * sin(tau * freq * t + uSway * tau)
    let py = y0 + (vt * t + (vy0 - vt) * decay) * h

    let size = h * (0.024'f32 + 0.024'f32 * uSize)

    # Phrased positively so a non-finite piece is dropped rather than reaching
    # an unchecked float -> int conversion. `size` bounds the outline.
    if not (px + size >= 0.0'f32 and px - size <= w and
            py + size >= 0.0'f32 and py - size <= h):
      continue

    # Spin in-plane (Rz) while tumbling end over end (Rx) and edge to edge (Ry).
    # The chip is flat, so local z = 0 collapses the three matrices to this;
    # dropping z projects it, foreshortening a chip that turns away.
    let spinZ = (1.5'f32 + 4.0'f32 * uSpin) * t + uPhase * tau
    let turnX = (2.0'f32 + 5.0'f32 * uTumble) * t + uSize * tau
    let turnY = (1.5'f32 + 4.0'f32 * uRoll) * t + uAim * tau
    let ca = cos(spinZ)
    let sa = sin(spinZ)
    let cb = cos(turnX)
    let sb = sin(turnX)
    let cc = cos(turnY)
    let sc = sin(turnY)

    var poly: Chip   # uShape sets the proportions: narrow strip to near-square
    chipOutline(n, size * 0.5'f32, size * (0.22'f32 + 0.28'f32 * uShape), poly)
    for j in 0 ..< 4:
      let lx = poly[j].x * ca - poly[j].y * sa
      let ly = poly[j].x * sa + poly[j].y * ca
      poly[j] = (px + lx * cc + ly * sb * sc, py + ly * cb)

    let idx = min(palette.len - 1, int(hashUnit(n, 8) * float32(palette.len)))
    var color = unpackRGB(palette[idx])
    if act.cShimmer:
      # cb*cc is how square-on the chip is to the viewer, so near 0 is edge-on:
      # the angle that catches a light off to the side. Ramped, so the glint
      # rolls through the turn.
      const glintBelow = 0.25'f32
      let facing = abs(cb * cc)
      if facing < glintBelow:
        color = towardWhite(color, (glintBelow - facing) / glintBelow)
    fillChip(frame, poly, color)

proc scaleWithPad(src: ptr AVFrame, targetW, targetH: int32,
    bg: RGBColor): ptr AVFrame =
  ## Scale src to fit within targetW x targetH preserving aspect ratio,
  ## centering with bg color padding. Returns a new YUV420P frame.
  ## Uses sws_scale_frame + manual pixel copy to avoid filter graph NEON
  ## crashes on Windows ARM64.
  let srcW = src.width
  let srcH = src.height

  # Compute fitted dims (equivalent to scale=force_original_aspect_ratio=decrease)
  var scaledW = targetW
  var scaledH = targetH
  if srcW.int * targetH.int > srcH.int * targetW.int:
    scaledH = cint((srcH.int * targetW.int) div srcW.int) and not 1.cint
    if scaledH < 2: scaledH = 2
  elif srcH.int * targetW.int > srcW.int * targetH.int:
    scaledW = cint((srcW.int * targetH.int) div srcH.int) and not 1.cint
    if scaledW < 2: scaledW = 2

  var output = makeSolid(targetW, targetH, bg)
  if output == nil:
    error "Could not create background frame in scaleWithPad"
  output.pts = src.pts
  output.time_base = src.time_base

  # Scale + convert to YUV420P. Use a valid sws context but don't pre-allocate
  # the destination buffer — sws_scale_frame calls av_frame_get_buffer itself
  # when dst->data[0] is null, which avoids failures with unusual source frame
  # layouts (e.g. dvvideo). A nil context is not safe in FFmpeg 8.1+.
  var scaled = av_frame_alloc()
  if scaled == nil:
    av_frame_free(addr output)
    error "Could not allocate scaled frame"
  scaled.format = AV_PIX_FMT_YUV420P.cint
  scaled.width = scaledW
  scaled.height = scaledH
  # Propagate interlaced flags so sws_frame_setup doesn't reject mismatched frames.
  # AV_FRAME_FLAG_INTERLACED = 1<<3, AV_FRAME_FLAG_TOP_FIELD_FIRST = 1<<4
  scaled.flags = src.flags and (8 or 16).cint
  var swsCtx = sws_alloc_context()
  if swsCtx == nil:
    av_frame_free(addr scaled)
    av_frame_free(addr output)
    error "Could not allocate sws context in scaleWithPad"
  discard av_opt_set_int(swsCtx, "threads", 0, 0)
  let scaleRet = sws_scale_frame(swsCtx, scaled, src)
  sws_free_context(addr swsCtx)
  if scaleRet < 0:
    av_frame_free(addr scaled)
    av_frame_free(addr output)
    error &"Could not scale frame in scaleWithPad: {scaleRet}"

  # Even pixel offsets required for YUV420P chroma subsampling
  let ox = ((targetW - scaledW) div 2) and not 1.cint
  let oy = ((targetH - scaledH) div 2) and not 1.cint

  for y in 0 ..< scaled.height.int:
    let sp = cast[pointer](cast[int](scaled.data[0]) + y * scaled.linesize[0].int)
    let dp = cast[pointer](cast[int](output.data[0]) + (oy.int + y) * output.linesize[
        0].int + ox.int)
    copyMem(dp, sp, scaled.width.int)

  for y in 0 ..< (scaled.height div 2).int:
    let sp = cast[pointer](cast[int](scaled.data[1]) + y * scaled.linesize[1].int)
    let dp = cast[pointer](cast[int](output.data[1]) + ((oy div 2).int + y) *
        output.linesize[1].int + (ox div 2).int)
    copyMem(dp, sp, (scaled.width div 2).int)

  for y in 0 ..< (scaled.height div 2).int:
    let sp = cast[pointer](cast[int](scaled.data[2]) + y * scaled.linesize[2].int)
    let dp = cast[pointer](cast[int](output.data[2]) + ((oy div 2).int + y) *
        output.linesize[2].int + (ox div 2).int)
    copyMem(dp, sp, (scaled.width div 2).int)

  av_frame_free(addr scaled)
  return output

func scaledVideoResolution*(resolution: (int32, int32),
    scale: float64): (int32, int32) =
  if scale == 1.0:
    return resolution
  (
    max(int32(round(resolution[0].float64 * scale)) and not 1'i32, 2),
    max(int32(round(resolution[1].float64 * scale)) and not 1'i32, 2),
  )

proc makeNewVideoFrames*(output: var OutputContainer, tl: v3, args: mainArgs,
    myCache: MediaCache):
    (ptr AVCodecContext, ptr AVStream, iterator(): (ptr AVFrame, int64)) =

  # One state object per source (decoders, seek bookkeeping, still/held frame
  # caches, loop accounting). Still-image sources (overlay logos/watermarks)
  # decode a single frame that is held for the clip's whole duration in `still`.
  var srcs = initTable[ptr string, SrcState]()
  # Within a single timeline frame, two layers can reference the same source at
  # the same source-frame index (e.g. a clip composited over itself). The shared
  # per-source decoder can only be at one position, so memoize the raw decoded
  # frame per (src, index) for the duration of one timeline frame; cleared at the
  # top of each iteration.
  var decodedCache = initTable[(ptr string, int), ptr AVFrame]()

  var pix_fmt = AV_PIX_FMT_YUV420P
  let targetFps = tl.tb

  # Reference source for encoder config (color/pix_fmt/SAR): the base video
  # layer's first clip. Don't derive this from uniqueSources iteration order,
  # which is pointer-hash order over `ptr string` keys and so varies run-to-run
  # (e.g. an `add:` overlay image could win over the actual video).
  var firstSrc: ptr string = nil
  if tl.v.len > 0 and tl.v[0].len > 0:
    firstSrc = tl.v[0][0].src

  for src in tl.uniqueSources:
    # getContainer turns a missing/unreadable source (e.g. `add:gone.mp4`)
    # into a clean error instead of an unhandled IOError.
    discard myCache.getContainer(src)

    # Per-source state with mutable-decode defaults. Decoding always begins on a
    # keyframe, so frame 0 is always a valid seek point (observedKeyframes starts
    # at @[0]); decoder/isStill below fill in for sources that have a video stream.
    srcs[src] = SrcState(frameIndex: -1, seekThreshold: 10,
      observedKeyframes: @[0], lastSeekTarget: -1, lastReqIndex: -1, loopBase: 0)

    # Audio-only sources (e.g. the .mp3 behind a synthesized video canvas) have
    # no video stream to decode.
    if myCache.cns[src].video.len == 0:
      continue
    if firstSrc == nil:
      firstSrc = src

    let decoderCtx = initDecoder(myCache.cns[src].video[0].codecpar)
    decoderCtx.thread_type = FF_THREAD_FRAME or FF_THREAD_SLICE
    srcs[src].decoder = decoderCtx

    # An image source is a single still: known image codec, or a stream that
    # reports exactly one frame (single-frame webp, png_pipe, etc.).
    let vstream = myCache.cns[src].video[0]
    let imageCodecs = [ID_PNG, ID_JPEG, ID_WEBP, ID_BMP, ID_TIFF]
    srcs[src].isStill = vstream.codecpar.codec_id in imageCodecs or
      vstream.nb_frames == 1

  let (targetWidth, targetHeight) = scaledVideoResolution(tl.res, args.scale)
  var fxGraph: Graph = nil
  var fxKey: GraphKey
  var rotGraph: Graph = nil # static source rotation, applied before the fit
  var rotKey: GraphKey
  # Cached mask/confine mattes (gray8), rebuilt only when the region/size changes
  # so the per-pixel geq runs once, not every frame.
  var maskMatte: ptr AVFrame = nil
  var maskMatteKey: GraphKey
  var confineMatte: ptr AVFrame = nil
  var confineMatteKey: GraphKey
  let needsScaling = args.scale != 1.0

  debug &"Creating video stream with codec: {args.videoCodec}"
  var (outputStream, encoderCtx) = output.addStream(args.videoCodec, targetFps,
      lang = tl.langs[0], width = targetWidth, height = targetHeight)
  var codec = encoderCtx.codec

  if codec.id == ID_HEVC:
    const codecTag = fourccToInt("hvc1") # for QuickTime
    outputStream.codecpar.codec_tag = codecTag
    encoderCtx.codec_tag = codecTag

  encoderCtx.framerate = targetFps
  encoderCtx.thread_type = FF_THREAD_FRAME or FF_THREAD_SLICE

  # For encoder config (colorspace/SAR/pix_fmt) prefer a real, non-still video
  # source. An audio-only `add` timeline may have only still images over a
  # synthesized background, in which case yuv420p defaults are used.
  for s in tl.uniqueSources:
    if myCache.cns[s].video.len > 0 and not srcs[s].isStill:
      firstSrc = s
      break

  # Don't inherit color tags / SAR from a still image. PNGs are tagged full-range
  # (which makes the H.264 encoder emit deprecated yuvj420p), so when the only
  # reference is a still (e.g. an audio-only `add` over a synthesized canvas),
  # keep the encoder's limited-range yuv420p defaults instead. firstSrc is nil
  # when nothing in the timeline carries video at all, e.g. audio plus a lone
  # `add:confetti` generator; the same defaults cover that.
  if firstSrc != nil and not srcs[firstSrc].isStill:
    let src = myCache.cns[firstSrc]
    let color_range = src.video[0].codecpar.color_range
    let colorspace = src.video[0].codecpar.color_space
    let color_prim = src.video[0].codecpar.color_primaries
    let color_trc = src.video[0].codecpar.color_trc

    if color_range in [1, 2]:
      encoderCtx.color_range = color_range
    if colorspace in [0, 1] or (colorspace >= 3 and colorspace < 16):
      encoderCtx.colorspace = colorspace
    if color_prim == 1 or (color_prim >= 4 and color_prim < 17):
      encoderCtx.color_primaries = color_prim
    if color_trc == 1 or (color_trc >= 4 and color_trc < 22):
      encoderCtx.color_trc = color_trc

    let sar = src.video[0].codecpar.sample_aspect_ratio
    if sar.isValid:
      encoderCtx.sample_aspect_ratio = sar

  # The format frames will arrive in, or NONE when the timeline carries no video
  # source at all and every frame is synthesized.
  let srcPixFmt =
    if firstSrc != nil: AVPixelFormat(myCache.cns[firstSrc].video[0].codecpar.format)
    else: AV_PIX_FMT_NONE

  if args.videoBitrate >= 0:
    encoderCtx.bit_rate = args.videoBitrate
    debug(&"video bitrate: {encoderCtx.bit_rate}")
  else:
    debug(&"[auto] video bitrate: {encoderCtx.bit_rate}")

  for src, cn in myCache.cns:
    if len(cn.video) > 0 and src in srcs:
      let st = srcs[src]
      let stream = cn.video[0]
      let defaultInterval = toInt(targetFps * AVRational(num: 5, den: 1))

      # avg_frame_rate can be 0/0 for streams with no declared frame rate; use
      # the timeline rate for both frame indexing and seek timestamp conversion.
      st.frameRate =
        if stream.avg_frame_rate.isValid: stream.avg_frame_rate else: targetFps
      let fps = st.frameRate.float

      if args.noSeek:
        st.kfFrames = @[]
        st.hasKfIndex = false
        st.kfInterval = high(int)
      else:
        let kf = buildKeyframeIndex(stream, fps, defaultInterval)
        st.kfFrames = kf.frames
        st.kfInterval = kf.avgInterval
        st.hasKfIndex = kf.hasIndex
        if kf.hasIndex:
          debug &"Source {src[]}: {kf.frames.len} keyframes indexed, avg interval: {kf.avgInterval} frames"
        else:
          debug &"Source {src[]}: no index entries, using estimated interval: {kf.avgInterval} frames"

      if src == firstSrc and not st.isStill and
          encoderCtx.pix_fmt != AV_PIX_FMT_NONE:
        pix_fmt = AVPixelFormat(cn.video[0].codecpar.format)

  let userFmt = args.pixFmt != ""
  if userFmt:
    pix_fmt = av_get_pix_fmt(cstring(args.pixFmt))
    if pix_fmt == AV_PIX_FMT_NONE:
      error &"Unknown pixel format: {args.pixFmt}"

  let pixFmts = codec.supportedPixFmts
  var needValidFmt = true
  if pixFmts != nil:
    var i = 0
    while pixFmts[i].cint != -1:
      if pix_fmt == pixFmts[i]:
        needValidFmt = false
        break
      i += 1

  if needValidFmt:
    # A format the user asked for by name must not be silently swapped.
    if userFmt and pixFmts != nil:
      error &"Encoder {codec.name} does not support pixel format: {args.pixFmt}"
    if pixFmts != nil:
      let best = avcodec_find_best_pix_fmt_of_list(pixFmts, pix_fmt, 0, nil)
      pix_fmt = if best != AV_PIX_FMT_NONE: best else: AV_PIX_FMT_YUV420P
    else:
      pix_fmt = AV_PIX_FMT_YUV420P

  if args.vprofile != "":
    encoderCtx.setProfileOrErr(args.vprofile)

  encoderCtx.pix_fmt = pix_fmt
  resolveEncoderContext(encoderCtx)
  codec = encoderCtx.codec

  if codec.id == ID_HEVC:
    discard av_opt_set(encoderCtx.priv_data, "x265-params", "log-level=error", 0)
  if args.crf >= 0:
    discard av_opt_set_int(encoderCtx.priv_data, "crf", args.crf.cint, 0)
  if args.preset != "":
    discard av_opt_set(encoderCtx.priv_data, "preset", cstring(args.preset), 0)

  if args.gop >= 1:
    encoderCtx.gop_size = args.gop.cint
  elif args.fragmented and not args.noFragmented:
    # frag_keyframe only cuts a fragment at a keyframe, so the default keyint
    # would hold back the first fragment for seconds of media.
    encoderCtx.gop_size = max(1, int(round(tl.tb.float))).cint

  encoderCtx.open()
  pix_fmt = encoderCtx.pix_fmt
  if avcodec_parameters_from_context(outputStream.codecpar, encoderCtx) < 0:
    error "Could not copy encoder parameters to stream"

  let templateVid =
    if tl.templateFile != nil: myCache.getContainer(tl.templateFile).video
    else: @[]
  if templateVid.len > 0:
    let srcPar = templateVid[0].codecpar
    let sd = av_packet_side_data_get(srcPar.coded_side_data,
        srcPar.nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX)
    if sd != nil and sd.size > 0:
      let dstPar = outputStream.codecpar
      let dst = av_packet_side_data_new(addr dstPar.coded_side_data,
          addr dstPar.nb_coded_side_data, AV_PKT_DATA_DISPLAYMATRIX, sd.size, 0)
      if dst != nil:
        copyMem(dst.data, sd.data, sd.size)

  let graphTb = av_inv_q(targetFps)
  let bg = tl.bg.toString

  proc bufArgsOf(frame: ptr AVFrame): string =
    ## Buffer-source args for feeding `frame` into a graph; only built when a
    ## graph is actually (re)configured, never on the per-frame reuse path.
    &"video_size={frame.width}x{frame.height}:pix_fmt={$AVPixelFormat(frame.format)}:time_base={graphTb}:pixel_aspect=1/1"

  # Scaling has stable input/output geometry, so keep one libswscale
  # context instead of sending every frame through a filter graph.
  var scaleCtx: ptr SwsContext = nil
  if needsScaling:
    scaleCtx = sws_alloc_context()
    if scaleCtx == nil:
      error "Failed to allocate proxy scale sws context"
    discard av_opt_set_int(scaleCtx, "threads", 0, 0)

  # Create a persistent sws context for the per-frame pixel format conversion.
  # Reusing it avoids the per-frame alloc/init overhead of the new sws API.
  var reformatCtx: ptr SwsContext = nil
  if pix_fmt != srcPixFmt:
    reformatCtx = sws_alloc_context()
    if reformatCtx == nil:
      error "Failed to allocate reformat sws context"
    discard av_opt_set_int(reformatCtx, "threads", 0, 0)

  var framesSaved = 0

  var nullFrame = makeSolid(targetWidth, targetHeight, tl.bg)
  if nullFrame == nil:
    error "Could not allocate fallback video frame"
  var frame: ptr AVFrame = av_frame_clone(nullFrame)
  var objList: seq[VideoFrame] = @[]
  var lastProcessedFrame: ptr AVFrame = nil
  var lastFrameIndex = -1
  let isLinear = tl.isLinear

  debug &"isLinear: {isLinear}"

  proc keyOverBg(frame0: ptr AVFrame, effect: Action): ptr AVFrame =
    var frame = frame0
    let w = frame.width
    let h = frame.height
    let col = effect.color.toString
    let isChroma = effect.kind == actChromaKey
    var bgFrame = makeSolid(w, h, tl.bg)
    frame.pts = 0
    bgFrame.pts = 0
    let g = newGraph()
    let bgSrc = g.add("buffer", bufArgsOf(bgFrame))
    let fgSrc = g.add("buffer", bufArgsOf(frame))
    let toAlpha = g.add("format", "pix_fmts=" & (if isChroma: "yuva420p" else: "rgba"))
    let keyer = g.add((if isChroma: "chromakey" else: "colorkey"),
      &"{col}:{effect.similar}:{effect.blend}")
    let ov = g.add("overlay", "format=yuv420")
    discard g.linkNodes(@[fgSrc, toAlpha, keyer])
    g.link(bgSrc, ov, 0, 0) # background on the bottom pad
    g.link(keyer, ov, 0, 1) # keyed frame on top
    g.link(ov, g.add("buffersink"))
    g.configure()
    g.pushIdx(0, bgFrame)
    g.pushIdx(1, frame)
    g.flushIdx(0)
    g.flushIdx(1)
    result = g.pull()
    g.cleanup()
    av_frame_free(addr bgFrame)
    av_frame_free(addr frame)

  proc buildMaskMatte(w, h: cint, effect: Action): ptr AVFrame =
    ## A gray8 matte: white where the mask/effect applies, black elsewhere, with
    ## a feathered ramp between. Built once per (region, size) and cached.
    var black = makeSolid(w, h, RGBColor(red: 0, green: 0, blue: 0))
    black.pts = 0
    let g = newGraph()
    let src = g.add("buffer", bufArgsOf(black))
    let geq = g.add("geq", &"lum={maskGray(effect)}")
    let toGray = g.add("format", "pix_fmts=gray8")
    let sink = g.add("buffersink")
    g.linkNodes(@[src, geq, toGray, sink]).configure()
    g.push(black)
    result = g.pull()
    g.cleanup()
    av_frame_free(addr black)

  proc cachedMatte(cache: var ptr AVFrame, key: var GraphKey,
      frame: ptr AVFrame, effect: Action): ptr AVFrame =
    ## Return the cached matte for `effect` at `frame`'s size, rebuilding only
    ## when the region/feather/size changes. Caller must NOT free the result.
    let k = fxId(effect.kind, frame, f0 = effect.mRadius.float32,
        i0 = effect.mX, i1 = effect.mY, i2 = effect.mW, i3 = effect.mH,
        col = (if effect.mInvert: 0x100'u32 else: 0'u32) or
          (uint32(effect.mFeather) shl 16))
    if cache == nil or key != k:
      if cache != nil: av_frame_free(addr cache)
      cache = buildMaskMatte(frame.width, frame.height, effect)
      key = k
    cache

  proc alphamergeOnto(frame0, matte: ptr AVFrame): ptr AVFrame =
    ## Set `frame`'s alpha from the gray matte (cheap; no per-pixel geq).
    var frame = frame0
    frame.pts = 0
    var m = av_frame_clone(matte) # cached matte; push a fresh ref
    m.pts = 0
    let g = newGraph()
    let fSrc = g.add("buffer", bufArgsOf(frame))
    let mSrc = g.add("buffer", bufArgsOf(m))
    let toGbrp = g.add("format", "pix_fmts=gbrp")
    let am = g.add("alphamerge")
    let toRgba = g.add("format", "pix_fmts=rgba")
    let sink = g.add("buffersink")
    discard g.linkNodes(@[fSrc, toGbrp])
    g.link(toGbrp, am, 0, 0)
    g.link(mSrc, am, 0, 1)
    g.link(am, toRgba)
    g.link(toRgba, sink)
    g.configure()
    g.pushIdx(0, frame)
    g.pushIdx(1, m)
    g.flushIdx(0)
    g.flushIdx(1)
    result = g.pull()
    g.cleanup()
    av_frame_free(addr m)
    av_frame_free(addr frame)

  proc overBg(frame0: ptr AVFrame): ptr AVFrame =
    ## Flatten an alpha-shaped rgba frame over a solid `-bg` (base-track mask).
    var top = frame0
    var bgFrame = makeSolid(top.width, top.height, tl.bg)
    top.pts = 0
    bgFrame.pts = 0
    let g = newGraph()
    let bgSrc = g.add("buffer", bufArgsOf(bgFrame))
    let fgSrc = g.add("buffer", bufArgsOf(top))
    let ov = g.add("overlay", "format=yuv420")
    g.link(bgSrc, ov, 0, 0)
    g.link(fgSrc, ov, 0, 1)
    g.link(ov, g.add("buffersink"))
    g.configure()
    g.pushIdx(0, bgFrame)
    g.pushIdx(1, top)
    g.flushIdx(0)
    g.flushIdx(1)
    result = g.pull()
    g.cleanup()
    av_frame_free(addr bgFrame)
    av_frame_free(addr top)

  proc maskedMergeRegion(saved, effected, matte: ptr AVFrame): ptr AVFrame =
    ## Merge `effected` over `saved` weighted by the gray `matte` (in gbrp, so
    ## the per-plane merge is clean), then back to the original format.
    let origFmt = AVPixelFormat(saved.format)
    saved.pts = 0
    effected.pts = 0
    var m = av_frame_clone(matte) # cached matte; push a fresh ref
    m.pts = 0
    let g = newGraph()
    let bSrc = g.add("buffer", bufArgsOf(saved))
    let oSrc = g.add("buffer", bufArgsOf(effected))
    let mSrc = g.add("buffer", bufArgsOf(m))
    let bFmt = g.add("format", "pix_fmts=gbrp")
    let oFmt = g.add("format", "pix_fmts=gbrp")
    let mFmt = g.add("format", "pix_fmts=gbrp")
    let mm = g.add("maskedmerge")
    let toOrig = g.add("format", &"pix_fmts={$origFmt}")
    let sink = g.add("buffersink")
    discard g.linkNodes(@[bSrc, bFmt])
    discard g.linkNodes(@[oSrc, oFmt])
    discard g.linkNodes(@[mSrc, mFmt])
    g.link(bFmt, mm, 0, 0)
    g.link(oFmt, mm, 0, 1)
    g.link(mFmt, mm, 0, 2)
    g.link(mm, toOrig)
    g.link(toOrig, sink)
    g.configure()
    g.pushIdx(0, saved)
    g.pushIdx(1, effected)
    g.pushIdx(2, m)
    g.flushIdx(0)
    g.flushIdx(1)
    g.flushIdx(2)
    result = g.pull()
    g.cleanup()
    av_frame_free(addr m)

  proc applyEffects(frame0: ptr AVFrame, effects: Actions, local, clipDur: int,
      isOverlay = false): ptr AVFrame =
    ## Apply one clip's effect chain to a frame, returning the (possibly new)
    ## frame. Shared by the single-layer path and per-clip compositing. `isOverlay`
    ## is true for higher composited layers, which want transparent (not bg) fill
    ## from `spin`.
    var frame = frame0
    let fps = tl.tb.float
    # `confine` state: the active region's matte (lazily (re)built at the frame
    # size of the next confined effect) and whether this iteration's effect is
    # restricted to it.
    var confineActive = false
    var confineThis = false
    var confineEffect: Action
    # Eased progress in [0, 1] for an animated action, using its own packed
    # easing curve + duration (defaults to linear over the whole clip).
    template prog(e: Action): float32 =
      applyEase(e.easeCurve,
        clipT(local, envAnimLen(e.easeDurUnit, e.easeDur, clipDur, fps)))

    # Run `frame` through the effect graph identified by `key`, reusing the
    # previous graph when the key matches; `build` must add nodes to `fxGraph`
    # and configure it. When the active `confine` covers this effect, run it on a
    # copy and merge only the masked region back over the untouched frame.
    template runFx(key: GraphKey, build: untyped) =
      let k = key
      if fxKey != k:
        if fxGraph != nil:
          fxGraph.cleanup()
        fxGraph = newGraph()
        build
        fxKey = k
      if confineThis:
        let matte = cachedMatte(confineMatte, confineMatteKey, frame, confineEffect)
        let saved = av_frame_clone(frame)
        fxGraph.push(frame)
        av_frame_free(addr frame)
        let effected = fxGraph.pull()
        frame = maskedMergeRegion(saved, effected, matte)
        av_frame_free(addr saved)
        av_frame_free(addr effected)
      else:
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()

    for effect in effects:
      confineThis = confineActive and effect.kind in confinable
      case effect.kind:
      of actSpeed, actVarispeed, actVolume, actDeesser, actDuck, actPitch, actPos,
          actRotate, actLoop: discard
      of actSpin:
        let rate = effect.sRate
        let startDeg = rotDeg(effect.sStart)
        let w = frame.width
        let h = frame.height
        frame.pts = local.int64
        runFx(fxId(actSpin, frame, overlay = isOverlay, f0 = startDeg, f1 = rate)):
          # Spin within a constant square sized to the diagonal, so no angle clips
          # the picture. Overlays fill the exposed corners transparently (only the
          # picture shows over the base); the base layer fills them with bg.
          let side = cint(int(ceil(hypot(w.float, h.float))) + 1) and not 1.cint
          let aExpr = &"a=({startDeg}+({rate})*t)*PI/180:ow={side}:oh={side}"
          var nodes: seq[ptr AVFilterContext] =
            @[fxGraph.add("buffer", bufArgsOf(frame))]
          if isOverlay:
            # Convert to rgba first so the rotate fill (and exposed corners) can
            # be transparent.
            nodes.add fxGraph.add("format", "pix_fmts=rgba")
            nodes.add fxGraph.add("rotate", aExpr & ":c=black@0")
          else:
            nodes.add fxGraph.add("rotate", aExpr & &":c={bg}")
          nodes.add fxGraph.add("buffersink")
          fxGraph.linkNodes(nodes).configure()
        if not isOverlay:
          # Base layer must stay canvas-sized: shrink the contained square back
          # to the original frame size, centered with bg padding.
          let fitted = scaleWithPad(frame, w, h, tl.bg)
          if fitted != frame:
            av_frame_free(addr frame)
            frame = fitted
      of actZoom:
        let z = sampleKf(effect.kf, prog(effect))
        if z == 1.0:
          continue
        let origW = frame.width
        let origH = frame.height
        let scaledW = max(cint(float(origW) * z), 2)
        let scaledH = max(cint(float(origH) * z), 2)
        let scaledFrame = frame.reformat(AVPixelFormat(frame.format), scaledW, scaledH)
        if scaledFrame != frame:
          av_frame_free(addr frame)
          frame = scaledFrame
        let zoomCrop = z > 1.0
        runFx(fxId(actZoom, frame, i0 = origW.int32, i1 = origH.int32,
            i2 = (if zoomCrop: 1'i32 else: 0'i32))):
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let mid =
            if zoomCrop: fxGraph.add("crop", &"{origW}:{origH}")
            else: fxGraph.add("pad", &"{origW}:{origH}:-1:-1:color={bg}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, mid, bufferSink]).configure()
      of actHflip, actVflip, actInvert, actErosion:
        runFx(fxId(effect.kind, frame)):
          let filterName = case effect.kind
            of actHflip: "hflip"
            of actVflip: "vflip"
            of actErosion: "erosion"
            else: "negate"
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let filt = fxGraph.add(filterName)
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
      of actBlur:
        let sigma = sampleKf(effect.kf, prog(effect))
        if sigma <= 0.0:
          continue
        runFx(fxId(actBlur, frame, f0 = sigma)):
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let filt = fxGraph.add("gblur", &"sigma={sigma}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
      of actBrightness:
        let b = sampleKf(effect.kf, prog(effect))
        if b == 0.0'f32:
          continue
        let shift = b * 255.0'f32
        runFx(fxId(actBrightness, frame, f0 = shift)):
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let toRgb = fxGraph.add("format", "pix_fmts=rgb24")
          let expr = brightnessLutExpr(b)
          let lut = fxGraph.add("lutrgb", &"r={expr}:g={expr}:b={expr}")
          let toOrig = fxGraph.add("format", &"pix_fmts={$AVPixelFormat(frame.format)}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, toRgb, lut, toOrig, bufferSink]).configure()
      of actLuv:
        if (effect.brighthue == luvBrighthueId and
            effect.contrast == luvContrastId and
            effect.saturation == luvSaturationId):
          continue

        let b = effect.brighthue
        let c = effect.contrast
        let s = effect.saturation
        runFx(fxId(actLuv, frame, f0 = b, f1 = c, f2 = s)):
          let expr = luvLutExprs(b, c, s)
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let toYuv = fxGraph.add("format", "pix_fmts=yuv444p")
          let lut = fxGraph.add("lutyuv", &"y={expr.y}:u={expr.u}:v={expr.v}")
          let toOrig = fxGraph.add("format", &"pix_fmts={$AVPixelFormat(frame.format)}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, toYuv, lut, toOrig, bufferSink]).configure()
      of actOpacity:
        let o = sampleKf(effect.kf, prog(effect))
        if o >= 1.0'f32:
          continue
        if isOverlay:
          runFx(fxId(actOpacity, frame, overlay = true, f0 = o)):
            let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
            let toRgba = fxGraph.add("format", "pix_fmts=rgba")
            let lut = fxGraph.add("lutrgb", &"a=val*{o}")
            let bufferSink = fxGraph.add("buffersink")
            fxGraph.linkNodes(@[bufferSrc, toRgba, lut, bufferSink]).configure()
        else:
          runFx(fxId(actOpacity, frame, f0 = o)):
            let bgR = (1.0'f32 - o) * float32(tl.bg.red)
            let bgG = (1.0'f32 - o) * float32(tl.bg.green)
            let bgB = (1.0'f32 - o) * float32(tl.bg.blue)
            let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
            let toRgb = fxGraph.add("format", "pix_fmts=rgb24")
            let lut = fxGraph.add("lutrgb",
              &"r=val*{o}+{bgR}:g=val*{o}+{bgG}:b=val*{o}+{bgB}")
            let toOrig = fxGraph.add("format",
                &"pix_fmts={$AVPixelFormat(frame.format)}")
            let bufferSink = fxGraph.add("buffersink")
            fxGraph.linkNodes(@[bufferSrc, toRgb, lut, toOrig, bufferSink]).configure()
      of actLens:
        let k1 = effect.k1
        let k2 = effect.k2
        if k1 == 0.0'f32 and k2 == 0.0'f32:
          continue
        runFx(fxId(actLens, frame, f0 = k1, f1 = k2)):
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let filt = fxGraph.add("lenscorrection", &"k1={k1}:k2={k2}:fc={bg}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
      of actDrawbox:
        runFx(fxId(actDrawbox, frame, i0 = effect.dbX, i1 = effect.dbY,
            i2 = effect.dbW, i3 = effect.dbH, col = packRGB(effect.dbColor))):
          let col = effect.dbColor.toString
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let filt = fxGraph.add("drawbox",
            &"x={effect.dbX}:y={effect.dbY}:w={effect.dbW}:h={effect.dbH}:color={col}:t=fill")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
      of actColorKey, actChromaKey:
        if not isOverlay:
          # Base layer: no lower track to reveal, so replace the keyed color with
          # the timeline background instead of making it transparent.
          frame = keyOverBg(frame, effect)
          continue
        runFx(fxId(effect.kind, frame, f0 = effect.similar, f1 = effect.blend,
            col = packRGB(effect.color))):
          let col = effect.color.toString
          var nodes = @[fxGraph.add("buffer", bufArgsOf(frame))]
          if effect.kind == actChromaKey:
            # chromakey keys in YUV-with-alpha; convert in, then back to rgba so
            # the composited overlay keeps its alpha channel.
            nodes.add fxGraph.add("format", "pix_fmts=yuva420p")
            nodes.add fxGraph.add("chromakey", &"{col}:{effect.similar}:{effect.blend}")
            nodes.add fxGraph.add("format", "pix_fmts=rgba")
          else:
            nodes.add fxGraph.add("colorkey", &"{col}:{effect.similar}:{effect.blend}")
          nodes.add fxGraph.add("buffersink")
          fxGraph.linkNodes(nodes).configure()
      of actChoke:
        # Choke (shrink) the alpha matte a key produced, to cut off the spill
        # fringe. Only overlay layers carry alpha; the base track keys over bg
        # (no matte), so there is nothing to choke there.
        if not isOverlay or not hasAlpha(AVPixelFormat(frame.format)):
          continue
        let n = max(1, int(effect.chokeN))
        runFx(fxId(actChoke, frame, i0 = n.int32)):
          var nodes = @[fxGraph.add("buffer", bufArgsOf(frame))]
          # Erode only the alpha plane: in gbrap the color planes are 0=G, 1=B,
          # 2=R, so threshold0..2=0 freezes them and only plane 3 (alpha) erodes.
          # Each pass pulls the matte edge inward by 1px.
          nodes.add fxGraph.add("format", "pix_fmts=gbrap")
          for _ in 0 ..< n:
            nodes.add fxGraph.add("erosion", "threshold0=0:threshold1=0:threshold2=0")
          nodes.add fxGraph.add("format", &"pix_fmts={$AVPixelFormat(frame.format)}")
          nodes.add fxGraph.add("buffersink")
          fxGraph.linkNodes(nodes).configure()
      of actAberration:
        # Fake chromatic aberration: slide each color channel by its own offset,
        # so the gaps show up as colored fringing. Via rgba so an overlay layer's
        # alpha rides through unshifted.
        let edge = (if effect.abWrap: "wrap" else: "smear")
        runFx(fxId(actAberration, frame,
            i0 = effect.abRh.int32, i1 = effect.abRv.int32,
            i2 = effect.abGh.int32, i3 = effect.abGv.int32,
            f0 = effect.abBh.float32, f1 = effect.abBv.float32,
            col = (if effect.abWrap: 1'u32 else: 0'u32))):
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let toRgba = fxGraph.add("format", "pix_fmts=rgba")
          let shift = fxGraph.add("rgbashift",
            &"rh={effect.abRh}:rv={effect.abRv}:gh={effect.abGh}:gv={effect.abGv}" &
            &":bh={effect.abBh}:bv={effect.abBv}:edge={edge}")
          let toOrig = fxGraph.add("format", &"pix_fmts={$AVPixelFormat(frame.format)}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, toRgba, shift, toOrig, bufferSink]).configure()
      of actMask:
        # Shape the alpha from a cached matte via alphamerge (cheap per frame).
        let matte = cachedMatte(maskMatte, maskMatteKey, frame, effect)
        frame = alphamergeOnto(frame, matte)
        if not isOverlay:
          # Base layer: nothing below to reveal, so flatten the masked-out area
          # over the timeline background.
          frame = overBg(frame)
      of actPixelate:
        # Mosaic censor. Clamp the block to the frame so pixelize can't reject a
        # block larger than the plane; 1x1 blocks are a no-op.
        let w = min(effect.pixW.int, frame.width)
        let h = min(effect.pixH.int, frame.height)
        if w <= 1 and h <= 1:
          continue
        runFx(fxId(actPixelate, frame, i0 = w.int32, i1 = h.int32)):
          let bufferSrc = fxGraph.add("buffer", bufArgsOf(frame))
          let filt = fxGraph.add("pixelize", &"width={w}:height={h}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
      of actConfetti:
        # In the layer's own format so an overlay's alpha survives; fillRect only
        # writes yuv420p and rgba, so convert anything else first.
        let want = (if hasAlpha(AVPixelFormat(frame.format)): AV_PIX_FMT_RGBA
                    else: AV_PIX_FMT_YUV420P)
        let conv = frame.reformat(want)
        if conv != frame:
          av_frame_free(addr frame)
          frame = conv
        # Required, not defensive: the pre-effects frame is cached by clone, so
        # this buffer is shared and an in-place draw would compound into it.
        if av_frame_make_writable(frame) < 0:
          error "Could not make frame writable for confetti"
        drawConfetti(frame, effect, local, fps)
      of actConfine:
        # Set/clear the region the following adjustment effects are masked to.
        confineActive = not effect.mReset
        confineEffect = effect
    return frame

  proc decodeClipFrame(obj: VideoFrame): (ptr AVFrame, bool) =
    ## Decode one clip's frame at its native resolution (after any static
    ## rotation), maintaining per-source seek state. Still images decode once
    ## and return clones. Caller owns the returned frame.
    if obj.gen: # generator overlay: a clear canvas for its action to paint
      return (makeClear(targetWidth, targetHeight), true)
    if obj.src == nil: # synthesized background base (audio-only `add`)
      return (av_frame_clone(nullFrame), true)
    let st = srcs[obj.src]
    if st.isStill:
      if st.still == nil:
        let imgStream = myCache.cns[obj.src].video[0]
        var scratch = av_frame_clone(nullFrame)
        var got: ptr AVFrame = nil
        for decodedFrame in myCache.cns[obj.src].flushDecode(imgStream.index.cint,
            st.decoder, scratch):
          got = av_frame_clone(decodedFrame)
          break
        av_frame_free(addr scratch)
        if got == nil:
          got = av_frame_clone(nullFrame)
        st.still = got
      return (av_frame_clone(st.still), true)

    let cacheKey = (obj.src, obj.index)
    if cacheKey in decodedCache:
      # Another layer at this same timeline frame already decoded this exact
      # source frame. Reuse it.
      return (av_frame_clone(decodedCache[cacheKey]), true)

    # `loop` makes the source restart when it runs out: requests past the source
    # end map back to its start. `loopBase` is the frames consumed by completed
    # loops, so the local decode `target` (and the decoder's frameIndex) stay in
    # one loop's coordinate space while obj.index keeps climbing.
    let looping = firstIsLoop(obj.effects)
    var loopBase = st.loopBase
    var target = obj.index - loopBase
    if target < 0:
      # The request precedes the completed loops: a looping overlay restarted
      # (e.g. follow-base=0 in a later section). Re-anchor at zero; linear
      # timelines hit this too, not just nonlinear ones.
      loopBase = 0
      target = obj.index

    if obj.index >= st.lastReqIndex and obj.index <= loopBase + st.frameIndex and
        st.held != nil:
      st.lastReqIndex = obj.index
      return (av_frame_clone(st.held), true)

    var frame = av_frame_clone(nullFrame)
    var myStream: ptr AVStream = myCache.cns[obj.src].video[0]
    var frameIndex = st.frameIndex
    var seekThreshold = st.seekThreshold
    var seekFrame = st.seekFrame
    var hasSeekFrame = st.hasSeekFrame
    if frameIndex > target:
      # Seek to the largest observed keyframe <= target. A backward seek only
      # ever targets a frame we have already decoded past, so every keyframe up
      # to here has been observed (upfront `keyframeIndices` is unreliable:
      # sparsely-cued containers can report just a single keyframe).
      # observedKeyframes is kept strictly ascending, so upperBound-1 is the
      # floor; frame 0 is always a valid seek point.
      let idx = upperBound(st.observedKeyframes, target) - 1
      let seekTarget = if idx >= 0: st.observedKeyframes[idx] else: 0
      if seekTarget < 0 or seekTarget > target:
        let indexInfo = if st.hasKfIndex: &"{st.kfFrames.len} indexed" else: "no index"
        error &"Cannot seek backward: no suitable keyframe found (frameIndex: {frameIndex}, target: {target}, seekTarget: {seekTarget}, {indexInfo})"
      debug &"Seek backward: from {frameIndex} to keyframe {seekTarget} (need frame {target})"
      myCache.cns[obj.src].seek(
        videoFrameToTimestamp(seekTarget, st.frameRate, myStream.time_base),
        stream = myStream)
      avcodec_flush_buffers(st.decoder)
      st.lastSeekTarget = seekTarget
      frameIndex = min(seekTarget, target - 1)

    var didDecode = false
    while frameIndex < target:
      if target - frameIndex > st.kfInterval and frameIndex > seekThreshold:
        if st.lastSeekTarget != target:
          seekThreshold = frameIndex + (st.kfInterval div 2)
          seekFrame = frameIndex
          hasSeekFrame = true
          debug &"Seek: {frameIndex} -> {target}"
          myCache.cns[obj.src].seek(
            videoFrameToTimestamp(target, st.frameRate, myStream.time_base),
            stream = myStream)
          avcodec_flush_buffers(st.decoder)
          st.lastSeekTarget = target

      let decoder: ptr AVCodecContext = st.decoder
      var foundFrame = false
      for decodedFrame in myCache.cns[obj.src].flushDecode(
          myStream.index.cint, decoder, frame):
        frame = decodedFrame
        frameIndex = int(round(
          decodedFrame.time(myStream.time_base) * st.frameRate.float))
        if decodedFrame.pict_type == AV_PICTURE_TYPE_I and
            frameIndex > st.observedKeyframes[^1]:
          st.observedKeyframes.add frameIndex
        foundFrame = true
        break

      if not foundFrame:
        if looping and frameIndex >= 0:
          loopBase += frameIndex + 1
          target = obj.index - loopBase
          myCache.cns[obj.src].seek(0, stream = myStream)
          avcodec_flush_buffers(st.decoder)
          st.lastSeekTarget = -1
          frameIndex = -1
          continue

        didDecode = false
        av_frame_free(addr frame)
        frame = av_frame_clone(nullFrame)
        break

      didDecode = true

      if hasSeekFrame:
        let framesAvoided = frameIndex - seekFrame
        debug &"Seek landed at frame {frameIndex}, avoided decoding {framesAvoided} frames"
        framesSaved += framesAvoided
        hasSeekFrame = false

    if didDecode:
      # Cache the raw frame (before per-clip static rotation) so another layer
      # sharing this (src, index) reuses it this timeline frame.
      decodedCache[cacheKey] = av_frame_clone(frame)

      var rotStatic = 0.0'f32
      for effect in obj.effects:
        if effect.kind == actRotate:
          rotStatic = rotDeg(effect.rStart)
          break
      if rotStatic != 0.0'f32:
        let rad = rotStatic * 3.14159265358979'f32 / 180.0'f32
        let rk = fxId(actRotate, frame, f0 = rad)
        if rotKey != rk:
          if rotGraph != nil: rotGraph.cleanup()
          rotGraph = newGraph()
          let bsrc = rotGraph.add("buffer", bufArgsOf(frame))
          let filt = rotGraph.add("rotate", &"a={rad}:ow=rotw({rad}):oh=roth({rad}):c={bg}")
          let bsink = rotGraph.add("buffersink")
          rotGraph.linkNodes(@[bsrc, filt, bsink]).configure()
          rotKey = rk
        rotGraph.push(frame)
        av_frame_free(addr frame)
        frame = rotGraph.pull()

    st.frameIndex = frameIndex
    st.seekThreshold = seekThreshold
    st.seekFrame = seekFrame
    st.hasSeekFrame = hasSeekFrame
    st.loopBase = loopBase
    st.lastReqIndex = obj.index
    if didDecode:
      # Hold the final (post-rotation) frame so a later monotonic-forward request
      # that the overshooting decoder has already passed can reuse it (see the
      # reuse check at the top) instead of seeking backward.
      if st.held != nil:
        var old = st.held
        av_frame_free(addr old)
      st.held = av_frame_clone(frame)
    return (frame, didDecode)

  # Output colorspace/range for overlays, from the encoder (stable). Declaring
  # these on the base buffer keeps the composite yuv420p (not gbrp) and makes the
  # overlay's rgb->yuv conversion match the base instead of washing out.
  let ovColorspace =
    if encoderCtx.colorspace.int in 1 .. 15: encoderCtx.colorspace.int
    else: 1
  let ovRange = (if encoderCtx.color_range.int == 2: 2 else: 1)

  proc subpixelShift(src: ptr AVFrame; dx, dy: float32): ptr AVFrame =
    ## Bilinearly translate a packed-RGBA frame by (dx, dy) px, sampling
    ## out-of-bounds as transparent. Lets an animated overlay sit at a fractional
    ## pixel so a slow position ramp slides smoothly instead of stair-stepping.
    let w = src.width.int
    let h = src.height.int
    let dst = av_frame_alloc()
    if dst == nil: error "subpixelShift: could not allocate frame"
    dst.format = src.format
    dst.width = src.width
    dst.height = src.height
    dst.pts = src.pts
    dst.time_base = src.time_base
    if av_frame_get_buffer(dst, 32) < 0: error "subpixelShift: bad buffer"
    let sStride = src.linesize[0].int
    let dStride = dst.linesize[0].int
    let sBase = cast[int](src.data[0])
    let dBase = cast[int](dst.data[0])
    for y in 0 ..< h:
      let dRow = cast[ptr UncheckedArray[uint8]](dBase + y * dStride)
      let syf = y.float32 - dy
      let y0 = floor(syf).int
      let wy = syf - y0.float32
      for x in 0 ..< w:
        let sxf = x.float32 - dx
        let x0 = floor(sxf).int
        let wx = sxf - x0.float32
        for c in 0 ..< 4: # bilinear blend of the 4 neighbours, per RGBA channel
          template px(xx, yy: int): float32 =
            if xx < 0 or xx >= w or yy < 0 or yy >= h: 0.0'f32
            else:
              cast[ptr UncheckedArray[uint8]](
                sBase + yy * sStride)[xx * 4 + c].float32
          let t = px(x0, y0) * (1 - wx) + px(x0 + 1, y0) * wx
          let b = px(x0, y0 + 1) * (1 - wx) + px(x0 + 1, y0 + 1) * wx
          dRow[x * 4 + c] = uint8(clamp(t * (1 - wy) + b * wy + 0.5'f32, 0, 255))
    return dst

  proc overlayFrame(base, top: ptr AVFrame; x, y: float32;
      scale: float32): ptr AVFrame =
    ## Composite `top` over `base` at (x, y), preserving the overlay's alpha.
    ## (x, y) may be fractional: `overlay` places the integer part (it only does
    ## whole pixels) and a bilinear shift places the sub-pixel remainder, so a slow
    ## animated position slides smoothly. Built per call because `overlay` is a
    ## framesync filter (needs EOF on both inputs to emit).
    let ix = floor(x).int
    let iy = floor(y).int
    let fx = x - ix.float32
    let fy = y - iy.float32
    let nw = max(2, int(top.width.float32 * scale))
    let nh = max(2, int(top.height.float32 * scale))
    base.colorspace = cint(ovColorspace)
    base.color_range = cint(ovRange)
    base.pts = 0
    let baseArgs = bufArgsOf(base) & &":colorspace={ovColorspace}:range={ovRange}"
    # The two buffer sources must be nodes 0 (base) and 1 (top) and the sink last,
    # to match pushIdx(0/1) and pull's nodes[^1].
    let g = newGraph()
    let b0 = g.add("buffer", baseArgs)

    if abs(fx) < 0.001'f32 and abs(fy) < 0.001'f32:
      # Whole-pixel placement: scale in-graph (bicubic) and overlay.
      top.pts = 0
      let b1 = g.add("buffer", bufArgsOf(top))
      let topRgba = g.add("format", "pix_fmts=rgba")
      let scl = g.add("scale", &"{nw}:{nh}:flags=bicubic")
      let ov = g.add("overlay", &"x={ix}:y={iy}:format=yuv420")
      let sink = g.add("buffersink")
      g.link(b1, topRgba, 0, 0)
      g.link(topRgba, scl, 0, 0)
      g.link(b0, ov, 0, 0)
      g.link(scl, ov, 0, 1)
      g.link(ov, sink, 0, 0)
      g.configure()
      g.pushIdx(0, base)
      g.pushIdx(1, top)
      g.flushIdx(0)
      g.flushIdx(1)
      result = g.pull()
      g.cleanup()
    else:
      # Sub-pixel placement: scale to rgba up front (so alpha survives), nudge it by
      # the fractional remainder, then overlay the prepared frame at the whole pixel.
      let scaled = top.reformat(AV_PIX_FMT_RGBA, nw.cint, nh.cint)
      let shifted = subpixelShift(scaled, fx, fy)
      shifted.pts = 0
      let b1 = g.add("buffer", bufArgsOf(shifted))
      let ov = g.add("overlay", &"x={ix}:y={iy}:format=yuv420")
      let sink = g.add("buffersink")
      g.link(b0, ov, 0, 0)
      g.link(b1, ov, 0, 1)
      g.link(ov, sink, 0, 0)
      g.configure()
      g.pushIdx(0, base)
      g.pushIdx(1, shifted)
      g.flushIdx(0)
      g.flushIdx(1)
      result = g.pull()
      g.cleanup()
      av_frame_free(addr shifted)
      if scaled != top: av_frame_free(addr scaled)

  proc finalizeFrame(f: ptr AVFrame; index: int64): ptr AVFrame =
    var frame = f
    if frame != nil and (frame.width <= 0 or frame.height <= 0):
      debug &"Warning: Invalid frame at {index}tb, using fallback"
      av_frame_free(addr frame)
      frame =
        if lastProcessedFrame != nil: av_frame_clone(lastProcessedFrame)
        else: av_frame_clone(nullFrame)
      if frame == nil:
        error &"Failed to create fallback frame at {index}tb"
    let reformatted = frame.reformat(pix_fmt, ctx = reformatCtx)
    if reformatted != nil and reformatted != frame:
      av_frame_free(addr frame)
      frame = reformatted
    frame.pts = index
    frame.time_base = av_inv_q(tl.tb)
    frame.duration = 1
    result = frame

  proc scaleProxyFrame(f: ptr AVFrame): ptr AVFrame =
    if scaleCtx == nil or f == nil or
        (f.width == targetWidth and f.height == targetHeight):
      return f
    f.reformat(AVPixelFormat(f.format), targetWidth, targetHeight, scaleCtx)

  return (encoderCtx, outputStream, iterator(): (ptr AVFrame, int64) =
    for index in 0 ..< tl.len:
      objList = @[]
      # The (src, index) decode cache is only valid within one timeline frame.
      for _, f in decodedCache:
        var df = f
        av_frame_free(addr df)
      decodedCache.clear()

      for layerIdx, layer in tl.v:
        for obj in layer:
          if index >= obj.start and index < (obj.start + obj.dur):
            # Convert timeline position from target framerate to source framerate
            let timelinePos = obj.offset + index - obj.start
            let effectGroup = tl.effects[obj.effects]
            var speed = 1.0
            # Overlay placement comes from a `pos` action in the clip's effects
            # (keeps Clip itself position-free); defaults to the canvas origin.
            var ox, oy = 0.0'f32
            var oscale = 1.0'f32
            var hasPos = false
            for effect in effectGroup:
              if effect.kind in [actSpeed, actVarispeed]:
                speed *= effect.val
              elif effect.kind == actPos:
                hasPos = true
                # Sample the placement ramps at this frame's progress, eased like
                # the other animatable effects; static pos has 1-keyframe seqs.
                # Kept as floats so overlayFrame can place at a sub-pixel offset.
                let pp = applyEase(effect.easeCurve, clipT(int(index - obj.start),
                  envAnimLen(effect.easeDurUnit, effect.easeDur, int(obj.dur),
                    tl.tb.float)))
                ox = sampleKf(effect.pxKf, pp)
                oy = sampleKf(effect.pyKf, pp)
                oscale = sampleKf(effect.pscaleKf, pp)

            # A synthesized background base (nil src) has no source frame.
            let sourceFramePos =
              if obj.src == nil: 0
              else:
                let rate = myCache.cns[obj.src].video[0].avg_frame_rate
                # 0/0 (no declared frame rate) would make the index NaN; map 1:1.
                if rate.isValid:
                  int(round(float(timelinePos) * rate.float / tl.tb.float))
                else:
                  int(timelinePos)
            let i = int(round(float(sourceFramePos) * speed))
            # nil src: the `-bg` canvas on the base track, a generator above it.
            objList.add VideoFrame(index: i, src: obj.src, effects: effectGroup,
              gen: obj.src == nil and layerIdx > 0,
              local: int(index - obj.start), dur: int(obj.dur),
              x: ox, y: oy, scale: oscale, fit: not hasPos)

      # More than one active clip at this frame => composite layers (overlay /
      # picture-in-picture / image overlays). objList is in track order, so
      # objList[0] is the bottom (base) layer and later entries paint on top.
      if objList.len > 1:
        av_frame_free(addr frame)
        var (acc, baseDidDecode) = decodeClipFrame(objList[0])
        if baseDidDecode and (acc.width.int32, acc.height.int32) != tl.res:
          let oldAcc = acc
          acc = scaleWithPad(acc, tl.res[0], tl.res[1], tl.bg)
          av_frame_free(addr oldAcc)
        if acc != nil and acc.width > 0 and acc.height > 0:
          acc = applyEffects(acc, objList[0].effects, objList[0].local, objList[0].dur)

        for k in 1 ..< objList.len:
          let o = objList[k]
          var (top, topDidDecode) = decodeClipFrame(o)
          # The overlay has no frame for this timeline position (its source ended,
          # or hasn't started): leave the base untouched so it shows through,
          # rather than compositing an opaque bg-filled fallback over it.
          if not topDidDecode or top == nil or top.width <= 0 or top.height <= 0:
            if top != nil: av_frame_free(addr top)
            continue
          # Effects run at native size; overlayFrame scales (in full chroma).
          top = applyEffects(top, o.effects, o.local, o.dur, isOverlay = true)
          # No explicit `pos`: fit the overlay to the canvas and center it, like
          # the base layer (scaleWithPad), but let the padding stay transparent
          # so only the image shows over the base.
          var ox = o.x
          var oy = o.y
          var oscale = o.scale
          if o.fit:
            oscale = min(acc.width.float32 / top.width.float32,
                         acc.height.float32 / top.height.float32)
            ox = float32((acc.width - int(top.width.float32 * oscale)) div 2)
            oy = float32((acc.height - int(top.height.float32 * oscale)) div 2)
          let newAcc = overlayFrame(acc, top, ox, oy, oscale)
          av_frame_free(addr acc)
          av_frame_free(addr top)
          acc = newAcc

        let scaledAcc = scaleProxyFrame(acc)
        if scaledAcc != acc:
          av_frame_free(addr acc)
          acc = scaledAcc

        frame = finalizeFrame(acc, index)
        av_frame_free(addr lastProcessedFrame)
        lastProcessedFrame = av_frame_clone(frame)
        lastFrameIndex = -1 # compositing bypasses the single-layer reuse cache
        yield (frame, index)
        continue

      if not isLinear:
        # When there can be valid gaps in the timeline and no objects for this frame.
        av_frame_free(addr frame)
        frame = av_frame_clone(nullFrame)
      else:
        # Always start with a fresh frame to avoid reusing encoder-unref'd frames
        av_frame_free(addr frame)
        if pix_fmt == AV_PIX_FMT_RGB8 and lastProcessedFrame != nil:
          frame = av_frame_clone(lastProcessedFrame)
        else:
          frame = av_frame_clone(nullFrame)

      for obj in objList:
        # Reuse the decoded frame from the previous timeline iteration when
        # this frame maps to the same source frame.
        if obj.index == lastFrameIndex and lastProcessedFrame != nil:
          av_frame_free(addr frame)
          frame = av_frame_clone(lastProcessedFrame)
          continue

        var (decoded, didDecode) = decodeClipFrame(obj)
        if didDecode:
          av_frame_free(addr frame)
          frame = decoded
          # decodeClipFrame returns native resolution; scale the final frame to
          # the canvas (intermediate seek frames never reach here, so the resize
          # costs one sws_scale rather than one per decoded frame).
          if (frame.width.int32, frame.height.int32) != tl.res:
            let oldFrame = frame
            frame = scaleWithPad(frame, tl.res[0], tl.res[1], tl.bg)
            av_frame_free(addr oldFrame)
        else:
          # No new frame decoded: keep the pre-initialized `frame` (nullFrame, or
          # the last frame for RGB8 palette persistence) and drop the fallback.
          av_frame_free(addr decoded)

      let scaledFrame = scaleProxyFrame(frame)
      if scaledFrame != frame:
        av_frame_free(addr frame)
        frame = scaledFrame

      # Cache the pre-effects frame: effects are per-timeline-frame (animated
      # via `local`) and would compound when a source frame repeats.
      if objList.len > 0:
        av_frame_free(addr lastProcessedFrame)
        lastProcessedFrame = av_frame_clone(frame)
        lastFrameIndex = objList[0].index

      if objList.len > 0 and frame != nil and frame.width > 0 and frame.height > 0:
        frame = applyEffects(frame, objList[0].effects, objList[0].local,
          objList[0].dur)

      frame = finalizeFrame(frame, index)

      yield (frame, index)

    if fxGraph != nil:
      fxGraph.cleanup()
    if rotGraph != nil:
      rotGraph.cleanup()
    if maskMatte != nil: av_frame_free(addr maskMatte)
    if confineMatte != nil: av_frame_free(addr confineMatte)
    sws_free_context(addr scaleCtx)
    sws_free_context(addr reformatCtx)
    av_frame_free(addr frame)
    av_frame_free(addr lastProcessedFrame)
    av_frame_free(addr nullFrame)
    for _, f in decodedCache:
      var df = f
      av_frame_free(addr df)
    for _, s in srcs:
      if s.still != nil:
        var sf = s.still
        av_frame_free(addr sf)
      if s.held != nil:
        var hf = s.held
        av_frame_free(addr hf)
      if s.decoder != nil:
        var p = s.decoder
        avcodec_free_context(addr p)
    debug &"Total frames avoided decoding via seeks: {framesSaved}")
