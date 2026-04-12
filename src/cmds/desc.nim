import ../[av, ffmpeg]

proc main*(args: seq[string]) {.raises: [].} =
  av_log_set_level(AV_LOG_QUIET)

  var formatContext: ptr AVFormatContext
  for inputFile in args:
    try:
      formatContext = av.openFormatCtx(inputFile.cstring)
    except IOError:
      continue

    var entry = av_dict_get(formatContext.metadata, "description", nil, 0)
    try:
      if entry != nil:
        stdout.write("\n" & $entry.value & "\n\n")
      else:
        stdout.write("\nNo description.\n\n")
    except IOError:
      discard

    avformat_close_input(addr formatContext)
