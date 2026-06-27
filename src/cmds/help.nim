import std/strutils
import ../cli
import ../util/[fun, term]

proc printHelp*(usage: string, opts: seq[OptDef]) {.noreturn.} =
  let termWidth = max(terminalWidth(), 40)
  let optWidth = min(32, termWidth div 3)
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
