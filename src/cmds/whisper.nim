import std/[strformat, strutils]
import ../ffmpeg
import ../av
import ../log
import ../util/fun


proc main*(cArgs: seq[string]) =
  var isDebug = false
  var inputPath: string = ""
  var model: string = ""
  var queue: int = 10
  var vadModel: string = ""

  if cArgs.len < 1:
    echo "Whisper front-end"
    quit(0)

  var expecting: string = ""
  for rawKey in cArgs:
    let key = handleKey(rawKey)
    case key:
    of "--debug":
      isDebug = true
    of "--queue":
      expecting = "queue"
    of "--vad-model":
      expecting = "vad-model"
    else:
      if key.startsWith("--"):
        error &"Unknown option: {key}"

      case expecting:
      of "":
        if inputPath == "":
          inputPath = key
        elif model == "":
          model = key
      of "queue":
        queue = parseInt(key)
      of "vad-model":
        vadModel = key
      expecting = ""

  if inputPath == "":
    error "A media file is needed"
  if model == "":
    error "A model is needed, you came find them here: https://huggingface.co/ggerganov/whisper.cpp"
  if queue < 1 or queue > 1000:
    error &"Invalid queue value: {queue}"

  if not isDebug:
    av_log_set_level(AV_LOG_QUIET)

  let input = (try: av.open(inputPath) except: error "Invalid media file")
  defer: input.close()

  if input.audio.len == 0:
    error "No audio stream found"
  let audioStreamIndex = input.audio[0].index
  
  let filterGraph = avfilter_graph_alloc()
  defer: avfilter_graph_free(addr filterGraph)
  
  # Create buffer source for audio input
  let abuffer = avfilter_get_by_name("abuffer")
  var bufferCtx: ptr AVFilterContext
  
  let audioStream = input.streams[audioStreamIndex]
  let sampleRate = audioStream.codecpar.sample_rate
  let channelLayout = audioStream.codecpar.ch_layout.u.mask
  let sampleFormat = cast[AVSampleFormat](audioStream.codecpar.format)

  # Get sample format name
  let sampleFmtName = av_get_sample_fmt_name(cint(sampleFormat))
  let bufferArgs = "sample_rate=" & $sampleRate & ":sample_fmt=" & $sampleFmtName & ":channel_layout=" & $channelLayout

  if avfilter_graph_create_filter(addr bufferCtx, abuffer, "in", bufferArgs.cstring, nil, filterGraph) < 0:
    echo "Failed to create buffer source"
    quit(1)

  let whisperFilter = avfilter_get_by_name("whisper")
  var whisperCtx: ptr AVFilterContext
  var whisperArgs = &"model={model}:queue={queue}"
  if vadModel != "":
    whisperArgs &= ":vad_model=" & vadModel

  if avfilter_graph_create_filter(addr whisperCtx, whisperFilter, "whisper", whisperArgs.cstring, nil, filterGraph) < 0:
    error &"Failed to create whisper filter with model: {model}"

  # Create buffer sink
  let abuffersink = avfilter_get_by_name("abuffersink")
  var sinkCtx: ptr AVFilterContext

  if avfilter_graph_create_filter(addr sinkCtx, abuffersink, "out", nil, nil, filterGraph) < 0:
    error "Failed to create buffer sink"

  # Link filters: buffer -> whisper -> sink
  if avfilter_link(bufferCtx, 0, whisperCtx, 0) < 0:
    error "Failed to link buffer to whisper"
  if avfilter_link(whisperCtx, 0, sinkCtx, 0) < 0:
    error "Failed to link whisper to sink"

  if avfilter_graph_config(filterGraph, nil) < 0:
    error "Failed to configure filter graph"

  # Set up decoder for the audio stream
  let decoderCtx = initDecoder(audioStream.codecpar)
  defer: avcodec_free_context(addr decoderCtx)

  let frame = av_frame_alloc()
  defer: av_frame_free(addr frame)
  
  let outputFrame = av_frame_alloc()
  defer: av_frame_free(addr outputFrame)
  
  for decodedFrame in input.decode(cint(audioStreamIndex), decoderCtx, frame):
    if av_buffersrc_write_frame(bufferCtx, decodedFrame) < 0:
      echo "Error feeding frame to filter"
      continue
    
    # Try to get output from whisper filter - check frame metadata for subtitle text
    while av_buffersink_get_frame_flags(sinkCtx, outputFrame, 0) >= 0:
      # Check frame metadata for whisper text
      if outputFrame.metadata != nil:
        let whisperTextEntry = av_dict_get(outputFrame.metadata, "lavfi.whisper.text", nil, 0)
        if whisperTextEntry != nil and whisperTextEntry.value != nil:
          echo $whisperTextEntry.value
      av_frame_unref(outputFrame)
  
  # Flush the filter
  if av_buffersrc_write_frame(bufferCtx, nil) >= 0:
    while av_buffersink_get_frame_flags(sinkCtx, outputFrame, 0) >= 0:
      if outputFrame.metadata != nil:
        let whisperTextEntry = av_dict_get(outputFrame.metadata, "lavfi.whisper.text", nil, 0)
        if whisperTextEntry != nil and whisperTextEntry.value != nil:
          echo $whisperTextEntry.value
      av_frame_unref(outputFrame)
