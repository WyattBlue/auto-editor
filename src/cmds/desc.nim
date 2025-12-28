import ../av
import ../ffmpeg

proc main*(args: seq[string]) =
  av_log_set_level(AV_LOG_QUIET)

  for inputFile in args:
    var container = av.open(inputFile)
    let formatContext = container.formatContext
    var entry = av_dict_get(formatContext.metadata, "description", nil, 0)

    if entry != nil:
      stdout.write("\n" & $entry.value & "\n\n")
    else:
      stdout.write("\nNo description.\n\n")

    container.close()

