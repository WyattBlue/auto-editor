import std/[times, math, strutils, strformat, terminal, os]
import std/[typedthreads, atomics]

when defined(macosx):
  import std/osproc

import ../log

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

type
  BarConfig = object
    icon: string
    chars: seq[string]
    brackets: tuple[left, right: string]
    machine: bool
    hide: bool
    partWidth: int
    ampm: bool

  ThreadData = ref object
    progress: Atomic[float]
    total: Atomic[float]
    shouldStop: Atomic[bool]
    hasUpdate: Atomic[bool]
    title: string
    lenTitle: int
    begin: float
    config: ptr BarConfig  # Share constant config via pointer

  Bar* = ref object
    config: BarConfig
    stack: seq[tuple[title: string, lenTitle: int, total: float, begin: float]]
    progressThread: Thread[ThreadData]
    threadData: ThreadData
    hide: bool

proc createBarString(config: BarConfig, progress: float, width: int): string =
  let wholeWidth = int(progress * width.float)
  let remainderWidth = (progress * width.float) mod 1.0
  let partWidth = int(remainderWidth * config.partWidth.float)
  let partChar = if partWidth < config.chars.len: config.chars[partWidth] else: ""

  let partCharFinal = if width - wholeWidth - 1 < 0: "" else: partChar

  result = config.brackets.left &
           config.chars[^1].repeat(wholeWidth) &
           partCharFinal &
           config.chars[0].repeat(max(0, width - wholeWidth - 1)) &
           config.brackets.right

proc formatProgressOutput(config: BarConfig, title: string, lenTitle: int, progress: float, rate: float, begin: float, currentIndex: float, total: float): string =
  if config.machine:
    let indexClamped = min(currentIndex, total)
    let secsTilEta = round(begin + rate - epochTime(), 2)
    return fmt"{title}~{indexClamped}~{total}~{secsTilEta}"
  else:
    let newTime = prettyTime(begin + rate, config.ampm)
    let percent = round(progress * 100, 1)
    let pPad = " ".repeat(max(0, 4 - ($percent).len))

    let columns = terminalWidth()
    let barLen = max(1, columns - lenTitle - 35)
    let barString = createBarString(config, progress, barLen)

    return fmt"  {config.icon}{title} {barString} {pPad}{percent}%  ETA {newTime}    "

proc progressWorker(data: ThreadData) {.thread.} =
  ## Background thread worker that handles progress bar updates with full format
  var lastProgress: float = -1
  let config = data.config[]  # Dereference once and cache
  const sleepRate = 16 # ~60 FPS update rate

  while not data.shouldStop.load():
    let hasUpdate = data.hasUpdate.load()
    if not hasUpdate:
      sleep(sleepRate)
      continue

    let currentProgress = data.progress.load()
    if currentProgress == lastProgress:
      data.hasUpdate.store(false)
      sleep(sleepRate)
      continue

    let total = data.total.load()
    let progress = if total == 0: 0.0 else: min(1.0, max(0.0, currentProgress / total))
    let rate = if progress == 0: 0.0 else: (epochTime() - data.begin) / progress

    let output = formatProgressOutput(config, data.title, data.lenTitle, progress, rate, data.begin, currentProgress, total)
    stdout.write(output & "\r")
    stdout.flushFile()

    lastProgress = currentProgress
    data.hasUpdate.store(false)
    sleep(sleepRate)

proc initBar*(barType: BarType, threaded: bool = true): Bar =
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

  let config = BarConfig(
    icon: icon,
    chars: chars,
    brackets: brackets,
    machine: machine,
    partWidth: partWidth,
    ampm: ampm
  )
  result = Bar(hide: hide, config: config, stack: @[])
  if not hide:
    result.threadData = ThreadData(config: addr result.config)
    result.threadData.shouldStop.store(false)
    result.threadData.hasUpdate.store(false)
    createThread(result.progressThread, progressWorker, result.threadData)


func tick*(bar: Bar, index: float) =
  if not bar.hide:
    bar.threadData.progress.store(index)
    bar.threadData.hasUpdate.store(true)

proc start*(bar: Bar, total: float, title: string) =
  if bar.hide:
    return

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

  bar.threadData.title = title
  bar.threadData.lenTitle = lenTitle
  bar.threadData.total.store(total)
  bar.threadData.progress.store(0.0)
  bar.threadData.begin = epochTime()
  bar.threadData.hasUpdate.store(true)

proc `end`*(bar: Bar) =
  let columns = terminalWidth()
  stdout.write(" ".repeat(max(0, columns - 2)) & "\r")
  stdout.flushFile()
  if bar.stack.len > 0:
    bar.stack.setLen(bar.stack.len - 1)

proc destroy*(bar: Bar) =
  if bar.threadData != nil:
    bar.threadData.shouldStop.store(true)
    joinThread(bar.progressThread)
