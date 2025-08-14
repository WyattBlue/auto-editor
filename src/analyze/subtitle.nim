from std/math import round

import ../[av, ffmpeg]
import tinyre

proc subtitle*(container: InputContainer, tb: AVRational, pattern: Re,
    stream: int32): seq[bool] =
  let
    formatCtx = container.formatContext
    s = container.subtitle[stream].index
    codecCtx = initDecoder(formatCtx.streams[s].codecpar)
    packet = av_packet_alloc()

  if packet == nil:
    quit(1)
  defer: av_packet_free(addr packet)

  let subtitleStream: AVStream = container.subtitle[stream][]

  var length = 0
  var spans: seq[(int, int)] = @[]
  var subtitle: AVSubtitle
  while av_read_frame(formatCtx, packet) >= 0:
    defer: av_packet_unref(packet)

    if packet.stream_index == s:
      if packet.pts == AV_NOPTS_VALUE or packet.duration == AV_NOPTS_VALUE:
        continue

      let
        startFloat = float(packet.pts * subtitleStream.time_base)
        durFloat = float(packet.duration * subtitleStream.time_base)
        start = round(startFloat * tb).int
        `end` = round((startFloat + durFloat) * tb).int

      var gotSubtitle: cint = 0
      let ret = avcodec_decode_subtitle2(codecCtx, addr subtitle,
        addr gotSubtitle, packet)

      if ret >= 0 and gotSubtitle != 0:
        defer: avsubtitle_free(addr subtitle)

        length = max(length, `end`)
        for i in 0..<subtitle.num_rects:
          let rect = subtitle.rects[i]
          if rect.`type` == SUBTITLE_ASS and rect.ass != nil:
            var assText: string = $rect.ass
            if match(assText.dialogue, pattern).len > 0:
              spans.add((start, `end`))

  result = newSeq[bool](length)
  for span in spans:
    for i in span[0] ..< span[1]:
      result[i] = true
