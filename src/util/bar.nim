import std/[times, math, strutils, strformat, terminal, os, osproc]

import ../log

type Bar* = ref object
  icon: string
  chars: seq[string]
  brackets: tuple[left, right: string]
  machine: bool
  hide: bool
  partWidth: int
  ampm: bool
  stack: seq[tuple[title: string, lenTitle: int, total: float, begin: float]]


proc initBar*(barType: BarType): Bar =
  var icon = "⏳"
  var chars = @[" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█"]
  var brackets = (left: "|", right: "|")
  var machine = false
  var hide = false

  case barType:
  of BarType.classic:
    icon = "⏳"
    chars = @["░", "█"]
    brackets = (left: "[", right: "]")
  of BarType.ascii:
    icon = "& "
    chars = @["-", "#"]
    brackets = (left: "[", right: "]")
  of BarType.machine:
    machine = true
  of BarType.none:
    hide = true
  else:
    discard # Use default modern style

  let partWidth = chars.len - 1

  var ampm = true
  when defined(macosx):
    if barType in {modern, classic, ascii}:
      try:
        let (dateFormat, _) = execCmdEx("defaults read com.apple.menuextra.clock Show24Hour")
        ampm = dateFormat == "0\n"
      except:
        discard

  result = Bar(
    icon: icon,
    chars: chars,
    brackets: brackets,
    machine: machine,
    hide: hide,
    partWidth: partWidth,
    ampm: ampm,
    stack: @[]
  )

proc prettyTime(myTime: float, ampm: bool): string =
  ## Format time as a pretty string
  let newTime = myTime.fromUnixFloat().local()
  var hours = newTime.hour
  let minutes = newTime.minute

  if ampm:
    if hours == 0:
      hours = 12
    elif hours > 12:
      hours -= 12
    let ampmMarker = (if newTime.hour >= 12: "PM" else: "AM")
    result = fmt"{hours:02}:{minutes:02} {ampmMarker}"
  else:
    result = fmt"{hours:02}:{minutes:02}"

proc barStr(bar: Bar, progress: float, width: int): string =
  let wholeWidth = int(progress * width.float)
  let remainderWidth = (progress * width.float) mod 1.0
  let partWidth = int(remainderWidth * bar.partWidth.float)
  let partChar = if partWidth < bar.chars.len: bar.chars[partWidth] else: ""

  let partCharFinal = if width - wholeWidth - 1 < 0: "" else: partChar

  result = bar.brackets.left &
           bar.chars[^1].repeat(wholeWidth) &
           partCharFinal &
           bar.chars[0].repeat(max(0, width - wholeWidth - 1)) &
           bar.brackets.right

proc tick*(bar: Bar, index: float) =
  if bar.hide or bar.stack.len == 0:
    return

  let (title, lenTitle, total, begin) = bar.stack[^1]
  let progress = if total == 0: 0.0 else: min(1.0, max(0.0, index / total))
  let rate = if progress == 0: 0.0 else: (epochTime() - begin) / progress

  if bar.machine:
    let indexClamped = min(index, total)
    let secsTilEta = round(begin + rate - epochTime(), 2)
    stdout.write(fmt"{title}~{indexClamped}~{total}~{secsTilEta}" & "\r")
    stdout.flushFile()
    return

  let newTime = prettyTime(begin + rate, bar.ampm)
  let percent = round(progress * 100, 1)
  let pPad = " ".repeat(max(0, 4 - ($percent).len))

  let columns = terminalWidth()
  let barLen = max(1, columns - lenTitle - 35)
  let barString = bar.barStr(progress, barLen)

  let barDisplay = fmt"  {bar.icon}{title} {barString} {pPad}{percent}%  ETA {newTime}    "
  stdout.write(barDisplay & "\r")
  stdout.flushFile()

proc start*(bar: Bar, total: float, title: string) =
  var lenTitle = 0
  var inEscape = false

  # Calculate display length excluding ANSI escape sequences
  for c in title:
    if not inEscape:
      if c == '\x1b': # ESC character
        inEscape = true
      else:
        inc lenTitle
    elif c == 'm':
      inEscape = false

  bar.stack.add((title: title, lenTitle: lenTitle, total: total, begin: epochTime()))

  try:
    bar.tick(0)
  except:
    # Fallback to ASCII if Unicode fails
    bar.icon = "& "
    bar.chars = @["-", "#"]
    bar.brackets = (left: "[", right: "]")
    bar.partWidth = 1
    bar.tick(0)

proc `end`*(bar: Bar) =
  let columns = terminalWidth()
  stdout.write(" ".repeat(max(0, columns - 2)) & "\r")
  stdout.flushFile()
  if bar.stack.len > 0:
    bar.stack.setLen(bar.stack.len - 1)

if isMainModule:
  let bar = initBar(modern)
  bar.start(1000.0, "Starting...")
  for i in countup(0, 1000):
    bar.tick(i.float64)
    sleep(33)
  bar.`end`()
