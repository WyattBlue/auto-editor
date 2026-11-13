import std/[strformat, strutils]

import ../[av, log, ffmpeg, timeline]
import ../util/rational

# Remux subtitle packets from each clip's source onto the cut timeline,
# clipping each cue's visible window to its clip boundary. A cue that overlaps
# a cut-in point is kept (its start clamped to the cut) and one that runs past
# a cut-out is shortened, so subtitles stay in sync with the edited video
# instead of dropping or bleeding over. Works for text subs (SRT/ASS/WebVTT);
# bitmap subs (DVD/PGS) pass through with adjusted timing only.
proc remuxSubtitles*(layer: seq[Clip], outputStream: ptr AVStream,
    output: var OutputContainer, timelineTb: AVRational) =
  ## Packets can't be converted here, so a clip whose stream isn't the
  ## output's codec is left out, with a warning once per file.
  if layer.len == 0:
    return

  let outTb = outputStream.time_base
  # timelineTb is the frame rate, so one frame lasts 1/timelineTb seconds.
  let frameTb = av_inv_q(timelineTb)

  var srcContainer: InputContainer
  var openPath = ""
  defer:
    if openPath != "": srcContainer.close()
  var leftOut: seq[string]

  for clipIdx, clip in layer:
    if clip.src == nil:
      continue
    let sourcePath = clip.src[]
    if sourcePath != openPath:
      if openPath != "": srcContainer.close()
      openPath = ""
      srcContainer = (try: av.open(sourcePath) except IOError as e: error e.msg)
      openPath = sourcePath
    if clip.stream >= srcContainer.subtitle.len:
      continue

    var streamIndex = srcContainer.subtitle[clip.stream].index
    var stream = srcContainer.formatContext.streams[streamIndex]
    if stream.codecpar.codec_id != outputStream.codecpar.codec_id:
      if sourcePath notin leftOut:
        leftOut.add sourcePath
        warning &"Subtitles of {sourcePath} are " &
          $avcodec_get_name(stream.codecpar.codec_id) & ", not " &
          $avcodec_get_name(outputStream.codecpar.codec_id) & "; left out"
      continue
    var srcTb = stream.time_base

    # The clip selects source interval [clipStartSrc, clipEndSrc) in source ticks.
    let clipStartSrc = av_rescale_q(clip.offset, frameTb, srcTb) +
      srcContainer.startPts(stream)
    let clipEndSrc = av_rescale_q(clip.offset + clip.dur, frameTb, srcTb) +
      srcContainer.startPts(stream)

    # Seek backward so a cue already on screen at the cut-in is read too.
    # A later clip needs the seek even at source position 0, since the
    # previous clip's loop advanced the demuxer.
    if clipIdx > 0 or clipStartSrc > 0:
      let ret = av_seek_frame(srcContainer.formatContext, stream.index,
        clipStartSrc, AVSEEK_FLAG_BACKWARD)
      if ret < 0:
        # Text sidecars such as SRT are commonly non-seekable. Reopening puts
        # the demuxer at the beginning; scanning forward below is slower but
        # preserves cues that overlap the clip boundary.
        srcContainer.close()
        openPath = ""
        srcContainer = (try: av.open(sourcePath) except IOError as e: error e.msg)
        openPath = sourcePath
        if clip.stream >= srcContainer.subtitle.len:
          continue
        streamIndex = srcContainer.subtitle[clip.stream].index
        stream = srcContainer.formatContext.streams[streamIndex]
        srcTb = stream.time_base

    var packet = av_packet_alloc()
    if packet == nil:
      error "Could not allocate subtitle packet"
    defer: av_packet_free(addr packet)

    while av_read_frame(srcContainer.formatContext, packet) >= 0:
      defer: av_packet_unref(packet)

      if packet.stream_index != streamIndex or packet.pts == AV_NOPTS_VALUE:
        continue

      let cueStart = packet.pts
      let hasDur = packet.duration > 0
      let cueEnd = (if hasDur: cueStart + packet.duration else: cueStart)

      # Packets arrive in pts order, so once a cue starts at/after the window, done.
      if cueStart >= clipEndSrc:
        break

      # Keep any cue overlapping the window. With unknown duration we can't tell if
      # an earlier-starting cue still overlaps, so fall back to start-inside.
      let overlaps = (if hasDur: cueEnd > clipStartSrc else: cueStart >= clipStartSrc)
      if not overlaps:
        continue

      # Intersect cue with the window, then map source -> timeline frames -> output.
      let visStart = max(cueStart, clipStartSrc)
      let startFrame = clip.start +
        av_rescale_q(visStart - clipStartSrc, srcTb, frameTb)
      let newPts = av_rescale_q(startFrame, frameTb, outTb)

      var outPacket: AVPacket
      if av_packet_ref(addr outPacket, packet) < 0:
        error "Failed to reference subtitle packet"
      outPacket.stream_index = outputStream.index
      outPacket.time_base = outTb
      outPacket.pts = newPts
      outPacket.dts = newPts # subtitle streams have no reordering; keep dts == pts
      if hasDur:
        let visEnd = min(cueEnd, clipEndSrc)
        let endFrame = clip.start + av_rescale_q(visEnd - clipStartSrc, srcTb, frameTb)
        outPacket.duration = max(1'i64, av_rescale_q(endFrame, frameTb, outTb) - newPts)

      output.mux(outPacket)
      av_packet_unref(addr outPacket)

proc writeCaptions*(track: CaptionTrack, ctx: ptr AVCodecContext,
    outputStream: ptr AVStream, output: var OutputContainer, timelineTb: AVRational) =
  ## Encode `track`'s cues as `outputStream`'s packets through `ctx`, an
  ## encoder from `addCaptionStream`.
  let frameTb = av_inv_q(timelineTb)
  var buf = newSeq[uint8](1 shl 16)
  for cue in track.cues:
    let pts = av_rescale_q(cue.start, frameTb, ctx.time_base)
    let dur = max(1'i64,
      av_rescale_q(cue.start + cue.dur, frameTb, ctx.time_base) - pts)

    # A dialogue line without its timing, which the packet carries.
    let line = "0,0,Default,,0,0,0,," &
      cue.text.replace("\r\n", "\n").replace("\n", "\\N")
    var rect: AVSubtitleRect
    rect.`type` = SUBTITLE_ASS
    rect.ass = line.cstring
    var rectPtr = addr rect
    var sub: AVSubtitle
    sub.format = 1 # text
    sub.end_display_time = uint32(dur) # ctx.time_base is milliseconds
    sub.num_rects = 1
    sub.rects = cast[ptr UncheckedArray[ptr AVSubtitleRect]](addr rectPtr)
    sub.pts = av_rescale_q(cue.start, frameTb, AVRational(num: 1, den: AV_TIME_BASE))

    let size = avcodec_encode_subtitle(ctx, addr buf[0], buf.len.cint, addr sub)
    if size < 0:
      error "Could not encode caption: " & av_err2str(size)
    if size == 0:
      continue

    var packet: AVPacket
    if av_new_packet(addr packet, size) < 0:
      error "Could not allocate caption packet"
    copyMem(packet.data, addr buf[0], size)
    packet.stream_index = outputStream.index
    packet.time_base = ctx.time_base
    packet.pts = pts
    packet.dts = pts
    packet.duration = dur
    output.mux(packet)
    av_packet_unref(addr packet)

proc makeAlteredSubtitle*(sourcePath, outputPath: string, layer: seq[Clip],
    timelineTb: AVRational) =
  ## Write every subtitle stream in a sidecar file, retimed to `layer`.
  let source = (try: av.open(sourcePath) except IOError as e: error e.msg)
  defer: source.close()

  var output = openWrite(outputPath)
  var outputStreams: seq[ptr AVStream]
  for sourceStream in source.subtitle:
    outputStreams.add output.addStreamFromTemplate(sourceStream)
  # The muxer may finalize stream time bases while writing its header.
  output.startEncoding()

  # The clips follow the media's cuts, but read the sidecar's streams.
  var sidecar = sourcePath
  for i, outputStream in outputStreams:
    var subtitleLayer = layer
    for clip in subtitleLayer.mitems:
      clip.src = addr sidecar
      clip.stream = i.int16
    remuxSubtitles(subtitleLayer, outputStream, output, timelineTb)

  output.close()
