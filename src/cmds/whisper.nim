import std/strformat
import ../ffmpeg
import ../av
import ../log

proc main*(args: seq[string]) =
  if args.len < 1:
    echo "Whisper front-end"
    quit(0)

  let inputPath = args[0]
  let model = args[1]

  av_log_set_level(AV_LOG_QUIET)

  let input = av.open(inputPath)
  defer: input.close()

  # Use the `whisper` filter. From audio stream 0, print out the new subtitles
  
  # Find audio stream
  var audioStreamIndex = -1
  for i in 0..<input.streams.len:
    if input.streams[i].codecpar.codec_type == AVMEDIA_TYPE_AUDIO:
      audioStreamIndex = i
      break
  
  if audioStreamIndex == -1:
    echo "No audio stream found"
    quit(1)
  
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

  if avfilter_graph_create_filter(addr bufferCtx, abuffer, "in", bufferArgs, nil, filterGraph) < 0:
    echo "Failed to create buffer source"
    quit(1)

  # Create whisper filter - whisper filter outputs subtitles to stderr/stdout by default
  let whisperFilter = avfilter_get_by_name("whisper")
  var whisperCtx: ptr AVFilterContext
  # Don't use destination - let whisper output as info messages and set frame metadata
  let whisperArgs = "model=" & model

  if avfilter_graph_create_filter(addr whisperCtx, whisperFilter, "whisper", whisperArgs, nil, filterGraph) < 0:
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
