import std/[sets, strformat, tables]
from std/math import round, hypot, ceil

import ../[action, av, ffmpeg, graph, log, timeline]
import ../util/[color, dnorm16, rational]

type VideoFrame = object
  index: int
  src: ptr string
  effects: Actions
  local: int  # frame offset within the clip, for animated effects
  dur: int    # clip length in frames
  x: int32    # overlay placement (canvas pixels); 0 for the base layer
  y: int32
  scale: float32  # overlay size multiplier; 1.0 for the base layer
  fit: bool   # no explicit `pos`: fit-and-center to the canvas like the base

func clipT(local, animLen: int): float32 =
  ## Normalized time over an animation of `animLen` frames, reaching 1.0 on the
  ## last frame and holding there once the animation completes.
  let l = min(local, max(animLen - 1, 0))
  float32(l) / float32(max(animLen - 1, 1))

func envAnimLen(unit: DurUnit, mag: float32, clipDur: int, fps: float): int =
  ## Resolve an ease duration to a frame count for the current clip.
  case unit
  of duClip: clipDur
  of duSec: max(1, int(round(mag.float * fps)))
  of duFrames: max(1, int(round(mag.float)))

# Keyframe index built from AVIndexEntry for efficient seeking
type KeyframeIndex = object
  frames: seq[int] # sorted list of keyframe frame numbers
  avgInterval: int # average interval between keyframes (for seek decisions)
  hasIndex: bool   # whether the demuxer provided index entries

type SrcState = ref object
  kfFrames: seq[int]          # indexed keyframe frame numbers
  observedKeyframes: seq[int] # keyframes seen while decoding (for backward seeks)
  decoder: ptr AVCodecContext
  still: ptr AVFrame          # memoized decoded still; nil until first decode
  held: ptr AVFrame           # last decoded frame, held for forward reuse
  tou: int                    # timebase units per source frame (for seeks)
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

proc buildKeyframeIndex(stream: ptr AVStream, fps: AVRational, defaultInterval: int): KeyframeIndex =
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
      let frameNum = int(round(float(entry.timestamp) * float(tb.num) / float(tb.den) * float(fps)))

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
  let swsCtx = if ctx != nil:
    ctx
  else:
    ownedCtx = sws_alloc_context()
    if ownedCtx == nil:
      error "Failed to allocate sws context"
    ownedCtx

  ret = sws_scale_frame(swsCtx, newFrame, frame)

  if ownedCtx != nil:
    sws_free_context(addr ownedCtx)

  if ret < 0:
    error "Failed to scale frame"

  return newFrame

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

  let yData: ptr uint8 = frame.data[0]
  let yLinesize: cint = frame.linesize[0]
  # Convert RGB to Y (luma): Y = 0.299*R + 0.587*G + 0.114*B
  let yValue = uint8(0.299 * color.red.float + 0.587 * color.green.float + 0.114 *
      color.blue.float)

  for y in 0 ..< height:
    let row: ptr uint8 = cast[ptr uint8](cast[int](yData) + y.int * yLinesize.int)
    let rowArray = cast[ptr UncheckedArray[uint8]](row)
    for x in 0 ..< width:
      rowArray[x] = yValue

  let uData: ptr uint8 = frame.data[1]
  let uLinesize: cint = frame.linesize[1]
  # Convert RGB to U: U = -0.169*R - 0.331*G + 0.5*B + 128
  let uValue = uint8(max(0.0, min(255.0, -0.169 * color.red.float - 0.331 *
      color.green.float + 0.5 * color.blue.float + 128)))

  for y in 0 ..< (height div 2):
    let row: ptr uint8 = cast[ptr uint8](cast[int](uData) + y.int * uLinesize.int)
    let rowArray = cast[ptr UncheckedArray[uint8]](row)
    for x in 0 ..< (width div 2):
      rowArray[x] = uValue

  let vData: ptr uint8 = frame.data[2]
  let vLinesize: cint = frame.linesize[2]
  # Convert RGB to V: V = 0.5*R - 0.419*G - 0.081*B + 128
  let vValue = uint8(max(0.0, min(255.0, 0.5 * color.red.float - 0.419 *
      color.green.float - 0.081 * color.blue.float + 128)))

  for y in 0 ..< (height div 2):
    let row: ptr uint8 = cast[ptr uint8](cast[int](vData) + y.int * vLinesize.int)
    let rowArray = cast[ptr UncheckedArray[uint8]](row)
    for x in 0 ..< (width div 2):
      rowArray[x] = vValue

  return frame

proc scaleWithPad(src: ptr AVFrame, targetW, targetH: int32, bg: RGBColor): ptr AVFrame =
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
    let dp = cast[pointer](cast[int](output.data[0]) + (oy.int + y) * output.linesize[0].int + ox.int)
    copyMem(dp, sp, scaled.width.int)

  for y in 0 ..< (scaled.height div 2).int:
    let sp = cast[pointer](cast[int](scaled.data[1]) + y * scaled.linesize[1].int)
    let dp = cast[pointer](cast[int](output.data[1]) + ((oy div 2).int + y) * output.linesize[1].int + (ox div 2).int)
    copyMem(dp, sp, (scaled.width div 2).int)

  for y in 0 ..< (scaled.height div 2).int:
    let sp = cast[pointer](cast[int](scaled.data[2]) + y * scaled.linesize[2].int)
    let dp = cast[pointer](cast[int](output.data[2]) + ((oy div 2).int + y) * output.linesize[2].int + (ox div 2).int)
    copyMem(dp, sp, (scaled.width div 2).int)

  av_frame_free(addr scaled)
  return output

proc makeNewVideoFrames*(output: var OutputContainer, tl: v3, args: mainArgs,
    cache: MediaCache = nil):
    (ptr AVCodecContext, ptr AVStream, iterator(): (ptr AVFrame, int64)) =

  let myCache = if cache != nil: cache else: newMediaCache()
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
    if src notin myCache.cns:
      myCache.cns[src] = av.open(src[])

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
    const imageCodecs = [ID_PNG, ID_JPEG, ID_WEBP, ID_BMP, ID_TIFF]
    srcs[src].isStill = vstream.codecpar.codec_id in imageCodecs or vstream.nb_frames == 1

  var targetWidth = tl.res[0]
  var targetHeight = tl.res[1]
  var scaleGraph: Graph = nil
  var fxGraph: Graph = nil
  var fxKey = ""
  var rotGraph: Graph = nil  # static source rotation, applied before the fit
  var rotKey = ""
  var needsScaling = false

  if args.scale != 1.0:
    targetWidth = max(int32(round(tl.res[0].float64 * args.scale)) and not 1'i32, 2)
    targetHeight = max(int32(round(tl.res[1].float64 * args.scale)) and not 1'i32, 2)
    needsScaling = true

  debug &"Creating video stream with codec: {args.videoCodec}"
  var (outputStream, encoderCtx) = output.addStream(args.videoCodec, targetFps,
      lang = tl.langs[0], width = targetWidth, height = targetHeight)
  let codec = encoderCtx.codec

  if codec.id == ID_HEVC:
    const codecTag = fourccToInt("hvc1") # for QuickTime
    outputStream.codecpar.codec_tag = codecTag
    encoderCtx.codec_tag = codecTag
    discard av_opt_set(encoderCtx.priv_data, "x265-params", "log-level=error", 0)

  encoderCtx.framerate = targetFps
  encoderCtx.thread_type = FF_THREAD_FRAME or FF_THREAD_SLICE

  # For encoder config (colorspace/SAR/pix_fmt) prefer a real, non-still video
  # source. An audio-only `add` timeline may have only still images over a
  # synthesized background, in which case yuv420p defaults are used.
  for s in tl.uniqueSources:
    if myCache.cns[s].video.len > 0 and not srcs[s].isStill:
      firstSrc = s
      break

  let src = myCache.cns[firstSrc]
  # Don't inherit color tags / SAR from a still image. PNGs are tagged full-range
  # (which makes the H.264 encoder emit deprecated yuvj420p), so when the only
  # reference is a still (e.g. an audio-only `add` over a synthesized canvas),
  # keep the encoder's limited-range yuv420p defaults instead.
  if not srcs[firstSrc].isStill:
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
    if sar != 0:
      encoderCtx.sample_aspect_ratio = sar

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

      # tou (timebase units per source frame) turns a frame index into a seek
      # timestamp. avg_frame_rate can be 0/0 for streams with no declared frame
      # rate; fall back to the timeline rate so the int conversion never sees
      # inf/nan from a divide-by-zero.
      let srcFps = float(stream.avg_frame_rate)
      let fps = if srcFps > 0.0: srcFps else: float(targetFps)
      st.tou = int(float(stream.time_base.den) / fps)

      if args.noSeek:
        st.kfFrames = @[]
        st.hasKfIndex = false
        st.kfInterval = high(int)
      else:
        let kf = buildKeyframeIndex(stream, stream.avg_frame_rate, defaultInterval)
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

  var needValidFmt = true
  if codec.pix_fmts != nil:
    var i = 0
    while codec.pix_fmts[i].cint != -1:
      if pix_fmt == codec.pix_fmts[i]:
        needValidFmt = false
        break
      i += 1

  if needValidFmt:
    if codec.pix_fmts != nil:
      let best = avcodec_find_best_pix_fmt_of_list(codec.pix_fmts, pix_fmt, 0, nil)
      pix_fmt = if best != AV_PIX_FMT_NONE: best else: AV_PIX_FMT_YUV420P
    else:
      pix_fmt = AV_PIX_FMT_YUV420P

  if args.vprofile != "":
    encoderCtx.setProfileOrErr(args.vprofile)

  if args.crf >= 0:
    discard av_opt_set_int(encoderCtx.priv_data, "crf", args.crf.cint, 0)
  if args.preset != "":
    discard av_opt_set(encoderCtx.priv_data, "preset", cstring(args.preset), 0)

  encoderCtx.pix_fmt = pix_fmt
  encoderCtx.open()
  pix_fmt = encoderCtx.pix_fmt
  if avcodec_parameters_from_context(outputStream.codecpar, encoderCtx) < 0:
    error "Could not copy encoder parameters to stream"

  let pixFmtName = $pix_fmt
  let graphTb = av_inv_q(targetFps)
  let bg = tl.bg.toString

  if needsScaling:
    let bufferArgs = &"video_size={tl.res[0]}x{tl.res[1]}:pix_fmt={pixFmtName}:time_base={graphTb}:pixel_aspect=1/1"

    scaleGraph = newGraph()
    let bufferSrc = scaleGraph.add("buffer", bufferArgs)
    let scaleFilter = scaleGraph.add("scale", &"{targetWidth}:{targetHeight}")
    let bufferSink = scaleGraph.add("buffersink")

    scaleGraph.linkNodes(@[bufferSrc, scaleFilter, bufferSink]).configure()

  # Create a persistent sws context for the per-frame pixel format conversion.
  # Reusing it avoids the per-frame alloc/init overhead of the new sws API.
  var reformatCtx: ptr SwsContext = nil
  if pix_fmt != AVPixelFormat(src.video[0].codecpar.format):
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
  let isNonlinear = tl.isNonlinear

  debug &"isNonlinear: {isNonlinear}"

  # Find the closest keyframe at or before targetFrame for backward seeking.
  # A backward seek only ever targets a frame we have already decoded past, so
  # every keyframe up to the current position has been observed -- and, having
  # been demuxed, is now in the container's seek index.

  # Upfront `keyframeIndices` is unreliable since sparsely-cued containers can
  # report just a single keyframe.
  proc findBestKeyframe(src: ptr string, targetFrame: int): int =
    let kfs = srcs[src].observedKeyframes
    var lo = 0
    var hi = kfs.high
    result = 0 # frame 0 is always a valid seek point
    while lo <= hi:
      let mid = (lo + hi) div 2
      if kfs[mid] <= targetFrame:
        result = kfs[mid]
        lo = mid + 1
      else:
        hi = mid - 1

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
    let bgSrc = g.add("buffer", &"video_size={w}x{h}:pix_fmt=yuv420p:time_base={graphTb}:pixel_aspect=1/1")
    let fgSrc = g.add("buffer", &"video_size={w}x{h}:pix_fmt={$AVPixelFormat(frame.format)}:time_base={graphTb}:pixel_aspect=1/1")
    let toAlpha = g.add("format", "pix_fmts=" & (if isChroma: "yuva420p" else: "rgba"))
    let keyer = g.add((if isChroma: "chromakey" else: "colorkey"),
      &"{col}:{effect.similar}:{effect.blend}")
    let ov = g.add("overlay", "format=yuv420")
    discard g.linkNodes(@[fgSrc, toAlpha, keyer])
    g.link(bgSrc, ov, 0, 0)  # background on the bottom pad
    g.link(keyer, ov, 0, 1)  # keyed frame on top
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

  proc applyEffects(frame0: ptr AVFrame, effects: Actions, local, clipDur: int,
      isOverlay = false): ptr AVFrame =
    ## Apply one clip's effect chain to a frame, returning the (possibly new)
    ## frame. Shared by the single-layer path and per-clip compositing. `isOverlay`
    ## is true for higher composited layers, which want transparent (not bg) fill
    ## from `spin`.
    var frame = frame0
    let fps = tl.tb.float
    # Eased progress in [0, 1] for an animated action, using its own packed
    # easing curve + duration (defaults to linear over the whole clip).
    template prog(e: Action): float32 =
      applyEase(e.easeCurve, clipT(local, envAnimLen(e.easeDurUnit, e.easeDur, clipDur, fps)))

    for effect in effects:
      case effect.kind:
      of actSpeed, actVarispeed, actVolume, actDeesser, actPos, actRotate, actLoop: discard
      of actSpin:
        let rate = effect.sRate
        let startDeg = rotDeg(effect.sStart)
        let w = frame.width
        let h = frame.height
        # Spin within a constant square sized to the diagonal, so no angle clips
        # the picture. Overlays fill the exposed corners transparently (only the
        # picture shows over the base); the base layer fills them with bg.
        let side = cint(int(ceil(hypot(w.float, h.float))) + 1) and not 1.cint
        frame.pts = local.int64
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={w}x{h}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let aExpr = &"a=({startDeg}+({rate})*t)*PI/180:ow={side}:oh={side}"
        let key = &"spin|{isOverlay}|{startDeg}|{rate}|{side}|{bg}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          var nodes: seq[ptr AVFilterContext] = @[bufferSrc]
          if isOverlay:
            # Convert to rgba first so the rotate fill (and exposed corners) can
            # be transparent.
            nodes.add fxGraph.add("format", "pix_fmts=rgba")
            nodes.add fxGraph.add("rotate", aExpr & ":c=black@0")
          else:
            nodes.add fxGraph.add("rotate", aExpr & &":c={bg}")
          nodes.add fxGraph.add("buffersink")
          fxGraph.linkNodes(nodes).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
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
        let frameFmtName = $AVPixelFormat(frame.format)
        let zoomBufArgs = &"video_size={scaledW}x{scaledH}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let zoomMode = if z > 1.0: "crop" else: "pad"
        let key = &"zoom|{zoomMode}|{origW}x{origH}|{bg}|{zoomBufArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", zoomBufArgs)
          let mid = if z > 1.0:
              fxGraph.add("crop", &"{origW}:{origH}")
            else:
              fxGraph.add("pad", &"{origW}:{origH}:-1:-1:color={bg}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, mid, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actHflip, actVflip, actInvert, actErosion:
        let filterName = case effect.kind
          of actHflip: "hflip"
          of actVflip: "vflip"
          of actErosion: "erosion"
          else: "negate"
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = filterName & "|" & bufferArgs
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          let filt = fxGraph.add(filterName)
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actBlur:
        let sigma = sampleKf(effect.kf, prog(effect))
        if sigma <= 0.0:
          continue
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"blur|{sigma}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          let filt = fxGraph.add("gblur", &"sigma={sigma}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actBrightness:
        let b = sampleKf(effect.kf, prog(effect))
        if b == 0.0'f32:
          continue
        let shift = b * 255.0'f32
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"brightness|{shift}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          let toRgb = fxGraph.add("format", "pix_fmts=rgb24")
          let lut = fxGraph.add("lutrgb",
            &"r=val+{shift}:g=val+{shift}:b=val+{shift}")
          let toOrig = fxGraph.add("format", &"pix_fmts={frameFmtName}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, toRgb, lut, toOrig, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actLuv:
        if (effect.brighthue == luvBrighthueId and
            effect.contrast == luvContrastId and
            effect.saturation == luvSaturationId):
          continue

        let b = effect.brighthue
        let c = effect.contrast
        let s = effect.saturation
        let bShift = b * 255.0
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"bcs|{b}|{c}|{s}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          let toYuv = fxGraph.add("format", "pix_fmts=yuv444p")
          let lut = fxGraph.add("lutyuv",
            &"y=(val-128)*{c}+128+{bShift}:u=(val-128)*{s}+128:v=(val-128)*{s}+128")
          let toOrig = fxGraph.add("format", &"pix_fmts={frameFmtName}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, toYuv, lut, toOrig, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actOpacity:
        let o = sampleKf(effect.kf, prog(effect))
        if o >= 1.0'f32:
          continue
        let bgR = (1.0'f32 - o) * float32(tl.bg.red)
        let bgG = (1.0'f32 - o) * float32(tl.bg.green)
        let bgB = (1.0'f32 - o) * float32(tl.bg.blue)
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"opacity|{o}|{bg}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          let toRgb = fxGraph.add("format", "pix_fmts=rgb24")
          let lut = fxGraph.add("lutrgb",
            &"r=val*{o}+{bgR}:g=val*{o}+{bgG}:b=val*{o}+{bgB}")
          let toOrig = fxGraph.add("format", &"pix_fmts={frameFmtName}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, toRgb, lut, toOrig, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actLens:
        let k1 = effect.k1
        let k2 = effect.k2
        if k1 == 0.0'f32 and k2 == 0.0'f32:
          continue
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"lens|{k1}|{k2}|{bg}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          let filt = fxGraph.add("lenscorrection", &"k1={k1}:k2={k2}:fc={bg}")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actDrawbox:
        let col = effect.dbColor.toString
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"drawbox|{effect.dbX}|{effect.dbY}|{effect.dbW}|{effect.dbH}|{col}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          let filt = fxGraph.add("drawbox",
            &"x={effect.dbX}:y={effect.dbY}:w={effect.dbW}:h={effect.dbH}:color={col}:t=fill")
          let bufferSink = fxGraph.add("buffersink")
          fxGraph.linkNodes(@[bufferSrc, filt, bufferSink]).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actColorKey, actChromaKey:
        if not isOverlay:
          # Base layer: no lower track to reveal, so replace the keyed color with
          # the timeline background instead of making it transparent.
          frame = keyOverBg(frame, effect)
          continue
        let col = effect.color.toString
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"{effect.kind}|{col}|{effect.similar}|{effect.blend}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          let bufferSrc = fxGraph.add("buffer", bufferArgs)
          var nodes = @[bufferSrc]
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
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
      of actChoke:
        # Choke (shrink) the alpha matte a key produced, to cut off the spill
        # fringe. Only overlay layers carry alpha; the base track keys over bg
        # (no matte), so there is nothing to choke there.
        if not isOverlay or not hasAlpha(AVPixelFormat(frame.format)):
          continue
        let n = max(1, int(effect.chokeN))
        let frameFmtName = $AVPixelFormat(frame.format)
        let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={frameFmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let key = &"choke|{n}|{frameFmtName}|{bufferArgs}"
        if fxKey != key:
          if fxGraph != nil:
            fxGraph.cleanup()
          fxGraph = newGraph()
          var nodes = @[fxGraph.add("buffer", bufferArgs)]
          # Erode only the alpha plane: in gbrap the color planes are 0=G, 1=B,
          # 2=R, so threshold0..2=0 freezes them and only plane 3 (alpha) erodes.
          # Each pass pulls the matte edge inward by 1px.
          nodes.add fxGraph.add("format", "pix_fmts=gbrap")
          for _ in 0 ..< n:
            nodes.add fxGraph.add("erosion", "threshold0=0:threshold1=0:threshold2=0")
          nodes.add fxGraph.add("format", &"pix_fmts={frameFmtName}")
          nodes.add fxGraph.add("buffersink")
          fxGraph.linkNodes(nodes).configure()
          fxKey = key
        fxGraph.push(frame)
        av_frame_free(addr frame)
        frame = fxGraph.pull()
    return frame

  proc decodeClipFrame(obj: VideoFrame): (ptr AVFrame, bool) =
    ## Decode one clip's frame at its native resolution (after any static
    ## rotation), maintaining per-source seek state. Still images decode once
    ## and return clones. Caller owns the returned frame.
    if obj.src == nil:  # synthesized background base (audio-only `add`)
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
    if isNonlinear and target < 0:
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
      let seekTarget = findBestKeyframe(obj.src, target)
      if seekTarget < 0 or seekTarget > target:
        let indexInfo = if st.hasKfIndex: &"{st.kfFrames.len} indexed" else: "no index"
        error &"Cannot seek backward: no suitable keyframe found (frameIndex: {frameIndex}, target: {target}, seekTarget: {seekTarget}, {indexInfo})"
      if st.lastSeekTarget != seekTarget:
        debug &"Seek backward: from {frameIndex} to keyframe {seekTarget} (need frame {target})"
        myCache.cns[obj.src].seek(seekTarget * st.tou, stream = myStream)
        avcodec_flush_buffers(st.decoder)
        st.lastSeekTarget = seekTarget
      frameIndex = min(seekTarget, target - 1)

    let srcTb = myStream.avg_frame_rate
    var didDecode = false
    while frameIndex < target:
      if target - frameIndex > st.kfInterval and frameIndex > seekThreshold:
        if st.lastSeekTarget != target:
          seekThreshold = frameIndex + (st.kfInterval div 2)
          seekFrame = frameIndex
          hasSeekFrame = true
          debug &"Seek: {frameIndex} -> {target}"
          myCache.cns[obj.src].seek(target * st.tou, stream = myStream)
          avcodec_flush_buffers(st.decoder)
          st.lastSeekTarget = target

      let decoder: ptr AVCodecContext = st.decoder
      var foundFrame = false
      for decodedFrame in myCache.cns[obj.src].flushDecode(myStream.index.cint, decoder, frame):
        frame = decodedFrame
        frameIndex = int(round(decodedFrame.time(myStream.time_base) * srcTb.float))
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
        let fmtName = $AVPixelFormat(frame.format)
        let rbufArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={fmtName}:time_base={graphTb}:pixel_aspect=1/1"
        let rk = &"srcrot|{rad}|{bg}|{rbufArgs}"
        if rotKey != rk:
          if rotGraph != nil: rotGraph.cleanup()
          rotGraph = newGraph()
          let bsrc = rotGraph.add("buffer", rbufArgs)
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
  let ovColorspace = (if encoderCtx.colorspace.int in 1 .. 15: encoderCtx.colorspace.int else: 1)
  let ovRange = (if encoderCtx.color_range.int == 2: 2 else: 1)

  proc overlayFrame(base, top: ptr AVFrame; x, y: int; scale: float32): ptr AVFrame =
    ## Composite `top` over `base` at (x, y), preserving the overlay's alpha.
    ## Built per call because `overlay` is a framesync filter (needs EOF on both
    ## inputs to emit).
    base.colorspace = cint(ovColorspace)
    base.color_range = cint(ovRange)
    base.pts = 0
    top.pts = 0
    let baseArgs = &"video_size={base.width}x{base.height}:pix_fmt={$AVPixelFormat(base.format)}:time_base={graphTb}:pixel_aspect=1/1:colorspace={ovColorspace}:range={ovRange}"
    let topArgs = &"video_size={top.width}x{top.height}:pix_fmt={$AVPixelFormat(top.format)}:time_base={graphTb}:pixel_aspect=1/1"
    let nw = max(2, int(top.width.float32 * scale))
    let nh = max(2, int(top.height.float32 * scale))
    let g = newGraph()
    let b0 = g.add("buffer", baseArgs)
    let b1 = g.add("buffer", topArgs)
    let topRgba = g.add("format", "pix_fmts=rgba")
    let scl = g.add("scale", &"{nw}:{nh}:flags=bicubic")
    let ov = g.add("overlay", &"x={x}:y={y}:format=yuv420")
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

  proc finalizeFrame(f: ptr AVFrame; index: int64): ptr AVFrame =
    var frame = f
    if frame != nil and (frame.width <= 0 or frame.height <= 0):
      debug &"Warning: Invalid frame at {index}tb, using fallback"
      av_frame_free(addr frame)
      frame = (if lastProcessedFrame != nil: av_frame_clone(lastProcessedFrame)
               else: av_frame_clone(nullFrame))
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

  return (encoderCtx, outputStream, iterator(): (ptr AVFrame, int64) =
    for index in 0 ..< tl.len:
      objList = @[]
      # The (src, index) decode cache is only valid within one timeline frame.
      for _, f in decodedCache:
        var df = f
        av_frame_free(addr df)
      decodedCache.clear()

      for layer in tl.v:
        for obj in layer:
          if index >= obj.start and index < (obj.start + obj.dur):
            # Convert timeline position from target framerate to source framerate
            let timelinePos = obj.offset + index - obj.start
            let effectGroup = tl.effects[obj.effects]
            var speed = 1.0
            # Overlay placement comes from a `pos` action in the clip's effects
            # (keeps Clip itself position-free); defaults to the canvas origin.
            var ox, oy = 0'i32
            var oscale = 1.0'f32
            var hasPos = false
            for effect in effectGroup:
              if effect.kind in [actSpeed, actVarispeed]:
                speed *= effect.val
              elif effect.kind == actPos:
                hasPos = true
                ox = effect.px
                oy = effect.py
                oscale = effect.pscale

            # A synthesized background base (nil src) has no source frame.
            let sourceFramePos =
              if obj.src == nil: 0
              else:
                let srcTb = myCache.cns[obj.src].video[0].avg_frame_rate
                int(round(float(timelinePos) * srcTb.float / tl.tb.float))
            let i = int(round(float(sourceFramePos) * speed))
            objList.add VideoFrame(index: i, src: obj.src, effects: effectGroup,
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
          var ox = o.x.int
          var oy = o.y.int
          var oscale = o.scale
          if o.fit:
            oscale = min(acc.width.float32 / top.width.float32,
                         acc.height.float32 / top.height.float32)
            ox = (acc.width - int(top.width.float32 * oscale)) div 2
            oy = (acc.height - int(top.height.float32 * oscale)) div 2
          let newAcc = overlayFrame(acc, top, ox, oy, oscale)
          av_frame_free(addr acc)
          av_frame_free(addr top)
          acc = newAcc

        if scaleGraph != nil and acc.width != targetWidth:
          scaleGraph.push(acc)
          av_frame_free(addr acc)
          acc = scaleGraph.pull()

        frame = finalizeFrame(acc, index)
        av_frame_free(addr lastProcessedFrame)
        lastProcessedFrame = av_frame_clone(frame)
        lastFrameIndex = -1  # compositing bypasses the single-layer reuse cache
        yield (frame, index)
        continue

      if isNonlinear:
        # When there can be valid gaps in the timeline and no objects for this frame.
        frame = av_frame_clone(nullFrame)
      else:
        # Always start with a fresh frame to avoid reusing encoder-unref'd frames
        av_frame_free(addr frame)
        if pix_fmt == AV_PIX_FMT_RGB8 and lastProcessedFrame != nil:
          frame = av_frame_clone(lastProcessedFrame)
        else:
          frame = av_frame_clone(nullFrame)

      for obj in objList:
        # Reuse the fully-processed frame from the previous timeline iteration
        # when this frame maps to the same source frame.
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

      if scaleGraph != nil and frame.width != targetWidth:
        scaleGraph.push(frame)
        av_frame_free(addr frame)
        frame = scaleGraph.pull()

      if objList.len > 0 and frame != nil and frame.width > 0 and frame.height > 0:
        frame = applyEffects(frame, objList[0].effects, objList[0].local, objList[0].dur)

      frame = finalizeFrame(frame, index)

      # Update cache for frame reuse BEFORE yielding (which will unref the frame)
      if objList.len > 0:
        av_frame_free(addr lastProcessedFrame)
        lastProcessedFrame = av_frame_clone(frame)
        lastFrameIndex = objList[0].index

      yield (frame, index)

    if scaleGraph != nil:
      scaleGraph.cleanup()
    if fxGraph != nil:
      fxGraph.cleanup()
    if rotGraph != nil:
      rotGraph.cleanup()
    sws_free_context(addr reformatCtx)
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
