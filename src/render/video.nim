import std/[sets, tables]
import std/options
import std/strformat
from std/math import round

import ../log
import ../av
import ../ffmpeg
import ../timeline
import ../util/color
import ../graph

# Helps with timing, may be extended.
type VideoFrame = object
  index: int
  src: ptr string

func toInt(r: AVRational): int =
  (r.num div r.den).int

proc reformat*(frame: ptr AVFrame, format: AVPixelFormat, width: cint = 0, height: cint = 0): ptr AVFrame =
  if frame == nil:
    return nil

  let srcFormat = AVPixelFormat(frame.format)
  let srcWidth = frame.width
  let srcHeight = frame.height
  let dstWidth = if width > 0: width else: srcWidth
  let dstHeight = if height > 0: height else: srcHeight

  # Shortcut: if format and dimensions are the same, return original frame
  if srcFormat == format and srcWidth == dstWidth and srcHeight == dstHeight:
    return frame

  # Create new frame for output
  let newFrame = av_frame_alloc()
  if newFrame == nil:
    error "Failed to allocate new frame"

  newFrame.format = format.cint
  newFrame.width = dstWidth
  newFrame.height = dstHeight
  newFrame.pts = frame.pts
  newFrame.time_base = frame.time_base

  # Allocate buffer for new frame
  if av_frame_get_buffer(newFrame, 32) < 0:
    error "Failed to allocate buffer for new frame"

  # Create swscale context
  let swsContext = sws_getCachedContext(
    nil,  # No cached context for now
    srcWidth, srcHeight, srcFormat,
    dstWidth, dstHeight, format,
    SWS_BILINEAR,  # Use bilinear interpolation
    nil, nil, nil
  )

  if swsContext == nil:
    error "Failed to create swscale context"

  # Perform the conversion
  let ret = sws_scale(
    swsContext,
    cast[ptr ptr uint8](addr frame.data[0]),
    cast[ptr cint](addr frame.linesize[0]),
    0,  # srcSliceY
    srcHeight,  # srcSliceH
    cast[ptr ptr uint8](addr newFrame.data[0]),
    cast[ptr cint](addr newFrame.linesize[0])
  )

  # Clean up the context
  sws_freeContext(swsContext)

  if ret < 0:
    error "Failed to scale frame"  # Noreturn

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

  # Fill Y plane (luma)
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

  # Fill U plane (chroma)
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

  # Fill V plane (chroma)
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

proc makeNewVideoFrames*(output: var OutputContainer, tl: v3, args: mainArgs):
    (ptr AVCodecContext, ptr AVStream, iterator(): (ptr AVFrame, int)) =

  var cns = initTable[ptr string, InputContainer]()
  var decoders = initTable[ptr string, ptr AVCodecContext]()
  var seekCost = initTable[ptr string, int]()
  var tous = initTable[ptr string, int]()

  var pix_fmt = AV_PIX_FMT_YUV420P # Reasonable default
  let targetFps = tl.tb # Always constant

  var firstSrc: ptr string = nil
  for src in tl.uniqueSources:
    if firstSrc == nil:
      firstSrc = src

    if src notin cns:
      cns[src] = av.open(src[])
      decoders[src] = initDecoder(cns[src].video[0].codecpar)

  var targetWidth: cint = cint(tl.res[0])
  var targetHeight: cint = cint(tl.res[1])
  var scaleGraph: Graph = nil
  var needsScaling = false

  if args.scale != 1.0:
    targetWidth = max(cint(round(tl.res[0].float64 * args.scale)), 2)
    targetHeight = max(cint(round(tl.res[1].float64 * args.scale)), 2)
    needsScaling = true


  debug &"Creating video stream with codec: {args.videoCodec}"
  var (outputStream, encoderCtx) = output.addStream(args.videoCodec,
      rate = targetFps, width = targetWidth, height = targetHeight, metadata = {
          "language": tl.v[0].lang}.toTable)
  let codec = encoderCtx.codec

  encoderCtx.framerate = targetFps
  encoderCtx.thread_type = FF_THREAD_FRAME or FF_THREAD_SLICE

  let src = cns[firstSrc]
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

  if args.videoBitrate >= 0:
    encoderCtx.bit_rate = args.videoBitrate
    debug(&"video bitrate: {encoderCtx.bit_rate}")
  else:
    debug(&"[auto] video bitrate: {encoderCtx.bit_rate}")

  let sar = src.video[0].codecpar.sample_aspect_ratio
  if sar != 0:
    encoderCtx.sample_aspect_ratio = sar

  for src, cn in cns:
    if len(cn.video) > 0:
      if args.noSeek:
        seekCost[src] = int(high(uint32) - 1)
        tous[src] = 1000
      else:
        # Keyframes are usually spread out every 5 seconds or less.
        seekCost[src] = toInt(targetFps * AVRational(num: 5, den: 1))
        tous[src] = 1000

      if src == firstSrc and encoderCtx.pix_fmt != AV_PIX_FMT_NONE:
        pix_fmt = AVPixelFormat(cn.video[0].codecpar.format)

  debug(&"Clips: {tl.v}")

  var needValidFmt = true
  if codec.pix_fmts != nil:
    var i = 0
    while codec.pix_fmts[i].cint != -1:
      if pix_fmt == codec.pix_fmts[i]:
        needValidFmt = false
        break
      i += 1

  if needValidFmt:
    if codec.canonicalName == "gif":
      pix_fmt = AV_PIX_FMT_RGB8
    elif codec.canonicalName == "prores":
      pix_fmt = AV_PIX_FMT_YUV422P10LE
    else:
      pix_fmt = AV_PIX_FMT_YUV420P

  if args.vprofile != "":
    encoderCtx.setProfileOrErr(args.vprofile)

  encoderCtx.pix_fmt = pix_fmt
  encoderCtx.open()
  if avcodec_parameters_from_context(outputStream.codecpar, encoderCtx) < 0:
    error "Could not copy encoder parameters to stream"

  let pixFmtName = $av_get_pix_fmt_name(pix_fmt)
  let graphTb = av_inv_q(targetFps)
  let bg = tl.background.toString
  let globalScaleArgs = &"{tl.res[0]}:{tl.res[1]}:force_original_aspect_ratio=decrease:eval=frame"

  if needsScaling:
    let bufferArgs = &"video_size={tl.res[0]}x{tl.res[1]}:pix_fmt={pixFmtName}:time_base={graphTb}:pixel_aspect=1/1"

    scaleGraph = newGraph()
    let bufferSrc = scaleGraph.add("buffer", bufferArgs)
    let scaleFilter = scaleGraph.add("scale", &"{targetWidth}:{targetHeight}")
    let bufferSink = scaleGraph.add("buffersink")

    scaleGraph.linkNodes(@[bufferSrc, scaleFilter, bufferSink]).configure()

  # First few frames can have an abnormal keyframe count, so never seek there.
  var seekThreshold = 10
  var seekFrame = none(int)
  var framesSaved = 0

  var nullFrame = makeSolid(targetWidth, targetHeight, args.background)
  var frameIndex = -1
  var frame: ptr AVFrame = av_frame_clone(nullFrame)
  var objList: seq[VideoFrame] = @[]

  return (encoderCtx, outputStream, iterator(): (ptr AVFrame, int) =
    # Process each frame in timeline order like Python version
    for index in 0 ..< tl.`end`:
      objList = @[]

      for layer in tl.v:
        for obj in layer.clips:
          if index >= obj.start and index < (obj.start + obj.dur):
            let i = int(round(float(obj.offset + index - obj.start) * obj.speed))
            objList.add VideoFrame(index: i, src: obj.src)

      if tl.chunks.isSome:
        # When there can be valid gaps in the timeline.
        frame = av_frame_clone(nullFrame)
      # else, use the last frame

      for obj in objList:
        var myStream: ptr AVStream = cns[obj.src].video[0]
        if frameIndex > obj.index:
          debug(&"Seek: {frameIndex} -> 0")
          cns[obj.src].seek(0)
          avcodec_flush_buffers(decoders[obj.src])

        while frameIndex < obj.index:
          # Check if skipping ahead is worth it.
          if obj.index - frameIndex > seekCost[obj.src] and frameIndex > seekThreshold:
            seekThreshold = frameIndex + (seekCost[obj.src] div 2)
            seekFrame = some(frameIndex)
            debug &"Seek: {frameIndex} -> {obj.index}"
            cns[obj.src].seek(obj.index * tous[obj.src], stream = myStream)
            avcodec_flush_buffers(decoders[obj.src])

          let decoder: ptr AVCodecContext = decoders[obj.src]
          var foundFrame = false
          for decodedFrame in cns[obj.src].flushDecode(myStream.index.cint, decoder, frame):
            frame = decodedFrame
            frameIndex = int(round(decodedFrame.time(myStream.time_base) * tl.tb.float))
            foundFrame = true
            break

          if not foundFrame:
            frame = av_frame_clone(nullFrame)
            break

          if seekFrame.isSome:
            debug &"Skipped {frameIndex - seekFrame.get} frame indexes"
            framesSaved += frameIndex - seekFrame.get
            seekFrame = none(int)

          if (frame.width.int, frame.height.int) != tl.res:
            var resGraph = newGraph()
            let bufferArgs = &"video_size={frame.width}x{frame.height}:pix_fmt={pixFmtName}:time_base={graphTb}:pixel_aspect=1/1"
            let bufferSrc = resGraph.add("buffer", bufferArgs)
            let scaleFilter = resGraph.add("scale", globalScaleArgs)
            let padFilter = resGraph.add("pad", &"{tl.res[0]}:{tl.res[1]}:-1:-1:color={bg}")
            let bufferSink = resGraph.add("buffersink")

            resGraph.linkNodes(@[bufferSrc, scaleFilter, padFilter, bufferSink]).configure()
            resGraph.push(frame)
            let oldFrame = frame
            frame = resGraph.pull()
            if oldFrame != nil and oldFrame != nullFrame:
              av_frame_free(addr oldFrame)
            resGraph.cleanup()

      if scaleGraph != nil and frame.width != targetWidth:
        scaleGraph.push(frame)
        let oldFrame = frame
        frame = scaleGraph.pull()
        if oldFrame != nil and oldFrame != nullFrame:
          av_frame_free(addr oldFrame)

      let reformattedFrame = frame.reformat(pix_fmt)
      if reformattedFrame != nil and reformattedFrame != frame:
        let oldFrame = frame
        frame = reformattedFrame
        if oldFrame != nil and oldFrame != nullFrame:
          av_frame_free(addr oldFrame)

      frame.pts = index.int64
      frame.time_base = av_inv_q(tl.tb)
      yield (frame, index)

    if scaleGraph != nil:
      scaleGraph.cleanup()
    av_frame_free(addr nullFrame)
    debug(&"Total frames saved seeking: {framesSaved}"))
