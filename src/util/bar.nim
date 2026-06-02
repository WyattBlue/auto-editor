import std/[times, math, strutils, strformat, os]
import std/[typedthreads, atomics]
when not defined(windows):
  import std/posix
  var SIGWINCH {.importc, header: "<signal.h>".}: cint

when defined(macosx):
  import std/osproc

import ../log
import ./term

when not defined(windows):
  var termResized {.global.}: Atomic[bool]

  proc sigwinchHandler(sig: cint) {.noconv.} =
    termResized.store(true)

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
    result = &"{hours:02}:{minutes:02} {ampmMarker}"
  else:
    result = &"{hours:02}:{minutes:02}"

type
  BarConfig = object
    icon: string
    chars: seq[string]
    brackets: tuple[left, right: string]
    partWidth: int
    machine: bool
    hide: bool
    ampm: bool

  ThreadData = ref object
    progress: Atomic[float]
    total: Atomic[float]
    shouldStop: Atomic[bool]
    paused: Atomic[bool]        # set by end() to halt writes
    sleeping: Atomic[bool]      # set by worker to acknowledge it isn't writing
    indeterminate: Atomic[bool] # animate without a known total
    title: string
    lenTitle: int
    begin: float
    config: ptr BarConfig # Share constant config via pointer

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

proc formatProgressOutput(config: BarConfig, title: string, lenTitle, columns: int,
    progress, rate, begin, currentIndex, total: float): string =
  if config.machine:
    let indexClamped = min(currentIndex, total)
    let secsTilEta = round(begin + rate - epochTime(), 2)
    return &"{title}~{indexClamped}~{total}~{secsTilEta}"
  else:
    let newTime = prettyTime(begin + rate, config.ampm)

    let percent = (if progress == 1.0: "100" else: $round(progress * 100, 1))
    let pPad = " ".repeat(max(0, 4 - percent.len))

    let barLen = max(1, columns - lenTitle - 35)
    let barString = createBarString(config, progress, barLen)

    return &"  {config.icon}{title} {barString} {pPad}{percent}%  ETA {newTime}    "

# Indeterminate sweep: one band whose leading and trailing edges each follow
# their own eased timing, so it stretches as it accelerates in and squashes as
# it slides out — Material Design style, but a single band (no overlap). The
# band travels from off the left edge to off the right edge each `sweepCycle`
# seconds, with a brief gap before re-entering.
const sweepCycle = 1.8

proc cubicBezier(x1, y1, x2, y2, t: float): float =
  ## Evaluate a CSS cubic-bezier(x1,y1,x2,y2) easing at input fraction t.
  proc sampleX(s: float): float =
    let u = 1.0 - s
    3 * u * u * s * x1 + 3 * u * s * s * x2 + s * s * s
  proc sampleY(s: float): float =
    let u = 1.0 - s
    3 * u * u * s * y1 + 3 * u * s * s * y2 + s * s * s

  # Invert x(s) = t with Newton-Raphson, then read off y(s).
  var s = t
  for _ in 0 ..< 8:
    let x = sampleX(s) - t
    let d = 3 * (1 - s) * (1 - s) * x1 + 6 * (1 - s) * s * (x2 - x1) +
            3 * s * s * (1 - x2)
    if abs(d) < 1e-6:
      break
    s = clamp(s - x / d, 0.0, 1.0)
  sampleY(s)

proc createIndeterminateBarString(config: BarConfig, phase: float, width: int): string =
  ## A single eased band sweeping across the track.
  # Edges run from -0.15 (off left) to 1.15 (off right). The leading edge
  # accelerates early; the trailing edge lags then catches up.
  let leading = -0.15 + 1.30 * cubicBezier(0.20, 0.80, 0.40, 1.00, phase)
  let trailing = -0.15 + 1.30 * cubicBezier(0.60, 0.00, 0.75, 0.45, phase)

  var cells = newSeq[string](width)
  for i in 0 ..< width:
    let center = (i.float + 0.5) / width.float
    cells[i] = if center >= trailing and center <= leading: config.chars[^1]
               else: config.chars[0]

  result = config.brackets.left & cells.join("") & config.brackets.right

proc formatIndeterminateOutput(config: BarConfig, title: string, lenTitle,
    columns: int, elapsed: float): string =
  if config.machine:
    return &"{title}~-1~-1~{round(elapsed, 2)}"
  else:
    # No percent/ETA suffix, so the bar can stretch across most of the line.
    let barLen = max(1, columns - lenTitle - 14)
    let phase = (elapsed mod sweepCycle) / sweepCycle
    let barString = createIndeterminateBarString(config, phase, barLen)
    return &"  {config.icon}{title} {barString}  "

proc progressWorker(data: ThreadData) {.thread.} =
  ## Background thread worker that handles progress bar updates with full format
  var lastProgress: float = -1
  var lastFrame = -1
  let config = data.config[] # Dereference once and cache
  const sleepRate = 8 # ~120 FPS update rate
  const animFps = 60.0 # indeterminate animation refresh rate
  var columns = terminalWidth()
  when defined(windows):
    var widthCounter = 0
    const widthRefreshRate = 63 # refresh terminal width ~twice per second (500ms / 8ms)

  while not data.shouldStop.load():
    if data.paused.load():
      data.sleeping.store(true)
      sleep(sleepRate)
      continue

    data.sleeping.store(false)

    when not defined(windows) and not defined(emscripten):
      if termResized.load():
        columns = terminalWidth()
        termResized.store(false)
    elif defined(windows):
      inc widthCounter
      if widthCounter >= widthRefreshRate:
        columns = terminalWidth()
        widthCounter = 0

    if data.indeterminate.load():
      let elapsed = epochTime() - data.begin
      let frame = int(elapsed * animFps)
      if frame == lastFrame:
        data.sleeping.store(true)
        sleep(sleepRate)
        continue
      lastFrame = frame

      let output = formatIndeterminateOutput(config, data.title, data.lenTitle,
          columns, elapsed)
      when defined(emscripten):
        wasmProgressWrite(output.cstring)
      else:
        stdout.write(output & "\r")
        stdout.flushFile()
      sleep(sleepRate)
      continue

    let currentProgress = data.progress.load()
    if currentProgress == lastProgress:
      data.sleeping.store(true)
      sleep(sleepRate)
      continue

    let total = data.total.load()
    let progress = if total == 0: 0.0 else: min(1.0, max(0.0, currentProgress / total))
    let rate = if progress == 0: 0.0 else: (epochTime() - data.begin) / progress

    let output = formatProgressOutput(config, data.title, data.lenTitle, columns,
        progress, rate, data.begin, currentProgress, total)
    when defined(emscripten):
      wasmProgressWrite(output.cstring)
    else:
      stdout.write(output & "\r")
      stdout.flushFile()

    lastProgress = currentProgress
    sleep(sleepRate)

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
    when not defined(windows):
      termResized.store(false)
      signal(SIGWINCH, sigwinchHandler)
    result.threadData = ThreadData(config: addr result.config)
    result.threadData.shouldStop.store(false)
    result.threadData.paused.store(true) # start() unpauses; prevents writes before first bar
    createThread(result.progressThread, progressWorker, result.threadData)


func tick*(bar: Bar, index: float) =
  if not bar.hide:
    bar.threadData.progress.store(index)

func displayLen(title: string): int =
  ## Display length of a title, excluding ANSI escape sequences.
  var inEscape = false
  for c in title:
    if not inEscape:
      if c == '\x1b': # ESC character
        inEscape = true
      else:
        inc result
    elif c == 'm':
      inEscape = false

proc beginBar(bar: Bar, title: string, total: float, indeterminate: bool) =
  when defined(windows):
    stdout.write("\x1b[?25l") # hide cursor to prevent visible jumps while drawing
    stdout.flushFile()

  bar.threadData.title = title
  bar.threadData.lenTitle = displayLen(title)
  bar.threadData.total.store(total)
  bar.threadData.progress.store(0.0)
  bar.threadData.begin = epochTime()
  bar.threadData.indeterminate.store(indeterminate)
  bar.threadData.sleeping.store(false)
  bar.threadData.paused.store(false)

proc start*(bar: Bar, total: float, title: string) =
  if not bar.hide:
    beginBar(bar, title, total, indeterminate = false)

proc startIndeterminate*(bar: Bar, title: string) =
  if not bar.hide:
    beginBar(bar, title, 0.0, indeterminate = true)

proc `end`*(bar: Bar) =
  if not bar.hide:
    bar.threadData.paused.store(true)
    # Wait for the worker to observe the pause before clearing, so it can't
    # re-draw the bar after we wipe the line.
    while not bar.threadData.sleeping.load():
      sleep(1)
    let columns = terminalWidth()
    stdout.write(" ".repeat(max(0, columns - 2)) & "\r")
    when defined(windows):
      stdout.write("\x1b[?25h") # restore cursor
    stdout.flushFile()
  if bar.stack.len > 0:
    bar.stack.setLen(bar.stack.len - 1)

proc destroy*(bar: Bar) =
  if bar.threadData != nil:
    bar.threadData.shouldStop.store(true)
    joinThread(bar.progressThread)
  when defined(windows):
    if not bar.hide:
      try:
        stdout.write("\x1b[?25h")
        stdout.flushFile()
      except IOError:
        discard
