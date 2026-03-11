import std/[envvars, math, options, os, strformat, strutils, tables, terminal, times]

import ffmpeg
import util/color
import cli

type BarType* = enum
  modern, classic, ascii, machine, none

type PackedInt* = distinct int64

func pack*(flag: bool, number: int64): PackedInt =
  let maskedNumber = number and 0x7FFFFFFFFFFFFFFF'i64
  let flagBit = if flag: 0x8000000000000000'i64 else: 0'i64
  PackedInt(flagBit or maskedNumber)

func getFlag*(packed: PackedInt): bool =
  int64(packed) < 0

func getNumber*(packed: PackedInt): int64 =
  let raw = int64(packed) and 0x7FFFFFFFFFFFFFFF'i64
  if (raw and 0x4000000000000000'i64) != 0:
    raw or 0x8000000000000000'i64
  else:
    raw

type
  NormKind* = enum
    nkNull, nkEbu, nkPeak

  Norm* = object
    case kind*: NormKind
    of nkNull:
      discard
    of nkEbu:
      i*: float32    # -70.0 to 5.0, default -24.0
      lra*: float32  # 1.0 to 50.0, default 7.0
      tp*: float32   # -9.0 to 0.0, default -2.0
      gain*: float32 # -99.0 to 99.0, default 0.0
    of nkPeak:
      t*: float32    # -99.0 to 0.0, default -8.0

  ActionKind* = enum
    actSpeed, actVarispeed, actVolume, actInvert, actZoom

  Action* = object
    case kind*: ActionKind
    of actInvert:
      discard
    of actSpeed, actVarispeed, actVolume, actZoom:
      val*: float32

  Actions* = distinct int  # A fat pointer to a list of Action(s).

func `$`*(act: Action): string =
  case act.kind
  of actSpeed: "speed:" & $act.val
  of actVarispeed: "varispeed:" & $act.val
  of actVolume: "volume:" & $act.val
  of actInvert: "invert"
  of actZoom: "zoom:" & $act.val

func `==`*(a, b: Action): bool =
  if a.kind != b.kind: return false
  case a.kind
  of actInvert: true
  of actSpeed, actVarispeed, actVolume, actZoom: a.val == b.val

const aNil* = Actions(0)
const aCut* = Actions(1)

func isCut*(a: Actions): bool = int(a) == 1
func isEmpty*(a: Actions): bool = int(a) == 0

func len*(a: Actions): int =
  if int(a) <= 1: 0
  else: int(cast[ptr int32](int(a))[])

func `[]`*(a: Actions, i: int): Action =
  let base = cast[ptr UncheckedArray[Action]](int(a) + sizeof(int32))
  base[i]

iterator items*(a: Actions): Action =
  if int(a) > 1:
    let n = a.len
    let base = cast[ptr UncheckedArray[Action]](int(a) + sizeof(int32))
    for i in 0 ..< n:
      yield base[i]

func `==`*(a, b: Actions): bool =
  let ia = int(a)
  let ib = int(b)
  if ia == ib: return true
  if ia <= 1 or ib <= 1: return false
  let n = a.len
  if n != b.len: return false
  let pa = cast[ptr UncheckedArray[Action]](ia + sizeof(int32))
  let pb = cast[ptr UncheckedArray[Action]](ib + sizeof(int32))
  for i in 0 ..< n:
    if pa[i] != pb[i]: return false
  true

proc newActions*(list: openArray[Action]): Actions =
  if list.len == 0: return aNil
  let p = alloc(sizeof(int32) + list.len * sizeof(Action))
  cast[ptr int32](p)[] = int32(list.len)
  let base = cast[ptr UncheckedArray[Action]](cast[int](p) + sizeof(int32))
  for i, a in list: base[i] = a
  Actions(cast[int](p))

func `$`*(a: Actions): string =
  if a.isCut: return "cut"
  if a.isEmpty: return "nil"
  var parts: seq[string]
  for action in a: parts.add $action
  parts.join(",")

type mainArgs* = object
  inputs*: seq[string]

  # Editing Options
  margin*: (PackedInt, PackedInt) = (pack(true, 200), pack(true, 200)) # 0.2s
  edit*: string = "audio"
  whenNormal*: Actions = aNil
  whenSilent*: Actions = aCut
  `export`*: string = ""
  output*: string = ""
  setAction*: seq[(Actions, PackedInt, PackedInt)]

  # URL download Options
  ytDlpLocation*: string = "yt-dlp"
  downloadFormat*: string
  outputFormat*: string
  ytDlpExtras*: string

  # Timeline Options
  resolution*: (int, int) = (0, 0)
  sampleRate*: cint = -1
  frameRate*: AVRational = AVRational(num: 0, den: 0)
  background*: Option[RGBColor] = none(RGBColor)

  # Rendering
  videoCodec*: string = "auto"
  vprofile*: string
  audioCodec*: string = "auto"
  audioLayout*: string = ""
  videoBitrate*: int = -1
  audioBitrate*: int = -1
  scale*: float = 1.0

  audioNormalize*: Norm = Norm(kind: nkNull)
  progress*: BarType = modern
  flags: uint32

genFlagInterface(mainArgs)

var isDebug* = false
var quiet* = false
var tempDir* = ""
let start* = epochTime()
let noColor* = getEnv("NO_COLOR") != "" or getEnv("AV_LOG_FORCE_NOCOLOR") != ""

proc conwrite*(msg: string) {.raises: [].} =
  if not quiet:
    try:
      let columns = terminalWidth()
      let buffer: string = " ".repeat(columns - msg.len - 3)
      stdout.write("  " & msg & buffer & "\r")
      stdout.flushFile()
    except IOError:
      discard

proc debug*(msg: string) =
  if isDebug:
    conwrite("")
    if not noColor:
      stderr.styledWriteLine(fgGreen, "Debug: ", resetStyle, msg)
    else:
      stderr.writeLine(&"Debug: {msg}")

proc warning*(msg: string) =
  if not quiet:
    conwrite("")
    stderr.write(&"Warning! {msg}\n")

proc closeTempDir*() {.raises: [].} =
  if tempDir != "":
    try:
      removeDir(tempDir)
    except OSError:
      discard

proc error*(msg: string) {.noreturn.} =
  closeTempDir()
  conwrite("")
  try:
    if not noColor:
      stderr.styledWriteLine(fgRed, bgBlack, "Error! ", msg, resetStyle)
    else:
      stderr.writeLine(&"Error! {msg}")
  except IOError:
    discard
  quit(1)


type StringInterner* = Table[string, ptr string]

proc intern*(interner: var StringInterner, s: string): ptr string =
  if s in interner:
    return interner[s]

  let internedStr = cast[ptr string](alloc0(sizeof(string)))
  internedStr[] = s
  interner[s] = internedStr
  return internedStr

proc cleanup*(interner: var StringInterner) =
  for ptrStr in interner.values:
    dealloc(ptrStr)
  interner.clear()


type Code* = enum
  webvtt, srt, mov_text, standard, ass, rass, display

func toTimecode*(secs: float, fmt: Code): string =
  var sign = ""
  var seconds = secs
  if seconds < 0:
    sign = "-"
    seconds = -seconds

  let totalSeconds = seconds
  let mFloat = totalSeconds / 60.0
  let hFloat = mFloat / 60.0

  let h = int(hFloat)
  let m = int(mFloat) mod 60
  let s = totalSeconds mod 60.0

  case fmt:
  of webvtt:
    (if h == 0: &"{sign}{m:02d}:{s:06.3f}" else: &"{sign}{h:02d}:{m:02d}:{s:06.3f}")
  of srt, mov_text:
    let sStr = (&"{s:06.3f}").replace(".", ",")
    &"{sign}{h:02d}:{m:02d}:{sStr}"
  of standard:
    &"{sign}{h:02d}:{m:02d}:{s:06.3f}"
  of ass:
    &"{sign}{h:d}:{m:02d}:{s:05.2f}"
  of rass:
    &"{sign}{h:d}:{m:02d}:{s:02.0f}"
  of display:
    &"{sign}{h:d}:{m:02d}:{s.round.int:02d}"
