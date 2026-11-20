import std/[algorithm, heapqueue, options, sequtils, sets, strformat, strutils]
from std/math import round

import ../[action, av, ffmpeg, license, log, media, timeline, throttle]
import ../util/[bar, rules, rational]
import ./[asyncenc, video, audio, subtitle, partialplan]

type Priority = object
  index: float64
  frame: ptr AVFrame
  packet: ptr AVPacket
  stream: ptr AVStream

func `<`(a, b: Priority): bool = a.index < b.index

func pngDimensions(data: ptr uint8, size: cint): (cint, cint) =
  const sig = [0x89'u8, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
  if size < 24:
    return (0, 0)
  let b = cast[ptr UncheckedArray[uint8]](data)
  for i in 0..7:
    if b[i] != sig[i]:
      return (0, 0)
  # IHDR: sig(8) + chunk_len(4) + "IHDR"(4) + width(4) + height(4)
  let w = (b[16].cint shl 24) or (b[17].cint shl 16) or
          (b[18].cint shl 8) or b[19].cint
  let h = (b[20].cint shl 24) or (b[21].cint shl 16) or
          (b[22].cint shl 8) or b[23].cint
  return (w, h)

proc resolveAudioCodec(layer: seq[Clip], rules: Rules, cache: MediaCache): AVCodecID =
  if layer.len == 0:
    return rules.defaultAud
  # PCM-first containers (WAV, AIFF, AU, W64, CAF, ...) prefer PCM over the
  # source codec.
  if rules.defaultAud.isPCM:
    return rules.defaultAud

  let firstClip = layer[0]
  if firstClip.src == nil:
    return rules.defaultAud
  let stream = int(firstClip.stream)

  var codec: AVCodecID
  if cache != nil:
    let container = cache.getContainer(firstClip.src)
    if stream >= container.audio.len:
      return rules.defaultAud
    codec = container.audio[stream].codecpar.codec_id
  else:
    let srcMi = initMediaInfo(firstClip.src[])
    if stream >= srcMi.a.len:
      return rules.defaultAud
    codec = srcMi.a[stream].codecId

  if rules.allowsCodec(codec):
    return codec
  return (if rules.defaultAud == ID_NONE: ID_AAC else: rules.defaultAud)

func opusRate(rate: cint): cint =
  for r in [8000.cint, 12000, 16000, 24000, 48000]:
    if rate <= r:
      return r
  return 48000

proc checkAudioCtx(ctx: ptr AVCodecContext, rate: cint) =
  let sampleFmts = ctx.codec.supportedSampleFmts
  if sampleFmts == nil:
    error &"{ctx.codec.name}: No known audio formats avail."

  var configPtr: pointer = nil
  var num: cint = 0
  discard avcodec_get_supported_config(
    ctx, nil, AV_CODEC_CONFIG_SAMPLE_RATE, 0.cuint, addr configPtr, addr num
  )

  const AAC_RATES = [48000.cint, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000]

  if configPtr == nil:
    debug "Audio encoder does not have a config"
    if ctx.codec.id == ID_AAC and rate notin AAC_RATES:
      error "AAC encoder only supports these samplerates: " & AAC_RATES.join(", ")
    return

  let rates = cast[ptr UncheckedArray[cint]](configPtr)
  for i in 0..<num:
    if rates[i] == rate:
      return

  error &"samplerate '{rate}' not allowed for {ctx.codec.name}."

proc makePartialLosslessVideo(output: var OutputContainer, tl: v3, args: mainArgs,
    video: VideoSettings):
    tuple[stream: ptr AVStream, packets: iterator(): (ptr AVPacket, int64)] =
  let encoder = initCodec(video.codec)
  if encoder == nil:
    return

  let plan = output.partialLosslessPlan(tl, args, video, encoder.id)
  if plan.len == 0:
    return

  (result.stream, result.packets) =
    makePartialLossless(output, tl, video, plan, encoder.id)

proc dropUndecodableAudio*(tl: var v3, cache: MediaCache) =
  ## A timeline can name an audio stream this build has no decoder for: the
  ## `apac` track in an iPhone Spatial Audio recording, say. The CLI drops those
  ## layers as it builds a timeline, but a v3 written elsewhere (the app builds
  ## its own) arrives with them intact, so drop the clips here too rather than
  ## failing the whole render. The layer is emptied, never removed, so the seqs
  ## indexed alongside it -- `langs`, `at` -- stay aligned.
  var reported: HashSet[(ptr string, int16)]
  for layer in tl.a.mitems:
    var kept = newSeqOfCap[Clip](layer.len)
    for clip in layer:
      if clip.src == nil:
        kept.add clip
        continue
      let container = cache.getContainer(clip.src)
      if clip.stream.int >= container.audio.len:
        kept.add clip
        continue
      let codecId = container.audio[clip.stream.int].codecpar.codec_id
      if canDecode(codecId):
        kept.add clip
      elif not reported.containsOrIncl((clip.src, clip.stream)):
        warning &"Skipping audio stream {clip.stream}: no decoder for " &
          $avcodec_get_name(codecId)
    layer = kept

proc makeMedia*(args: mainArgs, inputVideo: VideoSettings, audio: AudioSettings,
    tl: var v3, outputPath: string, rules: Rules, bar: Bar, cache: MediaCache) =
  var video = inputVideo
  # Before bakeTransitions: output streams are created from `tl` and their
  # frames come from the baked copy, so both must see the same audio layers.
  tl.dropUndecodableAudio(cache)
  let sourceEffectCount = tl.effects.len
  var renderTl = tl.bakeTransitions()
  defer:
    for i in sourceEffectCount ..< renderTl.effects.len:
      renderTl.effects[i].free()
  var throttle = initThrottle()
  let includeVideo = not args.vn and rules.defaultVid notin [ID_NONE, ID_PNG]
  let includeAudio = not args.an and rules.defaultAud != ID_NONE
  let includeSubtitle = not args.sn and rules.defaultSub != ID_NONE
  let renderVideo = includeVideo and renderTl.v.len > 0 and renderTl.v[0].len > 0
  if renderVideo:
    template limitTo(limit: SizeLimit, what, source: string) =
      let (width, height) = scaledVideoResolution(renderTl.res, video.scale)
      if not fits(width, height, limit):
        # Without a key, shrink to fit, unless the size was asked for exactly.
        if licenseKeyProvided(args) or (video.scaleSet and args.resolutionSet):
          requireLicense(args, "render " & what & " above " & $limit, source)
        else:
          video.scale = min(video.scale,
            fitScale(renderTl.res[0], renderTl.res[1], limit))
          let (w, h) = scaledVideoResolution(renderTl.res, video.scale)
          warning "Rendering " & what & " without a license is limited to " &
            $limit & "; using --scale " & formatFloat(video.scale, ffDefault, 4) &
            " (" & $w & "x" & $h & ")."

    if renderTl.numberOfSrc > 1:
      limitTo(FREE_MULTI_SOURCE, "video with multiple sources", "cli-multi-src")
    limitTo(FREE_RENDER, "video", "cli-res")

  var options: OutputOptions
  if args.fragmented and not args.noFragmented:
    options.add("frag_duration", "0.2")
    options.add("movflags", "empty_moov+default_base_moof+frag_keyframe+separate_moof")
    if args.faststart:
      warning "Fragmented is enabled, will not apply faststart."
  elif not args.noFaststart:
    options.add("movflags", "faststart")

  var output = openWrite(outputPath)
  output.options = options
  output.streaming = args.fragmented and not args.noFragmented

  var audCodec = ""
  if includeAudio:
    if audio.codec == "auto":
      for layer in tl.a:
        if layer.len > 0:
          audCodec = $avcodec_get_name(resolveAudioCodec(layer, rules, cache))
          break
      when defined(macosx):
        if audCodec == "aac" and avcodec_find_encoder_by_name("aac_at") != nil:
          audCodec = "aac_at"
    else:
      audCodec = audio.codec

    if audCodec in ["opus", "libopus"]:
      let snapped = opusRate(tl.sr)
      if snapped != tl.sr:
        debug &"opus: snapping sample rate {tl.sr} -> {snapped}"
        tl.sr = snapped
        renderTl.sr = snapped

  var vEncCtx: ptr AVCodecContext = nil
  var vOutStream: ptr AVStream = nil
  var videoFrameIter: iterator(): (ptr AVFrame, int64) =
    iterator(): (ptr AVFrame, int64) =
      return
  var videoPacketIter: iterator(): (ptr AVPacket, int64) =
    iterator(): (ptr AVPacket, int64) =
      return
  var partialLosslessVideo = false

  if renderVideo:
    (vOutStream, videoPacketIter) =
      output.makePartialLosslessVideo(renderTl, args, video)
    partialLosslessVideo = vOutStream != nil
    if not partialLosslessVideo:
      (vEncCtx, vOutStream, videoFrameIter) =
        makeNewVideoFrames(output, renderTl, args, video, cache)

  var audioStreams: seq[ptr AVStream] = @[]
  var audioEncoders: seq[ptr AVCodecContext] = @[]
  var audioFrameIters: seq[iterator(): (ptr AVFrame, int64)] = @[]

  if includeAudio and args.mixAudioStreams and tl.a.len > 0:
    # Create a single audio stream for mixed output
    var hasAnyClips = false
    for i in 0..<tl.a.len:
      if tl.a[i].len > 0:
        hasAnyClips = true
        break

    if hasAnyClips:
      let rate = AVRational(num: tl.sr, den: 1)
      var (aOutStream, aEncCtx) = output.addStream(audCodec, rate = rate,
          lang = ['u', 'n', 'd', '\0'], layout = tl.layout)
      checkAudioCtx(aEncCtx, tl.sr)
      # avcodec_open2 configures the encoder from bit_rate; set after and it's ignored.
      if audio.bitrate >= 0:
        aEncCtx.bit_rate = audio.bitrate
      resolveEncoderContext(aEncCtx)
      let encoder = aEncCtx.codec
      aEncCtx.open()

      # Update stream parameters after opening encoder for formats like AAC in MKV
      # that need codec-specific extra data (global header) to be propagated to stream
      if avcodec_parameters_from_context(aOutStream.codecpar, aEncCtx) < 0:
        error "Could not update stream parameters after opening encoder"

      if audio.bitrate >= 0:
        debug &"audio bitrate: {aEncCtx.bit_rate}"
      else:
        debug &"[auto] audio bitrate: {aEncCtx.bit_rate}"

      audioStreams.add(aOutStream)
      audioEncoders.add(aEncCtx)

      let frameSize = if aEncCtx.frame_size > 0: aEncCtx.frame_size else: 1024
      let audioFrameIter = makeAudioFrames(encoder.supportedSampleFmts[0], renderTl,
          frameSize, toSeq(0 ..< tl.a.len), audio.normalize, cache)
      audioFrameIters.add(audioFrameIter)
  elif includeAudio:
    # Create separate streams for each timeline layer
    for i in 0..<tl.a.len:
      if tl.a[i].len > 0: # Only create stream if track has clips
        let rate = AVRational(num: tl.sr, den: 1)
        var (aOutStream, aEncCtx) = output.addStream(audCodec, rate = rate,
            lang = tl.langs[tl.v.len + i], layout = tl.layout)
        checkAudioCtx(aEncCtx, tl.sr)
        # avcodec_open2 configures the encoder from bit_rate; setting it after
        # the call has no effect.
        if audio.bitrate >= 0:
          aEncCtx.bit_rate = audio.bitrate
        resolveEncoderContext(aEncCtx)
        let encoder = aEncCtx.codec
        aEncCtx.open()

        # Update stream parameters after opening encoder for formats like AAC in MKV
        # that need codec-specific extra data (global header) to be propagated to stream
        if avcodec_parameters_from_context(aOutStream.codecpar, aEncCtx) < 0:
          error "Could not update stream parameters after opening encoder"

        if audio.bitrate >= 0:
          debug &"audio bitrate: {aEncCtx.bit_rate}"
        else:
          debug &"[auto] audio bitrate: {aEncCtx.bit_rate}"

        audioStreams.add(aOutStream)
        audioEncoders.add(aEncCtx)

        let frameSize = if aEncCtx.frame_size > 0: aEncCtx.frame_size else: 1024
        let audioFrameIter = makeAudioFrames(encoder.supportedSampleFmts[0], renderTl,
            frameSize, @[i], audio.normalize, cache)
        audioFrameIters.add(audioFrameIter)

  defer:
    if vEncCtx != nil:
      avcodec_free_context(addr vEncCtx)
    for aEncCtx in audioEncoders:
      avcodec_free_context(addr aEncCtx)

  # Setup subtitle streams
  var subtitleStreams: seq[ptr AVStream] = @[]

  if includeSubtitle and tl.s.len > 0:
    for i in 0..<tl.s.len:
      if tl.s[i].len > 0:
        let firstClip = tl.s[i][0]
        let sourcePath = firstClip.src[]
        let streamIdx = firstClip.stream

        var srcContainer: InputContainer
        var ownsContainer = false
        if cache != nil:
          srcContainer = cache.getContainer(firstClip.src)
        else:
          srcContainer = (
            try: av.open(sourcePath)
            except IOError as e: error e.msg
          )
          ownsContainer = true
        if streamIdx >= srcContainer.subtitle.len:
          error &"Subtitle stream {streamIdx} not found in {sourcePath}"

        let srcStream = srcContainer.subtitle[streamIdx]

        # The layer's first clip is the template; later clips may come from
        # other files, which the remuxer opens as it reaches them.
        let sOutStream = output.addStreamFromTemplate(srcStream)
        subtitleStreams.add(sOutStream)

        if ownsContainer:
          srcContainer.close()

  # Inline captions become a text subtitle stream each.
  var captionStreams: seq[(int, ptr AVStream, ptr AVCodecContext)]
  if includeSubtitle:
    for i, track in tl.c:
      if track.cues.len > 0:
        let (stream, ctx) = output.addCaptionStream(rules.defaultSub, track.lang)
        captionStreams.add (i, stream, ctx)

  var imageStreams: seq[(ptr AVStream, ptr AVPacket)] = @[]
  var imageSourceCtx: ptr AVFormatContext = nil
  var ownsImageSourceCtx = false
  defer:
    if ownsImageSourceCtx and imageSourceCtx != nil:
      avformat_close_input(addr imageSourceCtx)

  var outPacket = av_packet_alloc()
  if outPacket == nil:
    error "Could not allocate output packet"
  defer: av_packet_free(addr outPacket)

  # Attachments (fonts, cover art) are copied from the template file.
  if not args.dn and tl.templateFile != nil:
    if cache != nil:
      imageSourceCtx = cache.getContainer(tl.templateFile).formatContext
    else:
      imageSourceCtx = av.openFormatCtx(tl.templateFile[].cstring)
      ownsImageSourceCtx = true

    for i in 0 ..< imageSourceCtx.nb_streams:
      let strm = imageSourceCtx.streams[i]
      if strm.codecpar.codec_type == AVMEDIA_TYPE_ATTACHMENT:
        let outStrm = avformat_new_stream(output.formatCtx, nil)
        if outStrm == nil:
          error "Could not allocate attachment stream"
        if avcodec_parameters_copy(outStrm.codecpar, strm.codecpar) < 0:
          error "Could not copy attachment codec parameters"
        if strm.metadata != nil:
          discard av_dict_copy(addr outStrm.metadata, strm.metadata, 0)
      elif strm.codecpar.codec_type == AVMEDIA_TYPE_VIDEO and
          (strm.disposition and AV_DISPOSITION_ATTACHED_PIC) != 0:
        let supported = avformat_query_codec(output.formatCtx.oformat,
          strm.codecpar.codec_id, FF_COMPLIANCE_EXPERIMENTAL)
        if supported == 0 or (supported < 0 and output.formatCtx.oformat.name != "flac"):
          continue
        let outStrm = avformat_new_stream(output.formatCtx, nil)
        if outStrm == nil:
          error "Could not allocate image stream"
        if avcodec_parameters_copy(outStrm.codecpar, strm.codecpar) < 0:
          error "Could not copy image codec parameters"
        if outStrm.codecpar.width == 0 or outStrm.codecpar.height == 0:
          if strm.codecpar.codec_id == ID_PNG:
            let (w, h) = pngDimensions(strm.attached_pic.data, strm.attached_pic.size)
            if w > 0 and h > 0:
              outStrm.codecpar.width = w
              outStrm.codecpar.height = h
        outStrm.time_base = strm.time_base
        outStrm.disposition = strm.disposition
        if strm.metadata != nil:
          discard av_dict_copy(addr outStrm.metadata, strm.metadata, 0)
        imageStreams.add((outStrm, addr strm.attached_pic))

  if args.chapters:
    # A named marker starts a chapter that runs for its span or, being a
    # point, up to the next chapter: players expect chapters end to end.
    var named = tl.markers.filterIt(it.name != "")
    named.sort(proc (a, b: Marker): int = cmp(a.start, b.start))
    for i, m in named:
      let stop =
        if m.dur > 0: m.start + m.dur
        elif i + 1 < named.len: named[i + 1].start
        else: tl.len
      output.addChapter(m.start, max(m.start, stop), av_inv_q(tl.tb), m.name)

  output.startEncoding()

  var title = &"({output.formatCtx.oformat.name}) "
  var encoderTitles: seq[string] = @[]

  if vOutStream != nil:
    let name = if vEncCtx != nil: vEncCtx.codec.canonicalName else: vOutStream.name()
    if name != "":
      encoderTitles.add (if noColor: name else: &"\e[95m{name}")
  for aEncCtx in audioEncoders:
    let name = aEncCtx.codec.canonicalName
    encoderTitles.add (if noColor: name else: &"\e[96m{name}")
  for sStream in subtitleStreams:
    let name = $sStream.name()
    if name != "":
      encoderTitles.add (if noColor: name else: &"\e[93m{name}")
  for (_, _, ctx) in captionStreams:
    let name = ctx.codec.canonicalName
    encoderTitles.add (if noColor: name else: &"\e[93m{name}")

  if noColor:
    title &= encoderTitles.join("+")
  else:
    title &= encoderTitles.join("\e[0m+") & "\e[0m"
  bar.start(tl.len.float64, title)

  # Priority queue for ordered frames by time_base.
  var frameQueue = initHeapQueue[Priority]()
  defer: # packets an error left waiting; the loop empties it otherwise
    while frameQueue.len > 0:
      var item = frameQueue.pop()
      if item.packet != nil:
        av_packet_free(addr item.packet)

  # Each audio stream encodes on a thread of its own, beside the video and the
  # other streams, fed ahead of the video so it has work while the video does.
  # Its packets wait in `frameQueue` for their turn, as frames do, so the muxer
  # gets everything in the same order. PCM is only a copy, not worth a thread.
  # The web build encodes inline: its threads come from a fixed pool.
  var asyncAudio = newSeq[AsyncEncoder](audioEncoders.len)
  var audioDone = newSeq[bool](audioEncoders.len) # every frame was sent
  var audioSent = newSeq[int64](audioEncoders.len) # the last one's index
  let asyncAhead = int64(round(60.0 * tl.tb.float64)) # one minute
  when not defined(emscripten):
    defer: # before the encoders are freed
      for e in asyncAudio: e.close()
    for i, aEncCtx in audioEncoders:
      if not ($aEncCtx.codec.name).startsWith("pcm_"):
        asyncAudio[i] = newAsyncEncoder(aEncCtx, depth = 64)

  template queueAudioPacket(i: int, pkt: ptr AVPacket) =
    let encCtx = audioEncoders[i]
    pkt.stream_index = audioStreams[i].index
    pkt.time_base = encCtx.time_base
    # Unrounded: the heap doesn't keep equal indices in order, and a stream's
    # packets must reach the muxer in theirs.
    let at = (if pkt.pts != AV_NOPTS_VALUE: pkt.pts else: pkt.dts)
    frameQueue.push(Priority(index: float(at) * float(encCtx.time_base) *
      float(tl.tb), packet: pkt, stream: audioStreams[i]))

  var shouldGetAudio: seq[bool] = newSeq[bool](audioFrameIters.len)
  const MAX_AUDIO_AHEAD = 30 # In timebase, how far audio can be ahead of video.

  var earliestVideoIndex = none(int64)
  var latestAudioIndices: seq[float64] = @[]
  for i in 0..<audioFrameIters.len:
    latestAudioIndices.add(-Inf)

  var videoFrame: ptr AVFrame
  var videoPacket: ptr AVPacket
  var audioFrames: seq[ptr AVFrame] = newSeq[ptr AVFrame](audioFrameIters.len)
  var index: int64

  while true:
    if not earliestVideoIndex.isSome:
      for i in 0..<shouldGetAudio.len:
        shouldGetAudio[i] = true
    else:
      for i in 0..<shouldGetAudio.len:
        if asyncAudio[i] != nil:
          continue # paced by its own feed
        for item in frameQueue:
          if item.stream == audioStreams[i]:
            latestAudioIndices[i] = max(latestAudioIndices[i], item.index.float64)
        shouldGetAudio[i] = (latestAudioIndices[i] <= float(earliestVideoIndex.get() +
            MAX_AUDIO_AHEAD))

    if partialLosslessVideo:
      videoFrame = nil
      if finished(videoPacketIter):
        videoPacket = nil
      else:
        (videoPacket, index) = videoPacketIter()
        if videoPacket != nil:
          earliestVideoIndex = some(index)
          frameQueue.push(Priority(index: float(index), packet: videoPacket,
            stream: vOutStream))
    else:
      videoPacket = nil
      if finished(videoFrameIter):
        videoFrame = nil
      else:
        (videoFrame, index) = videoFrameIter()
        if videoFrame != nil:
          earliestVideoIndex = some(index)
          frameQueue.push(Priority(index: float(index), frame: videoFrame,
            stream: vOutStream))

    for i in 0..<audioFrameIters.len:
      if asyncAudio[i] != nil:
        audioFrames[i] = nil
        let e = asyncAudio[i]
        let videoDone = videoFrame == nil and videoPacket == nil
        let videoAt = earliestVideoIndex.get(0)
        let limit = videoAt + asyncAhead
        # Never wait on it while the video has work, unless the video is ahead:
        # the muxer holds all of the video that the audio hasn't reached. After,
        # one frame a pass, to collect packets in between.
        while not audioDone[i] and (videoDone or audioSent[i] < videoAt or
            (e.hasRoom and audioSent[i] <= limit)):
          let (f, _) = (if finished(audioFrameIters[i]): (nil, 0'i64)
                        else: audioFrameIters[i]())
          if f == nil:
            audioDone[i] = true
            break
          audioSent[i] = int64(round(f.time(audioEncoders[i].time_base) * tl.tb))
          e.send(f) # it frees the frame
          if videoDone:
            index = max(index, audioSent[i])
            break
        for pkt in e.ready():
          queueAudioPacket(i, pkt)
      elif finished(audioFrameIters[i]):
        audioFrames[i] = nil
      elif shouldGetAudio[i]:
        (audioFrames[i], _) = audioFrameIters[i]()
        if audioFrames[i] != nil:
          let audioIndex = int(round(
            audioFrames[i].time(audioEncoders[i].time_base) * tl.tb))
          # Update index to the maximum of video and audio indices to ensure progress
          index = max(index, audioIndex)

    # Break if no more frames
    var hasFrames = videoFrame != nil or videoPacket != nil
    for audioFrame in audioFrames:
      if audioFrame != nil:
        hasFrames = true
        break
    for i, e in asyncAudio:
      if e != nil and not audioDone[i]:
        hasFrames = true
    if not hasFrames:
      # The threaded encoders' last packets, then everything still queued.
      var flushing = false
      for i, e in asyncAudio:
        if e != nil and not e.flushed:
          for pkt in e.flush():
            queueAudioPacket(i, pkt)
          flushing = true
      if not flushing:
        break
      index = int64.high

    # Add audio frames to queue
    for i in 0..<audioFrameIters.len:
      if shouldGetAudio[i] and audioFrames[i] != nil:
        let audioIndex = int(round(
          audioFrames[i].time(audioEncoders[i].time_base) * tl.tb))
        frameQueue.push(Priority(index: float(audioIndex), frame: audioFrames[i],
            stream: audioStreams[i]))

    while frameQueue.len > 0 and frameQueue[0].index <= float64(index):
      let item = frameQueue.pop()
      let frame = item.frame
      let outputStream = item.stream
      if item.packet != nil:
        let packet = item.packet
        if packet.pts != AV_NOPTS_VALUE and
            (outputStream == vOutStream or vOutStream == nil):
          let time = float(packet.pts) * float(packet.time_base)
          bar.tick(round(time * tl.tb))
          throttle.checkpoint(time)
        output.mux(packet[])
        var ownedPacket = packet
        av_packet_free(addr ownedPacket)
        continue
      let frameType = outputStream.codecpar.codec_type
      let encCtx =
        if frameType == AVMEDIA_TYPE_VIDEO:
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
            throttle.checkpoint(time)
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
    if asyncAudio[i] != nil:
      continue # flushed above
    for outPacket in aEncCtx.encode(nil, outPacket):
      outPacket.stream_index = audioStreams[i].index
      av_packet_rescale_ts(outPacket, aEncCtx.time_base, audioStreams[i].time_base)
      output.mux(outPacket[])
      av_packet_unref(outPacket)

  # Copy embedded images
  for (outStream, cachedPkt) in imageStreams:
    if cachedPkt != nil and av_packet_ref(outPacket, cachedPkt) >= 0:
      outPacket.stream_index = outStream.index
      if av_interleaved_write_frame(output.formatCtx, outPacket) < 0:
        error "Could not write embedded image packet"
      av_packet_unref(outPacket)

  # Process subtitle streams
  if includeSubtitle:
    for i in 0..<subtitleStreams.len:
      remuxSubtitles(tl.s[i], tl.effects, subtitleStreams[i], output, tl.tb)
    for (i, stream, ctx) in captionStreams:
      writeCaptions(tl.c[i], ctx, stream, output, tl.tb)
  for (_, _, ctx) in captionStreams:
    var encoder = ctx
    avcodec_free_context(addr encoder)

  output.close()
