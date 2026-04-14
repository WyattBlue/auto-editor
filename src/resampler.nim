import std/strformat
import log
import ffmpeg

type AudioResampler* = object
  graph*: ptr AVFilterGraph
  layout: ref AVChannelLayout
  abuffer: ptr AVFilterContext
  abuffersink: ptr AVFilterContext
  frameSize: cint
  templateFormat: cint
  templateRate: cint
  format: cint
  rate: cint
  isPassthrough: bool


func getFormatName(format: cint): string =
  let name = av_get_sample_fmt_name(format)
  (if name != nil: $name else: "none")

func newAudioResampler*(format: AVSampleFormat, layout: ref AVChannelLayout, rate: cint,
    frameSize: cint = 0): AudioResampler =
  result.graph = nil
  result.layout = layout
  result.abuffer = nil
  result.abuffersink = nil
  result.frameSize = frameSize
  result.format = format.cint
  result.rate = rate
  result.isPassthrough = false

proc `=destroy`*(resampler: var AudioResampler) =
  if resampler.graph != nil:
    avfilter_graph_free(addr resampler.graph)

proc resample*(resampler: var AudioResampler, frame: ptr AVFrame): seq[ptr AVFrame] =
  # We don't have any input, so don't bother even setting up
  if resampler.graph == nil and frame == nil:
    return @[]

  if resampler.isPassthrough:
    let cloned = av_frame_clone(frame)
    if cloned == nil:
      error "Could not clone passthrough frame"
    return @[cloned]

  # Take source settings from the first frame
  if resampler.graph == nil:
    # Set some default descriptors
    if resampler.format == AV_SAMPLE_FMT_NONE:
      resampler.format = frame.format
    if resampler.layout.nb_channels == 0:
      discard av_channel_layout_copy(addr resampler.layout[], addr frame.ch_layout)
    if resampler.rate == 0:
      resampler.rate = frame.sample_rate

    resampler.templateFormat = frame.format
    resampler.templateRate = frame.sample_rate

    # Check if we can passthrough or if there is actually work to do
    if (frame.format == resampler.format and
        frame.sample_rate == resampler.rate and
        resampler.frameSize == 0 and
        av_channel_layout_compare(addr frame.ch_layout, addr resampler.layout[]) == 0):
      resampler.isPassthrough = true
      let cloned = av_frame_clone(frame)
      if cloned == nil:
        error "Could not clone passthrough frame"
      return @[cloned]

    resampler.graph = avfilter_graph_alloc()
    if resampler.graph == nil:
      error "Could not allocate filter graph"

    let abuffer = avfilter_get_by_name("abuffer")
    let aformat = avfilter_get_by_name("aformat")
    let asink = avfilter_get_by_name("abuffersink")

    let inputFormatName = getFormatName(frame.format)
    let extraArgs = (if frame.pts != AV_NOPTS_VALUE: &":time_base={frame.time_base}" else: "")
    let abufferArgs = &"sample_rate={frame.sample_rate}:sample_fmt={inputFormatName}:channel_layout={frame.ch_layout}{extraArgs}"

    var ret = avfilter_graph_create_filter(addr resampler.abuffer, abuffer, nil, abufferArgs.cstring, nil, resampler.graph)
    if ret < 0:
      error "Could not create abuffer"

    let outputFormatName = getFormatName(resampler.format)
    let aformatArgs = &"sample_rates={resampler.rate}:sample_fmts={outputFormatName}:channel_layouts={resampler.layout}"

    var aformatCtx: ptr AVFilterContext = nil
    ret = avfilter_graph_create_filter(addr aformatCtx, aformat, nil, aformatArgs.cstring, nil, resampler.graph)
    if ret < 0:
      error "Could not create aformat"

    ret = avfilter_graph_create_filter(addr resampler.abuffersink, asink, nil, nil, nil, resampler.graph)
    if ret < 0:
      error "Could not create abuffersink"
    if resampler.frameSize > 0:
      av_buffersink_set_frame_size(resampler.abuffersink, resampler.frameSize.cuint)

    if ret >= 0: ret = avfilter_link(resampler.abuffer, 0, aformatCtx, 0)
    if ret >= 0: ret = avfilter_link(aformatCtx, 0, resampler.abuffersink, 0)
    if ret >= 0: ret = avfilter_graph_config(resampler.graph, nil)
    if ret < 0: error "Failed to connect filters"

  if frame != nil:
    # Only validate critical properties that would break the filter graph
    if (frame.format != resampler.templateFormat or
        frame.sample_rate != resampler.templateRate or
        av_channel_layout_compare(addr frame.ch_layout, addr resampler.layout[]) != 0):
      error "Frame does not match resampler setup"

  let ret = av_buffersrc_write_frame(resampler.abuffer, frame)
  if ret < 0:
    error &"Error pushing frame to filter: {ret}"

  while true:
    var outFrame = av_frame_alloc()
    if outFrame == nil:
      error "Could not alloc output frame"

    if av_buffersink_get_frame(resampler.abuffersink, outFrame) < 0:
      av_frame_free(addr outFrame)
      break

    result.add(outFrame)
