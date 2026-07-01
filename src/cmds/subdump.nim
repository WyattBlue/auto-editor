import std/[json, strutils]

import ../[av, cli, ffmpeg, log]
import ./help

proc main*(args: seq[string]) =
  av_log_set_level(AV_LOG_QUIET)

  var
    asJson = false
    inputFiles: seq[string] = @[]
  for key in args:
    if genCliMacro(key, args, subdumpOptions):
      continue
    if key in ["-h", "--help"]:
      printHelp("<file> [options]", subdumpOptions)
    if key.startsWith("--"):
      error "Unknown option: " & key
    inputFiles.add key

  var jsonOut = %* {}

  var container: InputContainer
  for inputFile in inputFiles:
    try:
      container = av.open(inputFile)
    except IOError as e:
      error(e.msg)
    defer: container.close()
    let formatCtx = container.formatContext

    var subStreams: seq[cint] = @[]
    for s in container.subtitle:
      subStreams.add s.index

    var streamsJson: seq[JsonNode] = @[]

    for i, s in subStreams.pairs:
      let codecName = $avcodec_get_name(formatCtx.streams[s].codecpar.codec_id)
      if not asJson:
        echo "file: " & inputFile & " (" & $i & ":" & codecName & ")"

      let tbSeconds = formatCtx.streams[s].time_base.toDouble
      var cues: seq[JsonNode] = @[]
      var codecCtx = initDecoder(formatCtx.streams[s].codecpar)
      var subtitle: AVSubtitle
      # The previous stream's loop left the demuxer at EOF.
      if av_seek_frame(formatCtx, -1, 0, AVSEEK_FLAG_BACKWARD) < 0:
        error "Could not seek to start of file"
      while av_read_frame(formatCtx, container.packet) >= 0:
        defer: av_packet_unref(container.packet)

        if container.packet.stream_index == s.cint:
          let pkt = container.packet
          var gotSubtitle: cint = 0
          let ret = avcodec_decode_subtitle2(codecCtx, addr subtitle,
            addr gotSubtitle, pkt)

          if ret >= 0 and gotSubtitle != 0:
            defer: avsubtitle_free(addr subtitle)
            # AVSubtitle.pts is in AV_TIME_BASE when set; otherwise fall back to
            # the packet pts in the stream time_base. Display times are ms
            # relative to that base; some codecs (e.g. mov_text) instead carry
            # the duration on the packet.
            let base =
              if subtitle.pts != AV_NOPTS_VALUE: subtitle.pts.float / AV_TIME_BASE.float
              elif pkt.pts != AV_NOPTS_VALUE: pkt.pts.float * tbSeconds
              else: 0.0
            let start = base + subtitle.start_display_time.float / 1000.0
            let finish =
              if subtitle.end_display_time > subtitle.start_display_time:
                base + subtitle.end_display_time.float / 1000.0
              elif pkt.duration > 0:
                base + pkt.duration.float * tbSeconds
              else:
                start
            for i in 0..<subtitle.num_rects:
              let rect = subtitle.rects[i]
              if rect.`type` == SUBTITLE_ASS and rect.ass != nil:
                if asJson:
                  let text = dialogue($rect.ass).strip()
                  if text.len > 0:
                    cues.add( %* {"start": start, "end": finish, "text": text})
                else:
                  echo $rect.ass

      if asJson:
        streamsJson.add( %* {"stream": i, "codec": codecName, "cues": cues})

    if asJson:
      jsonOut[inputFile] = %* streamsJson
    else:
      echo "------"

  if asJson:
    echo $jsonOut
