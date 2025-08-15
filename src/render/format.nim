import std/os
import std/options
import std/tables
import std/heapqueue
import std/[strformat, strutils]
from std/math import round

import ../timeline
import ../ffmpeg
import ../log
import ../av
import ../util/[bar, rules]
import video
import audio

type Priority = object
  index: float64
  frame: ptr AVFrame
  stream: ptr AVStream

proc initPriority(index: float64, frame: ptr AVFrame, stream: ptr AVStream): Priority =
  result.index = index
  result.frame = frame
  result.stream = stream

proc `<`(a, b: Priority): bool = a.index < b.index

proc makeMedia*(args: mainArgs, tl: v3, outputPath: string, rules: Rules, bar: Bar) =
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

  let (_, _, ext) = splitFile(outputPath)

  var vEncCtx: ptr AVCodecContext = nil
  var vOutStream: ptr AVStream = nil
  var videoFrameIter: iterator(): (ptr AVFrame, int) = iterator(): (ptr AVFrame, int) =
    return
  if rules.defaultVid notin ["none", "png"] and tl.v.len > 0 and tl.v[0].len > 0:
    if not args.vn:
      (vEncCtx, vOutStream, videoFrameIter) = makeNewVideoFrames(output, tl, args)

  var audioStreams: seq[ptr AVStream] = @[]
  var audioEncoders: seq[ptr AVCodecContext] = @[]
  var audioFrameIters: seq[iterator(): (ptr AVFrame, int)] = @[]

  if not args.an and args.mixAudioStreams and tl.a.len > 0:
    # Create a single audio stream for mixed output
    var hasAnyClips = false
    for i in 0..<tl.a.len:
      if tl.a[i].len > 0:
        hasAnyClips = true
        break

    if hasAnyClips:
      let rate = AVRational(num: tl.sr, den: 1)
      var (aOutStream, aEncCtx) = output.addStream(args.audioCodec, rate = rate,
          layout = tl.layout, metadata = {"language": "und"}.toTable)
      let encoder = aEncCtx.codec
      if encoder.sample_fmts == nil:
        error &"{encoder.name}: No known audio formats avail."

      aEncCtx.open()

      # Update stream parameters after opening encoder for formats like AAC in MKV
      # that need codec-specific extra data (global header) to be propagated to stream
      if avcodec_parameters_from_context(aOutStream.codecpar, aEncCtx) < 0:
        error "Could not update stream parameters after opening encoder"

      if args.audioBitrate >= 0:
        aEncCtx.bit_rate = args.audioBitrate
        debug(&"audio bitrate: {aEncCtx.bit_rate}")
      else:
        debug(&"[auto] audio bitrate: {aEncCtx.bit_rate}")

      audioStreams.add(aOutStream)
      audioEncoders.add(aEncCtx)

      let frameSize = if aEncCtx.frame_size > 0: aEncCtx.frame_size else: 1024
      let audioFrameIter = makeMixedAudioFrames(encoder.sample_fmts[0], tl, frameSize)
      audioFrameIters.add(audioFrameIter)
  elif not args.an:
    # Create separate streams for each timeline layer (existing behavior)
    for i in 0..<tl.a.len:
      if tl.a[i].len > 0: # Only create stream if track has clips
        let rate = AVRational(num: tl.sr, den: 1)
        var (aOutStream, aEncCtx) = output.addStream(args.audioCodec, rate = rate,
            layout = tl.layout, metadata = {"language": tl.a[i].lang}.toTable)
        let encoder = aEncCtx.codec
        if encoder.sample_fmts == nil:
          error &"{encoder.name}: No known audio formats avail."

        aEncCtx.open()

        # Update stream parameters after opening encoder for formats like AAC in MKV
        # that need codec-specific extra data (global header) to be propagated to stream
        if avcodec_parameters_from_context(aOutStream.codecpar, aEncCtx) < 0:
          error "Could not update stream parameters after opening encoder"

        if args.audioBitrate >= 0:
          aEncCtx.bit_rate = args.audioBitrate
          debug(&"audio bitrate: {aEncCtx.bit_rate}")
        else:
          debug(&"[auto] audio bitrate: {aEncCtx.bit_rate}")

        audioStreams.add(aOutStream)
        audioEncoders.add(aEncCtx)

        let frameSize = if aEncCtx.frame_size > 0: aEncCtx.frame_size else: 1024
        let audioFrameIter = makeNewAudioFrames(encoder.sample_fmts[0], i.int32, tl, frameSize)
        audioFrameIters.add(audioFrameIter)

  defer:
    for aEncCtx in audioEncoders:
      avcodec_free_context(addr aEncCtx)

  var outPacket = av_packet_alloc()
  if outPacket == nil:
    error "Could not allocate output packet"
  defer: av_packet_free(addr outPacket)

  output.startEncoding()

  var title = fmt"({ext[1 .. ^1]}) "
  var encoderTitles: seq[string] = @[]

  if vEncCtx != nil:
    let name = vEncCtx.codec.canonicalName
    encoderTitles.add (if noColor: name else: &"\e[95m{name}")
  for aEncCtx in audioEncoders:
    let name = aEncCtx.codec.canonicalName
    encoderTitles.add (if noColor: name else: &"\e[96m{name}")

  if noColor:
    title &= encoderTitles.join("+")
  else:
    title &= encoderTitles.join("\e[0m+") & "\e[0m"
  bar.start(tl.`end`.float, title)

  var shouldGetAudio: seq[bool] = newSeq[bool](audioFrameIters.len)
  const MAX_AUDIO_AHEAD = 30 # In timebase, how far audio can be ahead of video.

  # Priority queue for ordered frames by time_base.
  var frameQueue = initHeapQueue[Priority]()
  var earliestVideoIndex = none(int)
  var latestAudioIndices: seq[float64] = @[]
  for i in 0..<audioFrameIters.len:
    latestAudioIndices.add(-Inf)

  var videoFrame: ptr AVFrame
  var audioFrames: seq[ptr AVFrame] = newSeq[ptr AVFrame](audioFrameIters.len)
  var index: int

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

        if frameType == AVMEDIA_TYPE_AUDIO:
          av_frame_free(addr frame)
        elif frameType == AVMEDIA_TYPE_VIDEO:
          av_frame_unref(frame)

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

  output.close()
