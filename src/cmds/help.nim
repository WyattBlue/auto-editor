import std/[strformat, strutils]
import ../[cli, log]
import ../util/[fun, term]

proc printHelp*(usage: string, opts: seq[OptDef]) {.noreturn.} =
  let termWidth = max(terminalWidth(), 40)
  let optWidth = clamp(termWidth div 3, 15, 32)
  let helpWidth = termWidth - optWidth - 4

  echo "Usage: " & usage & "\n"
  echo "Options:"

  for opt in opts:
    if opt.hidden:
      continue
    var optStr = "    " & opt.names
    if opt.metavar != "":
      optStr &= " " & opt.metavar

    if optStr.len >= optWidth:
      echo optStr
      let wrapped = wrapText(opt.help, helpWidth, 0)
      for line in wrapped.split("\n"):
        echo " ".repeat(optWidth) & line
    else:
      let padding = optWidth - optStr.len
      let wrapped = wrapText(opt.help, helpWidth, optWidth)
      let helpLines = wrapped.split("\n")
      echo optStr & " ".repeat(padding) & helpLines[0]
      for i in 1 ..< helpLines.len:
        echo helpLines[i]

  echo "\n    -h, --help" & " ".repeat(optWidth - 14) &
    wrapText("Show info about this program then exit", helpWidth, optWidth)
  echo ""
  quit(0)

template parseArgs*(args: seq[string], opts: seq[OptDef], usage: string,
    prefix: string, body: untyped) =
  ## Drive a subcommand's option loop. `body` runs for every non-option
  ## argument with `key` bound to it, and dispatches on `expecting` for
  ## options that take a value. A bare `--` ends option parsing. `prefix` is
  ## what marks an unrecognized argument as a mistyped option rather than a
  ## positional; subcommands whose positionals never start with `-` pass "-".
  var expecting {.inject.} = coNone
  var parseOptions = true
  for key {.inject.} in args:
    if parseOptions and expecting == coNone and key == "--":
      parseOptions = false
      continue
    if parseOptions:
      if genCliMacro(key, args, opts):
        continue
      if key in ["-h", "--help"]:
        printHelp(usage, opts)
      if key.startsWith(prefix):
        error "Unknown option: " & key & optionDidYouMean(key, opts)
    body
