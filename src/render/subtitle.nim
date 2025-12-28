import ../timeline
import ../ffmpeg
import ../log
import ../av

# Simple subtitle remuxing: copy subtitle packets from source, adjusting timestamps
# Note: This approach works well for text-based subtitles (SRT, ASS, WebVTT, etc.)
# For bitmap subtitles (DVD/PGS), the timestamps are adjusted but the visual data remains unchanged
proc remuxSubtitles*(sourcePath: string, layer: seq[Clip], outputStream: ptr AVStream,
    output: var OutputContainer, timelineTb: AVRational) =
  if layer.len == 0:
    return

  # Open source container for each remux operation
  let srcContainer = av.open(sourcePath)
  defer: srcContainer.close()

  let formatCtx = srcContainer.formatContext
  let outTb = outputStream.time_base

  for clip in layer:
    if clip.stream >= srcContainer.subtitle.len:
      continue

    let streamIndex = srcContainer.subtitle[clip.stream].index
    let stream = formatCtx.streams[streamIndex]
    let srcTb = stream.time_base

    # Seek to the clip's offset position in source timebase
    # Note: timelineTb is actually the frame rate, so the actual timebase is 1/timelineTb
    let seekPts = int64(float64(clip.offset) / (float64(timelineTb) * float64(srcTb)))

    # Calculate the end position in source timebase
    let clipEndInSrcTb = int64(float64(clip.offset + clip.dur) / (float64(timelineTb) * float64(srcTb)))

    # Seek to start of clip
    if seekPts > 0:
      srcContainer.seek(seekPts, backward = true, stream = stream)

    var packet = av_packet_alloc()
    if packet == nil:
      error "Could not allocate subtitle packet"
    defer: av_packet_free(addr packet)

    # Read and copy packets for this clip
    while av_read_frame(formatCtx, packet) >= 0:
      defer: av_packet_unref(packet)

      if packet.stream_index == streamIndex:
        # Check if packet is within the clip range
        if packet.pts != AV_NOPTS_VALUE and packet.pts >= seekPts and packet.pts < clipEndInSrcTb:
          # Calculate new timestamp in output timebase
          # Step 1: Get relative position in source timebase
          let relativeStartInSrcTb = packet.pts - seekPts
          # Step 2: Convert to timeline units (frames)
          let relativeStartInFrames = int64(float64(relativeStartInSrcTb) * float64(timelineTb) * float64(srcTb))
          # Step 3: Calculate absolute position in frames
          let absoluteFramePos = clip.start + relativeStartInFrames
          # Step 4: Convert from frames to output timebase
          let newPts = int64(float64(absoluteFramePos) / (float64(timelineTb) * float64(outTb)))

          # Create output packet with adjusted timestamps
          var outPacket: AVPacket
          outPacket.time_base = outTb
          outPacket.stream_index = outputStream.index

          if av_packet_ref(addr outPacket, packet) < 0:
            error "Failed to reference subtitle packet"

          # Convert timestamps to timeline timebase
          outPacket.pts = newPts
          if packet.dts != AV_NOPTS_VALUE:
            let relativeDtsInSrcTb = packet.dts - seekPts
            let relativeDtsInFrames = int64(float64(relativeDtsInSrcTb) * float64(timelineTb) * float64(srcTb))
            let absoluteDtsFramePos = clip.start + relativeDtsInFrames
            outPacket.dts = int64(float64(absoluteDtsFramePos) / (float64(timelineTb) * float64(outTb)))
          else:
            outPacket.dts = AV_NOPTS_VALUE

          if packet.duration != AV_NOPTS_VALUE:
            outPacket.duration = int64(float64(packet.duration) * float64(timelineTb) * float64(srcTb) / (float64(timelineTb) * float64(outTb)))

          # Mux the packet
          output.mux(outPacket)
          av_packet_unref(addr outPacket)

        elif packet.pts != AV_NOPTS_VALUE and packet.pts >= clipEndInSrcTb:
          # We've passed the end of this clip
          break
