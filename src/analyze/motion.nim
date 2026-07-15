import std/[math, options, strformat]

when defined(emscripten) or defined(amd64) or defined(i386):
  import std/bitops

import ../[av, cache, ffmpeg, log]
import ../util/[bar, rational, dnorm16]

when defined(arm64) or defined(aarch64):
  type Vec8x16 {.importc: "uint8x16_t", header: "<arm_neon.h>".} = object

  proc neonLoad8(p: pointer): Vec8x16 {.importc: "vld1q_u8",
      header: "<arm_neon.h>".}
  proc neonEqual8(a, b: Vec8x16): Vec8x16 {.importc: "vceqq_u8",
      header: "<arm_neon.h>".}
  proc neonSumLong8(v: Vec8x16): uint16 {.importc: "vaddlvq_u8",
      header: "<arm_neon.h>".}

elif defined(emscripten):
  type V128 {.importc: "v128_t", header: "<wasm_simd128.h>".} = object

  proc wasmLoad(p: pointer): V128 {.importc: "wasm_v128_load",
      header: "<wasm_simd128.h>".}
  proc wasmEqual8(a, b: V128): V128 {.importc: "wasm_i8x16_eq",
      header: "<wasm_simd128.h>".}
  proc wasmBitmask8(v: V128): uint32 {.importc: "wasm_i8x16_bitmask",
      header: "<wasm_simd128.h>".}

elif defined(amd64) or defined(i386):
  type M128i {.importc: "__m128i", header: "<emmintrin.h>".} = object

  proc sseLoad(p: pointer): M128i {.importc: "_mm_loadu_si128",
      header: "<emmintrin.h>".}
  proc sseEqual8(a, b: M128i): M128i {.importc: "_mm_cmpeq_epi8",
      header: "<emmintrin.h>".}
  proc sseBitmask8(v: M128i): cint {.importc: "_mm_movemask_epi8",
      header: "<emmintrin.h>".}

proc countDifferentPixels(a, b: ptr UncheckedArray[uint8], len: int): int32 =
  ## Count differing gray pixels using 16-byte vectors where available.
  var i = 0
  when defined(arm64) or defined(aarch64):
    while i + 16 <= len:
      let equalBytes = neonEqual8(neonLoad8(addr a[i]), neonLoad8(addr b[i]))
      result += 16 - int32(neonSumLong8(equalBytes) div 255)
      i += 16
  elif defined(emscripten):
    while i + 16 <= len:
      let equalMask = wasmBitmask8(wasmEqual8(wasmLoad(addr a[i]),
        wasmLoad(addr b[i])))
      result += 16 - int32(countSetBits(equalMask))
      i += 16
  elif defined(amd64) or defined(i386):
    while i + 16 <= len:
      let equalMask = uint32(sseBitmask8(sseEqual8(sseLoad(addr a[i]),
        sseLoad(addr b[i]))))
      result += 16 - int32(countSetBits(equalMask))
      i += 16

  while i < len:
    result += int32(ord(a[i] != b[i]))
    inc i

type VideoProcessor* = object
  formatCtx*: ptr AVFormatContext
  codecCtx*: ptr AVCodecContext
  tb*: AVRational
  videoIndex*: cint

proc createFilterGraph(timeBase: AVRational, pixFmtName: string,
    codecCtx: ptr AVCodecContext, filter: string): (ptr AVFilterGraph,
    ptr AVFilterContext, ptr AVFilterContext) =
  var filterGraph: ptr AVFilterGraph = avfilter_graph_alloc()
  var bufferSrc: ptr AVFilterContext = nil
  var bufferSink: ptr AVFilterContext = nil

  if filterGraph == nil:
    error "Could not allocate filter graph"

  let width = codecCtx.width
  let height = codecCtx.height

  # Create buffer source with proper arguments
  let bufferArgs = cstring(
    &"video_size={width}x{height}:pix_fmt={pixFmtName}:time_base={timeBase.num}/{timeBase.den}:pixel_aspect=1/1"
  )

  var ret = avfilter_graph_create_filter(addr bufferSrc, avfilter_get_by_name("buffer"),
                                        "in", bufferArgs, nil, filterGraph)
  if ret < 0:
    error &"Cannot create buffer source with args: {bufferArgs}, error code: {ret}"

  # Create buffer sink
  ret = avfilter_graph_create_filter(addr bufferSink, avfilter_get_by_name("buffersink"),
                                    "out", nil, nil, filterGraph)
  if ret < 0:
    error "Cannot create buffer sink"

  # Parse and configure the filter chain
  var inputs = avfilter_inout_alloc()
  var outputs = avfilter_inout_alloc()

  if inputs == nil or outputs == nil:
    error "Could not allocate filter inputs/outputs"

  outputs.name = av_strdup("in")
  outputs.filter_ctx = bufferSrc
  outputs.pad_idx = 0
  outputs.next = nil

  inputs.name = av_strdup("out")
  inputs.filter_ctx = bufferSink
  inputs.pad_idx = 0
  inputs.next = nil

  let filterC = filter.cstring
  ret = avfilter_graph_parse_ptr(filterGraph, filterC, addr inputs, addr outputs, nil)
  if ret < 0:
    error "Could not parse filter graph"

  if avfilter_graph_config(filterGraph, nil) < 0:
    error "Could not configure filter graph"

  avfilter_inout_free(addr inputs)
  avfilter_inout_free(addr outputs)

  return (filterGraph, bufferSrc, bufferSink)

iterator videoPipeline*(processor: VideoProcessor, filter: string): ptr AVFrame =
  var packet = av_packet_alloc()
  var frame = av_frame_alloc()
  var filteredFrame = av_frame_alloc()
  var ret: cint

  if packet == nil or frame == nil or filteredFrame == nil:
    error "Could not allocate packet/frame"

  defer:
    av_packet_free(addr packet)
    av_frame_free(addr frame)
    av_frame_free(addr filteredFrame)
    if processor.codecCtx != nil:
      avcodec_free_context(addr processor.codecCtx)

  let timeBase = processor.tb

  let pixelFormat = processor.codecCtx.pix_fmt
  let pixFmtName = $pixelFormat
  if pixFmtName == "":
    error &"Could not get pixel format name for format: {ord(pixelFormat)}"

  let (filterGraph, bufferSrc, bufferSink) = createFilterGraph(
    timeBase, pixFmtName, processor.codecCtx, filter
  )

  defer:
    if filterGraph != nil:
      avfilter_graph_free(addr filterGraph)

  while av_read_frame(processor.formatCtx, packet) >= 0:
    defer: av_packet_unref(packet)

    if packet.stream_index == processor.videoIndex:
      ret = avcodec_send_packet(processor.codecCtx, packet)
      if ret < 0 and ret != AVERROR_EAGAIN:
        error &"Error sending packet to decoder: {av_err2str(ret)}"

      while ret >= 0:
        ret = avcodec_receive_frame(processor.codecCtx, frame)
        if ret == AVERROR_EAGAIN or ret == AVERROR_EOF:
          break
        elif ret < 0:
          error &"Error receiving frame from decoder: {av_err2str(ret)}"

        if frame.pts == AV_NOPTS_VALUE:
          continue

        if av_buffersrc_write_frame(bufferSrc, frame) < 0:
          error "Error adding frame to filter"

        ret = av_buffersink_get_frame(bufferSink, filteredFrame)
        if ret < 0:
          continue

        yield filteredFrame
        av_frame_unref(filteredFrame)

  discard avcodec_send_packet(processor.codecCtx, nil)
  while avcodec_receive_frame(processor.codecCtx, frame) >= 0:
    if frame.pts == AV_NOPTS_VALUE:
      continue

    ret = av_buffersrc_write_frame(bufferSrc, frame)
    if ret >= 0:
      ret = av_buffersink_get_frame(bufferSink, filteredFrame)
      if ret >= 0:
        yield filteredFrame
        av_frame_unref(filteredFrame)

iterator motionness*(processor: var VideoProcessor, width, blur: int32,
    rect: Unorm24x4): Unorm16 =
  if width < 1:
    error "motion: width must be greater than 0"
  if blur < 0:
    error "motion: blur must be greater than or equal to 0"
  let (x, y, w, h) = unpackUnorm24x4(rect)
  if not(w > 0.0'f32 and h > 0.0'f32):
    error "motion: w and h must be greater than 0"
  var totalPixels: int = 0
  var firstTime: bool = true
  var prevIndex: int64 = -1
  var prevFrame: ptr UncheckedArray[uint8] = nil
  var currentFrame: ptr UncheckedArray[uint8] = nil

  defer:
    if prevFrame != nil:
      dealloc(prevFrame)
    if currentFrame != nil:
      dealloc(currentFrame)

  var filter = &"scale={width}:-1,format=gray,gblur=sigma={blur}"
  if x != 0.0 or y != 0.0 or w != 1.0 or h != 1.0:
    # Crop before scaling so the analyzed region gets the full `width` resolution.
    let iw = processor.codecCtx.width
    let ih = processor.codecCtx.height
    let cw = max(1'i32, int32(round(iw.float32 * w)))
    let ch = max(1'i32, int32(round(ih.float32 * h)))
    let cx = clamp(int32(round(iw.float32 * x)), 0'i32, iw - cw)
    let cy = clamp(int32(round(ih.float32 * y)), 0'i32, ih - ch)
    filter = &"crop={cw}:{ch}:{cx}:{cy}," & filter
  for filteredFrame in processor.videoPipeline(filter):
    let frameTime = (filteredFrame.pts * processor.formatCtx.streams[
        processor.videoIndex].time_base).float64
    let index = round(frameTime * processor.tb.float64).int64

    if totalPixels == 0:
      totalPixels = filteredFrame.width * filteredFrame.height
      prevFrame = cast[ptr UncheckedArray[uint8]](alloc(totalPixels))
      currentFrame = cast[ptr UncheckedArray[uint8]](alloc(totalPixels))

    # linesize includes alignment padding (e.g. width 400 -> stride 416), so
    # a flat copy of width*height bytes drifts rows; copy row by row.
    let stride = filteredFrame.linesize[0].int
    let rowBytes = filteredFrame.width.int
    if stride == rowBytes:
      copyMem(currentFrame, filteredFrame.data[0], totalPixels)
    else:
      for y in 0 ..< filteredFrame.height.int:
        copyMem(addr currentFrame[y * rowBytes],
          cast[pointer](cast[int](filteredFrame.data[0]) + y * stride), rowBytes)

    var value: Unorm16 = toUnorm16(0.0'f32)
    if not firstTime:
      # Calculate motion by comparing with previous frame
      let diffCount = countDifferentPixels(prevFrame, currentFrame, totalPixels)

      value = toUnorm16(float32(diffCount) / float32(totalPixels))
    else:
      firstTime = false

    # Yield value for each frame index between previous and current
    for i in 0 ..< index - prevIndex:
      yield value

    swap(prevFrame, currentFrame)
    prevIndex = index

proc motion*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
  stream, width, blur: int32, rect: Unorm24x4): seq[Unorm16] =
  let cacheArgs = &"{stream},{width},{blur},{rect}"
  if not noCache:
    let cacheData = readCache[Unorm16](path, tb, "motion", cacheArgs)
    if cacheData.isSome:
      return cacheData.get()

  if stream < 0 or stream >= container.video.len:
    error &"motion: video stream '{stream}' does not exist."

  let videoStream: ptr AVStream = container.video[stream]
  # Rewind so a shared container can be re-read for additional streams.
  container.seek(0)

  var processor = VideoProcessor(
    formatCtx: container.formatContext,
    codecCtx: initDecoder(videoStream.codecpar),
    tb: tb,
    videoIndex: videoStream.index,
  )

  let inaccurateDur = (
    if videoStream.duration != AV_NOPTS_VALUE and videoStream.time_base.isValid:
      float(videoStream.duration) * float(videoStream.time_base * tb)
    else:
      container.duration * float(tb)
  )
  bar.start(inaccurateDur, "Analyzing motion")

  var i: float = 0
  for value in processor.motionness(width, blur, rect):
    result.add value
    bar.tick(i)
    i += 1

  bar.`end`()

  if not noCache:
    writeCache(result, tb, path, "motion", cacheArgs)
