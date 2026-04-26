import std/[heapqueue, os, options, sequtils, strformat, strutils, tables]
from std/math import round

import ../[av, ffmpeg, log, media, timeline]
import ../util/[bar, lang, rules]
import video
import audio
import subtitle

type Priority = object
  index: float64
  frame: ptr AVFrame
  stream: ptr AVStream

func initPriority(index: float64, frame: ptr AVFrame, stream: ptr AVStream): Priority =
  result.index = index
  result.frame = frame
  result.stream = stream

func `<`(a, b: Priority): bool = a.index < b.index

proc resolveAudioCodec(layer: seq[Clip], outExt: string, rules: Rules): AVCodecID =
  if layer.len == 0:
    return rules.defaultAud
  if outExt in [".wav", ".aiff", ".au"] and rules.defaultAud.isPCM:
    return rules.defaultAud

  let firstClip = layer[0]
  let srcMi = initMediaInfo(firstClip.src[])
  let stream = int(firstClip.stream)
  if stream >= srcMi.a.len:
    return rules.defaultAud

  let codec = srcMi.a[stream].codecId
  if codec notin rules.acodecs.mapIt(it.id):
    return (if rules.defaultAud == ID_NONE: ID_AAC else: rules.defaultAud)
  return codec

proc checkAudioCtx(ctx: ptr AVCodecContext, rate: cint) =
  if ctx.codec.sample_fmts == nil:
    error &"{ctx.codec.name}: No known audio formats avail."

  var myOut: pointer = nil
  var num: cint = 0
  discard avcodec_get_supported_config(
    ctx, nil, AV_CODEC_CONFIG_SAMPLE_RATE, 0.cuint, addr myOut, addr num
  )

  const AAC_AT_RATES = [48000.cint, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000]

  if myOut == nil:
    if ctx.codec.id == ID_AAC:
      if rate notin AAC_AT_RATES:
        error &"AudioToolbox only supports these samplerates: " & AAC_AT_RATES.join(", ")
    else:
      debug "audio encoder claims to support every samplerate"
      return

  let rates = cast[ptr UncheckedArray[cint]](myOut)
  for i in 0..<num:
    if rates[i] == rate:
      return

  error &"samplerate '{rate}' not allowed for {ctx.codec.name}."

proc makeMedia*(args: mainArgs, tl: v3, outputPath: string, rules: Rules, bar: Bar,
    cache: MediaCache = nil) =
  var options: Table[string, string]
  var movFlags: seq[string] = @[]
  if args.fragmented and not args.noFragmented:
    movFlags &= @["default_base_moof", "frag_keyframe", "separate_moof"]
    options["frag_duration"] = "0.2"
    if args.faststart:
      warning "Fragmented is enabled, will not apply faststart."
  elif not args.noFaststart:
    movFlags.add "faststart"
  if movFlags.len > 0:
    options["movflags"] = movFlags.join("+")

  var output = openWrite(outputPath)
  output.options = options

  let (_, _, outExt) = splitFile(outputPath)

  var vEncCtx: ptr AVCodecContext = nil
  var vOutStream: ptr AVStream = nil
  var videoFrameIter: iterator(): (ptr AVFrame, int64) = iterator(): (ptr AVFrame, int64) =
    return

  if rules.defaultVid notin [ID_NONE, ID_PNG] and tl.v.len > 0 and tl.v[0].len > 0:
    if not args.vn:
      (vEncCtx, vOutStream, videoFrameIter) = makeNewVideoFrames(output, tl, args, cache)

  var audioStreams: seq[ptr AVStream] = @[]
  var audioEncoders: seq[ptr AVCodecContext] = @[]
  var audioFrameIters: seq[iterator(): (ptr AVFrame, int64)] = @[]

  if not args.an and args.mixAudioStreams and tl.a.len > 0:
    # Create a single audio stream for mixed output
    var hasAnyClips = false
    for i in 0..<tl.a.len:
      if tl.a[i].len > 0:
        hasAnyClips = true
        break

    if hasAnyClips:
      let rate = AVRational(num: tl.sr, den: 1)
      let mixCodec = if args.audioCodec == "auto":
        block:
          var firstLayer: seq[Clip]
          for layer in tl.a:
            if layer.len > 0:
              firstLayer = layer
              break
          $avcodec_get_name(resolveAudioCodec(firstLayer, outExt, rules))
      else:
        args.audioCodec
      var (aOutStream, aEncCtx) = output.addStream(mixCodec, rate = rate,
          layout = tl.layout, metadata = {"language": "und"}.toTable)
      let encoder = aEncCtx.codec
      checkAudioCtx(aEncCtx, tl.sr)
      aEncCtx.open()

      # Update stream parameters after opening encoder for formats like AAC in MKV
      # that need codec-specific extra data (global header) to be propagated to stream
      if avcodec_parameters_from_context(aOutStream.codecpar, aEncCtx) < 0:
        error "Could not update stream parameters after opening encoder"

      if args.audioBitrate >= 0:
        aEncCtx.bit_rate = args.audioBitrate
        debug &"audio bitrate: {aEncCtx.bit_rate}"
      else:
        debug &"[auto] audio bitrate: {aEncCtx.bit_rate}"

      audioStreams.add(aOutStream)
      audioEncoders.add(aEncCtx)

      let frameSize = if aEncCtx.frame_size > 0: aEncCtx.frame_size else: 1024
      let audioFrameIter = makeMixedAudioFrames(encoder.sample_fmts[0], tl, frameSize, args.audioNormalize, cache)
      audioFrameIters.add(audioFrameIter)
  elif not args.an:
    # Create separate streams for each timeline layer
    for i in 0..<tl.a.len:
      if tl.a[i].len > 0: # Only create stream if track has clips
        let rate = AVRational(num: tl.sr, den: 1)
        let layerCodec = if args.audioCodec == "auto":
          $avcodec_get_name(resolveAudioCodec(tl.a[i], outExt, rules))
        else:
          args.audioCodec
        var (aOutStream, aEncCtx) = output.addStream(layerCodec, rate = rate,
            layout = tl.layout, metadata = {"language": $tl.langs[tl.v.len + i]}.toTable)
        let encoder = aEncCtx.codec
        checkAudioCtx(aEncCtx, tl.sr)
        aEncCtx.open()

        # Update stream parameters after opening encoder for formats like AAC in MKV
        # that need codec-specific extra data (global header) to be propagated to stream
        if avcodec_parameters_from_context(aOutStream.codecpar, aEncCtx) < 0:
          error "Could not update stream parameters after opening encoder"

        if args.audioBitrate >= 0:
          aEncCtx.bit_rate = args.audioBitrate
          debug &"audio bitrate: {aEncCtx.bit_rate}"
        else:
          debug &"[auto] audio bitrate: {aEncCtx.bit_rate}"

        audioStreams.add(aOutStream)
        audioEncoders.add(aEncCtx)

        let frameSize = if aEncCtx.frame_size > 0: aEncCtx.frame_size else: 1024
        let audioFrameIter = makeNewAudioFrames(encoder.sample_fmts[0], i.int32, tl, frameSize,
            args.audioNormalize, cache)
        audioFrameIters.add(audioFrameIter)

  defer:
    if vEncCtx != nil:
      avcodec_free_context(addr vEncCtx)
    for aEncCtx in audioEncoders:
      avcodec_free_context(addr aEncCtx)

  # Setup subtitle streams
  var subtitleStreams: seq[ptr AVStream] = @[]
  var subtitleSources: seq[string] = @[]

  if not args.sn and tl.s.len > 0:
    for i in 0..<tl.s.len:
      if tl.s[i].len > 0:
        # Get source file and stream index from first clip
        let firstClip = tl.s[i][0]
        let sourcePath = firstClip.src[]
        let streamIdx = firstClip.stream

        # Open source container to get subtitle stream info
        let srcContainer = av.open(sourcePath)
        if streamIdx >= srcContainer.subtitle.len:
          error &"Subtitle stream {streamIdx} not found in {sourcePath}"

        let srcStream = srcContainer.subtitle[streamIdx]

        # Add subtitle stream to output by copying from template
        let sOutStream = output.addStreamFromTemplate(srcStream)
        subtitleStreams.add(sOutStream)
        subtitleSources.add(sourcePath)

        srcContainer.close()

  if not args.dn:
    # Get the first source file from the timeline
    var sourcePath: string = ""
    block findSource:
      for vlayer in tl.v:
        if vlayer.len > 0:
          sourcePath = vlayer[0].src[]
          break findSource
      for alayer in tl.a:
        if alayer.len > 0:
          sourcePath = alayer[0].src[]
          break findSource

    if sourcePath != "":
      let formatCtx = av.openFormatCtx(sourcePath.cstring)
      defer: avformat_close_input(addr formatCtx)

      # Copy each attachment stream
      for i in 0 ..< formatCtx.nb_streams:
        let attachStream = formatCtx.streams[i]
        if attachStream.codecpar.codec_type != AVMEDIA_TYPE_ATTACHMENT:
          continue
        # Create attachment stream directly (attachments don't have decoders)
        let attachOutStream = avformat_new_stream(output.formatCtx, nil)
        if attachOutStream == nil:
          error "Could not allocate attachment stream"

        # Copy codec parameters directly
        if avcodec_parameters_copy(attachOutStream.codecpar, attachStream.codecpar) < 0:
          error "Could not copy attachment codec parameters"

        # Copy stream metadata
        if attachStream.metadata != nil:
          discard av_dict_copy(addr attachOutStream.metadata, attachStream.metadata, 0)

  var outPacket = av_packet_alloc()
  if outPacket == nil:
    error "Could not allocate output packet"
  defer: av_packet_free(addr outPacket)

  output.startEncoding()

  var title = &"({outExt[1 .. ^1]}) "
  var encoderTitles: seq[string] = @[]

  if vEncCtx != nil:
    let name = vEncCtx.codec.canonicalName
    encoderTitles.add (if noColor: name else: &"\e[95m{name}")
  for aEncCtx in audioEncoders:
    let name = aEncCtx.codec.canonicalName
    encoderTitles.add (if noColor: name else: &"\e[96m{name}")
  for sStream in subtitleStreams:
    let name = $sStream.name()
    if name != "":
      encoderTitles.add (if noColor: name else: &"\e[93m{name}")

  if noColor:
    title &= encoderTitles.join("+")
  else:
    title &= encoderTitles.join("\e[0m+") & "\e[0m"
  bar.start(tl.len.float64, title)

  var shouldGetAudio: seq[bool] = newSeq[bool](audioFrameIters.len)
  const MAX_AUDIO_AHEAD = 30 # In timebase, how far audio can be ahead of video.

  # Priority queue for ordered frames by time_base.
  var frameQueue = initHeapQueue[Priority]()
  var earliestVideoIndex = none(int64)
  var latestAudioIndices: seq[float64] = @[]
  for i in 0..<audioFrameIters.len:
    latestAudioIndices.add(-Inf)

  var videoFrame: ptr AVFrame
  var audioFrames: seq[ptr AVFrame] = newSeq[ptr AVFrame](audioFrameIters.len)
  var index: int64

  while true:
    if not earliestVideoIndex.isSome:
      for i in 0..<shouldGetAudio.len:
        shouldGetAudio[i] = true
    else:
      for i in 0..<shouldGetAudio.len:
        for item in frameQueue:
          if item.stream == audioStreams[i]:
            latestAudioIndices[i] = max(latestAudioIndices[i], item.index.float64)
        shouldGetAudio[i] = (latestAudioIndices[i] <= float(earliestVideoIndex.get() +
            MAX_AUDIO_AHEAD))

    if finished(videoFrameIter):
      videoFrame = nil
    else:
      (videoFrame, index) = videoFrameIter()
      if videoFrame != nil:
        earliestVideoIndex = some(index)
        frameQueue.push(initPriority(float(index), videoFrame, vOutStream))

    for i in 0..<audioFrameIters.len:
      if finished(audioFrameIters[i]):
        audioFrames[i] = nil
      elif shouldGetAudio[i]:
        (audioFrames[i], _) = audioFrameIters[i]()
        if audioFrames[i] != nil:
          let audioIndex = int(round(audioFrames[i].time(audioEncoders[i].time_base) * tl.tb))
          # Update index to the maximum of video and audio indices to ensure progress
          index = max(index, audioIndex)

    # Break if no more frames
    var hasFrames = (videoFrame != nil)
    for audioFrame in audioFrames:
      if audioFrame != nil:
        hasFrames = true
        break
    if not hasFrames:
      break

    # Add audio frames to queue
    for i in 0..<audioFrameIters.len:
      if shouldGetAudio[i] and audioFrames[i] != nil:
        let audioIndex = int(round(audioFrames[i].time(audioEncoders[i].time_base) * tl.tb))
        frameQueue.push(initPriority(float(audioIndex), audioFrames[i], audioStreams[i]))

    while frameQueue.len > 0 and frameQueue[0].index <= float64(index):
      let item = frameQueue.pop()
      let frame = item.frame
      let outputStream = item.stream
      let frameType = outputStream.codecpar.codec_type
      let encCtx = if frameType == AVMEDIA_TYPE_VIDEO:
        vEncCtx
      else:
        var aEncCtx: ptr AVCodecContext = nil
        for i, stream in audioStreams:
          if stream == outputStream:
            aEncCtx = audioEncoders[i]
            break
        aEncCtx

      for outPacket in encCtx.encode(frame, outPacket):
        outPacket.stream_index = outputStream.index
        av_packet_rescale_ts(outPacket, encCtx.time_base, outputStream.time_base)

        if frameType == AVMEDIA_TYPE_VIDEO or vOutStream == nil:
          let time = frame.time(encCtx.time_base)
          if time != -1.0:
            bar.tick(round(time * tl.tb))
        output.mux(outPacket[])
        av_packet_unref(outPacket)

        if frameType == AVMEDIA_TYPE_VIDEO:
          av_frame_unref(frame)

      if frameType == AVMEDIA_TYPE_AUDIO:
        av_frame_free(addr frame)

  bar.`end`()

  # Flush streams
  if vEncCtx != nil:
    for outPacket in vEncCtx.encode(nil, outPacket):
      outPacket.stream_index = vOutStream.index
      av_packet_rescale_ts(outPacket, vEncCtx.time_base, vOutStream.time_base)
      output.mux(outPacket[])
      av_packet_unref(outPacket)

  for i, aEncCtx in audioEncoders:
    for outPacket in aEncCtx.encode(nil, outPacket):
      outPacket.stream_index = audioStreams[i].index
      av_packet_rescale_ts(outPacket, aEncCtx.time_base, audioStreams[i].time_base)
      output.mux(outPacket[])
      av_packet_unref(outPacket)

  # Process subtitle streams
  if not args.sn and subtitleStreams.len > 0:
    for i in 0..<subtitleStreams.len:
      let layer = tl.s[i]
      let sourcePath = subtitleSources[i]
      let outputStream = subtitleStreams[i]
      remuxSubtitles(sourcePath, layer, outputStream, output, tl.tb)

  output.close()
