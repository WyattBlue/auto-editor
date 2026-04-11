import ../[av, ffmpeg]

proc main*(args: seq[string]) =
  av_log_set_level(AV_LOG_QUIET)

  for inputFile in args:
    let formatContext = av.openFormatCtx(inputFile.cstring)
    var entry = av_dict_get(formatContext.metadata, "description", nil, 0)

    if entry != nil:
      stdout.write("\n" & $entry.value & "\n\n")
    else:
      stdout.write("\nNo description.\n\n")

    avformat_close_input(addr formatContext)
