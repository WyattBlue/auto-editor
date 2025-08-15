import std/strformat
import std/options
import std/math

import ../av
import ../log
import ../cache
import ../ffmpeg
import ../util/bar

type
  VideoProcessor* = object
    formatCtx*: ptr AVFormatContext
    codecCtx*: ptr AVCodecContext
    tb*: AVRational
    videoIndex*: cint

proc createFilterGraph(timeBase: AVRational, pixFmtName: cstring,
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

  ret = avfilter_graph_config(filterGraph, nil)
  if ret < 0:
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
  let pixFmtName = av_get_pix_fmt_name(pixelFormat)
  if pixFmtName == nil:
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

iterator motionness*(processor: var VideoProcessor, width, blur: int32): float32 =
  var totalPixels: int = 0
  var firstTime: bool = true
  var prev_index = -1
  var prevFrame: ptr UncheckedArray[uint8] = nil
  var currentFrame: ptr UncheckedArray[uint8] = nil

  defer:
    if prevFrame != nil:
      dealloc(prevFrame)
    if currentFrame != nil:
      dealloc(currentFrame)

  let filter = &"scale={width}:-1,format=gray,gblur=sigma={blur}"
  for filteredFrame in processor.videoPipeline(filter):
    let frameTime = (filteredFrame.pts * processor.formatCtx.streams[
        processor.videoIndex].time_base).float64
    let index = round(frameTime * processor.tb.float64).int64

    if totalPixels == 0:
      totalPixels = filteredFrame.width * filteredFrame.height
      prevFrame = cast[ptr UncheckedArray[uint8]](alloc(totalPixels))
      currentFrame = cast[ptr UncheckedArray[uint8]](alloc(totalPixels))

    copyMem(currentFrame, filteredFrame.data[0], totalPixels)

    var value: float32 = 0.0
    if not firstTime:
      # Calculate motion by comparing with previous frame
      var diffCount: int32 = 0
      for i in 0 ..< totalPixels:
        if prevFrame[i] != currentFrame[i]:
          inc diffCount

      value = float32(diffCount) / float32(totalPixels)
    else:
      value = 0.0
      firstTime = false

    # Yield value for each frame index between previous and current
    for i in 0 ..< index - prev_index:
      yield value

    swap(prevFrame, currentFrame)
    prev_index = index

proc motion*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
  stream, width, blur: int32): seq[float32] =
  let cacheArgs = &"{stream},{width},{blur}"
  let cacheData = readCache(path, tb, "motion", cacheArgs)
  if cacheData.isSome:
    return cacheData.get()

  if stream < 0 or stream >= container.video.len:
    error fmt"motion: video stream '{stream}' does not exist."

  let videoStream: ptr AVStream = container.video[stream]

  var processor = VideoProcessor(
    formatCtx: container.formatContext,
    codecCtx: initDecoder(videoStream.codecpar),
    tb: tb,
    videoIndex: videoStream.index,
  )

  var inaccurateDur: float = 1024.0
  if videoStream.duration != AV_NOPTS_VALUE and videoStream.time_base != AV_NOPTS_VALUE:
    inaccurateDur = float(videoStream.duration) * float(videoStream.time_base * tb)
  elif container.duration != 0.0:
    inaccurateDur = container.duration / float(tb)

  bar.start(inaccurateDur, "Analyzing motion")
  var i: float = 0
  for value in processor.motionness(width, blur):
    result.add value
    bar.tick(i)
    i += 1

  bar.`end`()

  writeCache(result, path, tb, "motion", cacheArgs)
