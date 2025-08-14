import std/strformat
import log
import ffmpeg

type AudioResampler* = object
  format: AVSampleFormat
  layout: AVChannelLayout
  rate: int
  frame_size: int
  graph*: ptr AVFilterGraph
  `template`: ptr AVFrame
  is_passthrough: bool
  abuffer: ptr AVFilterContext
  abuffersink: ptr AVFilterContext

proc stringToChannelLayout(layout: string): AVChannelLayout =
  if layout == "mono":
    result.nb_channels = 1
    result.order = 0 # AV_CHANNEL_ORDER_NATIVE
    result.u.mask = 1 # AV_CH_LAYOUT_MONO
  elif layout == "stereo":
    result.nb_channels = 2
    result.order = 0 # AV_CHANNEL_ORDER_NATIVE
    result.u.mask = 3 # AV_CH_LAYOUT_STEREO
  else:
    result.nb_channels = 0
    result.order = 0
    result.u.mask = 0
  return result

proc getFormatName(format: AVSampleFormat): string =
  let name = av_get_sample_fmt_name(format.cint)
  if name != nil:
    return $name
  else:
    return "none"

proc getLayoutName(layout: AVChannelLayout): string =
  if layout.nb_channels == 1:
    return "mono"
  elif layout.nb_channels == 2:
    return "stereo"
  else:
    return fmt"{layout.nb_channels}channels"

proc newAudioResampler*(format: AVSampleFormat, layout: string = "", rate: int = 0,
    frame_size: int = 0): AudioResampler =
  result.format = format
  if layout != "":
    result.layout = stringToChannelLayout(layout)
  else:
    result.layout = AVChannelLayout()
  result.rate = rate
  result.frame_size = frame_size
  result.graph = nil
  result.`template` = nil
  result.is_passthrough = false
  result.abuffer = nil
  result.abuffersink = nil

proc `=destroy`*(resampler: var AudioResampler) =
  if resampler.graph != nil:
    avfilter_graph_free(addr resampler.graph)
  if resampler.`template` != nil:
    av_frame_free(addr resampler.`template`)

proc resample*(resampler: var AudioResampler, frame: ptr AVFrame): seq[ptr AVFrame] =
  # We don't have any input, so don't bother even setting up
  if resampler.graph == nil and frame == nil:
    return @[]

  # Shortcut for passthrough
  if resampler.is_passthrough:
    return @[frame]

  # Take source settings from the first frame
  if resampler.graph == nil:
    resampler.`template` = av_frame_alloc()
    if resampler.`template` == nil:
      raise newException(ValueError, "Could not allocate template frame")

    # Copy frame properties to template
    av_frame_unref(resampler.`template`)
    if av_frame_ref(resampler.`template`, frame) < 0:
      raise newException(ValueError, "Could not reference template frame")

    # Set some default descriptors
    if resampler.format == AV_SAMPLE_FMT_NONE:
      resampler.format = AVSampleFormat(frame.format)
    if resampler.layout.nb_channels == 0:
      resampler.layout = frame.ch_layout
    if resampler.rate == 0:
      resampler.rate = frame.sample_rate

    # Check if we can passthrough or if there is actually work to do
    if (frame.format.int == resampler.format.int and
        frame.ch_layout.nb_channels == resampler.layout.nb_channels and
        frame.ch_layout.u.mask == resampler.layout.u.mask and
        frame.sample_rate == resampler.rate.cint and
        resampler.frame_size == 0):
      resampler.is_passthrough = true
      return @[frame]

    # Handle resampling with aformat filter
    # (similar to configure_output_audio_filter from ffmpeg)
    resampler.graph = avfilter_graph_alloc()
    if resampler.graph == nil:
      raise newException(ValueError, "Could not allocate filter graph")

    # Create buffer source
    var extra_args = ""
    if frame.pts != AV_NOPTS_VALUE:
      extra_args = fmt":time_base={resampler.`template`.time_base}"

    let input_layout_name = getLayoutName(frame.ch_layout)
    let input_format_name = getFormatName(AVSampleFormat(frame.format))

    let abuffer_args = fmt"sample_rate={frame.sample_rate}:sample_fmt={input_format_name}:channel_layout={input_layout_name}{extra_args}"

    var ret = avfilter_graph_create_filter(addr resampler.abuffer, avfilter_get_by_name("abuffer"),
                                          "in", abuffer_args.cstring, nil,
                                              resampler.graph)
    if ret < 0:
      raise newException(ValueError, fmt"Could not create abuffer: {ret}")

    # Create aformat filter
    let output_layout_name = getLayoutName(resampler.layout)
    let output_format_name = getFormatName(resampler.format)
    let aformat_args = fmt"sample_rates={resampler.rate}:sample_fmts={output_format_name}:channel_layouts={output_layout_name}"

    var aformat: ptr AVFilterContext = nil
    ret = avfilter_graph_create_filter(addr aformat, avfilter_get_by_name("aformat"),
                                      "aformat", aformat_args.cstring, nil,
                                          resampler.graph)
    if ret < 0:
      raise newException(ValueError, fmt"Could not create aformat: {ret}")

    # Create buffer sink
    ret = avfilter_graph_create_filter(addr resampler.abuffersink, avfilter_get_by_name("abuffersink"),
                                      "out", nil, nil, resampler.graph)

    # Link filters: abuffer -> aformat -> abuffersink
    ret = avfilter_link(resampler.abuffer, 0, aformat, 0)
    ret = avfilter_link(aformat, 0, resampler.abuffersink, 0)
    ret = avfilter_graph_config(resampler.graph, nil)
    if ret < 0:
      raise newException(ValueError, fmt"Could not configure filter graph: {ret}")

  if frame != nil:
    # Only validate critical properties that would break the filter graph
    if (frame.format != resampler.`template`.format or
        frame.ch_layout.nb_channels != resampler.`template`.ch_layout.nb_channels or
        frame.sample_rate != resampler.`template`.sample_rate):

      #error &"Frame validation failed - format: {frame.format} vs {resampler.`template`.format}, channels: {frame.ch_layout.nb_channels} vs {resampler.`template`.ch_layout.nb_channels}, sample_rate: {frame.sample_rate} vs {resampler.`template`.sample_rate}"
      error "Frame does not match AudioResampler setup"

  let ret = av_buffersrc_write_frame(resampler.abuffer, frame)
  if ret < 0:
    error &"Error pushing frame to filter: {ret}"

  # Pull output frames
  var output: seq[ptr AVFrame] = @[]
  while true:
    var outFrame = av_frame_alloc()
    if outFrame == nil:
      error "Could not alloc output frame"

    if av_buffersink_get_frame(resampler.abuffersink, outFrame) < 0:
      av_frame_free(addr outFrame)
      break

    output.add(outFrame)

  return output
