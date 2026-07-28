import std/strutils
import ../[av, cli, ffmpeg, log]
import ./help

assertArgumentOptions(descOptions, {})

proc main*(args: seq[string]) =
  av_log_set_level(AV_LOG_QUIET)

  var inputFiles: seq[string] = @[]
  parseArgs(args, descOptions, "<file ...>", "--"):
    inputFiles.add key

  var formatContext: ptr AVFormatContext
  for inputFile in inputFiles:
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
