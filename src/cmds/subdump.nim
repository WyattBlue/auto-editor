import ../ffmpeg
import ../av
import ../log


proc main*(args: seq[string]) =
  if args.len < 1:
    echo "Dump text-based subtitles to stdout with formatting stripped out"
    quit(0)

  av_log_set_level(AV_LOG_QUIET)

  let packet = av_packet_alloc()
  if packet == nil:
    quit(1)
  defer: av_packet_free(addr packet)

  var container: InputContainer
  for inputFile in args:
    try:
      container = av.open(inputFile)
    except IOError as e:
      error(e.msg)
    defer: container.close()
    let formatCtx = container.formatContext

    var subStreams: seq[cint] = @[]
    for s in container.subtitle:
      subStreams.add s.index

    for i, s in subStreams.pairs:
      let codecName = $avcodec_get_name(formatCtx.streams[s].codecpar.codec_id)
      echo "file: " & inputFile & " (" & $i & ":" & codecName & ")"

      var codecCtx = initDecoder(formatCtx.streams[s].codecpar)
      var subtitle: AVSubtitle
      while av_read_frame(formatCtx, packet) >= 0:
        defer: av_packet_unref(packet)

        if packet.stream_index == s.cint:
          var gotSubtitle: cint = 0
          let ret = avcodec_decode_subtitle2(codecCtx, addr subtitle,
            addr gotSubtitle, packet)

          if ret >= 0 and gotSubtitle != 0:
            defer: avsubtitle_free(addr subtitle)
            for i in 0..<subtitle.num_rects:
              let rect = subtitle.rects[i]
              if rect.`type` == SUBTITLE_ASS and rect.ass != nil:
                echo $rect.ass

    echo "------"
