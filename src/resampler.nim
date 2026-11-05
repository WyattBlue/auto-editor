import std/strformat
import log
import ffmpeg
import util/rational

type AudioResampler* = object
  graph*: ptr AVFilterGraph
  layout: AVChannelLayout
  abuffer: ptr AVFilterContext
  abuffersink: ptr AVFilterContext
  frameSize: cint
  templateFormat: cint
  templateRate: cint
  templateLayout: AVChannelLayout
  format: cint
  rate: cint
  isPassthrough: bool


func getFormatName(format: cint): string =
  let name = av_get_sample_fmt_name(format)
  (if name != nil: $name else: "none")

proc newAudioResampler*(format: AVSampleFormat, layout: ref AVChannelLayout, rate: cint,
    frameSize: cint = 0): AudioResampler =
  result.graph = nil
  discard av_channel_layout_copy(addr result.layout, addr layout[])
  result.abuffer = nil
  result.abuffersink = nil
  result.frameSize = frameSize
  result.format = format.cint
  result.rate = rate
  result.isPassthrough = false

proc `=destroy`*(resampler: var AudioResampler) =
  # A custom destroy hook skips field destruction, so release fields here.
  if resampler.graph != nil:
    avfilter_graph_free(addr resampler.graph)
  `=destroy`(resampler.layout)
  `=destroy`(resampler.templateLayout)

proc `=copy`*(dest: var AudioResampler, src: AudioResampler) {.error.}

proc collect(resampler: var AudioResampler, into: var seq[ptr AVFrame]) =
  while true:
    var outFrame = av_frame_alloc()
    if outFrame == nil:
      error "Could not alloc output frame"
    if av_buffersink_get_frame(resampler.abuffersink, outFrame) < 0:
      av_frame_free(addr outFrame)
      break
    into.add(outFrame)

proc cloneFrame(frame: ptr AVFrame): ptr AVFrame =
  result = av_frame_clone(frame)
  if result == nil:
    error "Could not clone passthrough frame"

func matchesTemplate(resampler: AudioResampler, frame: ptr AVFrame): bool =
  frame.format == resampler.templateFormat and
    frame.sample_rate == resampler.templateRate and
    av_channel_layout_compare(addr frame.ch_layout,
      addr resampler.templateLayout) == 0

proc resample*(resampler: var AudioResampler, frame: ptr AVFrame): seq[ptr AVFrame] =
  let configured = resampler.graph != nil or resampler.isPassthrough
  # We don't have any input, so don't bother even setting up
  if not configured and frame == nil:
    return @[]

  # The input can change mid-stream (an AAC stream may switch channel
  # configurations). The output stays as first set up: finish the graph built
  # for the old input and build another for the new one.
  if configured and frame != nil and not resampler.matchesTemplate(frame):
    if resampler.graph != nil:
      discard av_buffersrc_write_frame(resampler.abuffer, nil)
      resampler.collect(result)
      avfilter_graph_free(addr resampler.graph)
      resampler.abuffer = nil
      resampler.abuffersink = nil
    resampler.isPassthrough = false

  if resampler.isPassthrough:
    # Nothing is buffered, so a flush has nothing to return.
    if frame == nil: return @[]
    return @[cloneFrame(frame)]

  # Take source settings from the first frame
  if resampler.graph == nil:
    # Set some default descriptors
    if resampler.format == AV_SAMPLE_FMT_NONE:
      resampler.format = frame.format
    if resampler.layout.nb_channels == 0:
      discard av_channel_layout_copy(addr resampler.layout, addr frame.ch_layout)
    if resampler.rate == 0:
      resampler.rate = frame.sample_rate

    resampler.templateFormat = frame.format
    resampler.templateRate = frame.sample_rate
    discard av_channel_layout_copy(addr resampler.templateLayout, addr frame.ch_layout)

    # Check if we can passthrough or if there is actually work to do
    if (frame.format == resampler.format and
        frame.sample_rate == resampler.rate and
        resampler.frameSize == 0 and
        av_channel_layout_compare(addr frame.ch_layout, addr resampler.layout) == 0):
      resampler.isPassthrough = true
      result.add cloneFrame(frame)
      return

    resampler.graph = avfilter_graph_alloc()
    if resampler.graph == nil:
      error "Could not allocate filter graph"

    let abuffer = avfilter_get_by_name("abuffer")
    let aformat = avfilter_get_by_name("aformat")
    let asink = avfilter_get_by_name("abuffersink")

    let inputFormatName = getFormatName(frame.format)
    let extraArgs =
      if frame.pts != AV_NOPTS_VALUE: ":time_base=" & $frame.time_base
      else: ""
    let abufferArgs = &"sample_rate={frame.sample_rate}:sample_fmt={inputFormatName}:channel_layout={frame.ch_layout}{extraArgs}"

    var ret = avfilter_graph_create_filter(addr resampler.abuffer, abuffer, nil,
        abufferArgs.cstring, nil, resampler.graph)
    if ret < 0:
      error "Could not create abuffer"

    let outputFormatName = getFormatName(resampler.format)
    let aformatArgs = &"sample_rates={resampler.rate}:sample_fmts={outputFormatName}:channel_layouts={resampler.layout}"

    var aformatCtx: ptr AVFilterContext = nil
    ret = avfilter_graph_create_filter(addr aformatCtx, aformat, nil,
        aformatArgs.cstring, nil, resampler.graph)
    if ret < 0:
      error "Could not create aformat"

    ret = avfilter_graph_create_filter(addr resampler.abuffersink, asink, nil, nil, nil,
        resampler.graph)
    if ret < 0:
      error "Could not create abuffersink"
    if resampler.frameSize > 0:
      av_buffersink_set_frame_size(resampler.abuffersink, resampler.frameSize.cuint)

    if ret >= 0: ret = avfilter_link(resampler.abuffer, 0, aformatCtx, 0)
    if ret >= 0: ret = avfilter_link(aformatCtx, 0, resampler.abuffersink, 0)
    if ret >= 0: ret = avfilter_graph_config(resampler.graph, nil)
    if ret < 0: error "Failed to connect filters"

  let ret = av_buffersrc_write_frame(resampler.abuffer, frame)
  if ret < 0:
    error &"Error pushing frame to filter: {ret}"

  resampler.collect(result)
