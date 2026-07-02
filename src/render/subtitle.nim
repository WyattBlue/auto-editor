import ../[av, log, ffmpeg, timeline]
import ../util/rational

# Remux subtitle packets from source onto the cut timeline, clipping each cue's
# visible window to its clip boundary. A cue that overlaps a cut-in point is kept
# (its start clamped to the cut) and one that runs past a cut-out is shortened, so
# subtitles stay in sync with the edited video instead of dropping or bleeding over.
# Works for text subs (SRT/ASS/WebVTT); bitmap subs (DVD/PGS) pass through with
# adjusted timing only.
proc remuxSubtitles*(sourcePath: string, layer: seq[Clip], outputStream: ptr AVStream,
    output: var OutputContainer, timelineTb: AVRational) =
  if layer.len == 0:
    return

  # Open source container for each remux operation
  let srcContainer = (
    try: av.open(sourcePath)
    except IOError as e: error e.msg
  )
  defer: srcContainer.close()

  let formatCtx = srcContainer.formatContext
  let outTb = outputStream.time_base
  # timelineTb is the frame rate, so one frame lasts 1/timelineTb seconds.
  let frameTb = av_inv_q(timelineTb)

  for clip in layer:
    if clip.stream >= srcContainer.subtitle.len:
      continue

    let streamIndex = srcContainer.subtitle[clip.stream].index
    let stream = formatCtx.streams[streamIndex]
    let srcTb = stream.time_base

    # The clip selects source interval [clipStartSrc, clipEndSrc) in source ticks.
    let clipStartSrc = av_rescale_q(clip.offset, frameTb, srcTb)
    let clipEndSrc = av_rescale_q(clip.offset + clip.dur, frameTb, srcTb)

    # Seek backward so a cue already on screen at the cut-in is read too.
    if clipStartSrc > 0:
      srcContainer.seek(clipStartSrc, backward = true, stream = stream)

    var packet = av_packet_alloc()
    if packet == nil:
      error "Could not allocate subtitle packet"
    defer: av_packet_free(addr packet)

    while av_read_frame(formatCtx, packet) >= 0:
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
      let startFrame = clip.start + av_rescale_q(visStart - clipStartSrc, srcTb, frameTb)
      let newPts = av_rescale_q(startFrame, frameTb, outTb)

      var outPacket: AVPacket
      if av_packet_ref(addr outPacket, packet) < 0:
        error "Failed to reference subtitle packet"
      outPacket.stream_index = outputStream.index
      outPacket.time_base = outTb
      outPacket.pts = newPts
      outPacket.dts = newPts  # subtitle streams have no reordering; keep dts == pts
      if hasDur:
        let visEnd = min(cueEnd, clipEndSrc)
        let endFrame = clip.start + av_rescale_q(visEnd - clipStartSrc, srcTb, frameTb)
        outPacket.duration = max(1'i64, av_rescale_q(endFrame, frameTb, outTb) - newPts)

      output.mux(outPacket)
      av_packet_unref(addr outPacket)
