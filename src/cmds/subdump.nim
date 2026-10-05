import std/[json, os, strutils]

import ../[av, cli, ffmpeg, log]
import ./help

assertArgumentOptions(subdumpOptions, {})

iterator subtitleEvents(container: InputContainer, stream: cint):
    tuple[start, finish: float64, ass: string] =
  ## Each text event of subtitle `stream`, from where the demuxer is, with
  ## its times in seconds.
  let formatCtx = container.formatContext
  let tbSeconds = formatCtx.streams[stream].time_base.toDouble
  var codecCtx = initDecoder(formatCtx.streams[stream].codecpar)
  defer: avcodec_free_context(addr codecCtx)
  var subtitle: AVSubtitle
  while av_read_frame(formatCtx, container.packet) >= 0:
    defer: av_packet_unref(container.packet)
    let pkt = container.packet
    if pkt.stream_index != stream: continue
    var gotSubtitle: cint = 0
    if avcodec_decode_subtitle2(codecCtx, addr subtitle, addr gotSubtitle, pkt) < 0 or
        gotSubtitle == 0:
      continue
    defer: avsubtitle_free(addr subtitle)
    # AVSubtitle.pts is in AV_TIME_BASE when set; otherwise fall back to the
    # packet pts in the stream time_base. Display times are ms relative to
    # that base; some codecs (e.g. mov_text) instead carry the duration on
    # the packet.
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
    for r in 0 ..< subtitle.num_rects:
      let rect = subtitle.rects[r]
      if rect.`type` == SUBTITLE_ASS and rect.ass != nil:
        yield (start, finish, $rect.ass)

type SubtitleCue* = tuple[start, stop: float64, text: string] ## seconds

proc readCues(path: string): seq[SubtitleCue] =
  ## The cues of the first subtitle stream in `path` that has any text; empty
  ## when it has none or can't be read.
  var container = (try: av.open(path) except IOError: return)
  defer: container.close()
  for i, st in container.subtitle:
    # The previous stream left the demuxer at EOF. Some demuxers (srt) can't
    # seek, but the first stream starts at 0 anyway.
    if i > 0 and av_seek_frame(container.formatContext, -1, 0, AVSEEK_FLAG_BACKWARD) < 0:
      break
    for (start, finish, ass) in container.subtitleEvents(st.index):
      let text = dialogue(ass).strip()
      if text.len > 0: result.add (start, finish, text)
    if result.len > 0: return

proc subtitleCues*(path: string, sidecar = "", siblings = true): seq[SubtitleCue] =
  ## The cues a subtitle lane shows: the media's own, or else its `sidecar`
  ## file's, or (with `siblings`) a sibling "<name>.srt"/".ass", which the
  ## subtitle edit method also falls back to.
  result = readCues(path)
  if result.len == 0 and sidecar.len > 0:
    result = readCues(sidecar)
  if result.len == 0 and siblings:
    for ext in ["srt", "ass"]:
      let side = path.changeFileExt(ext)
      if fileExists(side):
        result = readCues(side)
        if result.len > 0: return

proc main*(args: seq[string]) =
  av_log_set_level(AV_LOG_QUIET)

  var
    asJson = false
    inputFiles: seq[string] = @[]
  parseArgs(args, subdumpOptions, "<file> [options]", "--"):
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

      var cues: seq[JsonNode] = @[]
      # The previous stream's loop left the demuxer at EOF, so rewind before
      # dumping the next one. Only needed from the second stream on — some
      # demuxers (e.g. srt) can't seek, and the first stream starts at 0 anyway.
      if i > 0 and av_seek_frame(formatCtx, -1, 0, AVSEEK_FLAG_BACKWARD) < 0:
        error "Could not seek to start of file"
      for (start, finish, ass) in container.subtitleEvents(s):
        if asJson:
          let text = dialogue(ass).strip()
          if text.len > 0:
            cues.add( %* {"start": start, "end": finish, "text": text})
        else:
          echo ass

      if asJson:
        streamsJson.add( %* {"stream": i, "codec": codecName, "cues": cues})

    if asJson:
      jsonOut[inputFile] = %* streamsJson
    else:
      echo "------"

  if asJson:
    echo $jsonOut
