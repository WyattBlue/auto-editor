import std/[os, envvars]
import std/times

import std/tables
import std/terminal
import std/[strutils, strformat]
import std/math

import util/color
import ffmpeg

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
      i*: float32      # -70.0 to 5.0, default -24.0
      lra*: float32    # 1.0 to 50.0, default 7.0
      tp*: float32     # -9.0 to 0.0, default -2.0
      gain*: float32   # -99.0 to 99.0, default 0.0
    of nkPeak:
      t*: float32 # -99.0 to 0.0, default -8.0

  ActionKind* = enum
    actCut, actSpeed, actVarispeed, actVolume

  Action* = object
    case kind*: ActionKind
    of actCut:
      discard
    of actSpeed, actVarispeed, actVolume:
      val*: float32

func `==`*(a, b: Action): bool =
  if a.kind != b.kind:
    return false
  case a.kind
  of actCut:
    return true
  of actSpeed, actVarispeed, actVolume:
    return a.val == b.val

type mainArgs* = object
  input*: string = ""

  # Editing Options
  margin*: (PackedInt, PackedInt) = (pack(true, 200), pack(true, 200)) # 0.2s
  edit*: string = "audio"
  whenNormal*: seq[Action] = @[]
  whenSilent*: seq[Action] = @[Action(kind: actCut)]
  `export`*: string = ""
  output*: string = ""
  cutOut*: seq[(PackedInt, PackedInt)]
  addIn*: seq[(PackedInt, PackedInt)]
  setSpeed*: seq[(float64, PackedInt, PackedInt)]

  # Timeline Options
  sampleRate*: cint = -1
  frameRate*: AVRational = AVRational(num: 0, den: 0)
  background* = RGBColor(red: 0, green: 0, blue: 0)
  resolution*: (int, int) = (0, 0)

  # URL download Options
  ytDlpLocation*: string = "yt-dlp"
  downloadFormat*: string
  outputFormat*: string
  ytDlpExtras*: string

  # Display Options
  progress*: BarType = modern
  preview*: bool = false

  # Container Settings
  vn*: bool = false
  an*: bool = false
  sn*: bool = false
  dn*: bool = false
  faststart*: bool = false
  noFaststart*: bool = false
  fragmented*: bool = false
  noFragmented*: bool = false

  # Video Rendering
  videoCodec*: string = "auto"
  videoBitrate*: int = -1
  vprofile*: string
  noSeek*: bool = false
  scale*: float = 1.0

  # Audio Rendering
  audioCodec*: string = "auto"
  audioLayout*: string = ""
  audioBitrate*: int = -1
  mixAudioStreams*: bool = false
  audioNormalize*: Norm = Norm(kind: nkNull)

  # Misc.
  noOpen*: bool = false

var isDebug* = false
var quiet* = false
var tempDir* = ""
let start* = epochTime()
let noColor* = getEnv("NO_COLOR") != "" or getEnv("AV_LOG_FORCE_NOCOLOR") != ""

proc conwrite*(msg: string) {.raises:[].} =
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

proc closeTempDir*() {.raises:[].} =
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


type StringInterner* = object
  strings*: Table[string, ptr string]

func newStringInterner*(): StringInterner =
  result.strings = initTable[string, ptr string]()

proc intern*(interner: var StringInterner, s: string): ptr string =
  if s in interner.strings:
    return interner.strings[s]

  let internedStr = cast[ptr string](alloc0(sizeof(string)))
  internedStr[] = s
  interner.strings[s] = internedStr
  return internedStr

proc cleanup*(interner: var StringInterner) =
  for ptrStr in interner.strings.values:
    dealloc(ptrStr)
  interner.strings.clear()


type Code* = enum
  webvtt, srt, mov_text, standard, ass, rass, display

func toTimecode*(secs: float, fmt: Code): string =
  var sign = ""
  var seconds = secs
  if seconds < 0:
    sign = "-"
    seconds = -seconds

  let total_seconds = seconds
  let m_float = total_seconds / 60.0
  let h_float = m_float / 60.0

  let h = int(h_float)
  let m = int(m_float) mod 60
  let s = total_seconds mod 60.0

  case fmt:
  of webvtt:
    if h == 0:
      return fmt"{sign}{m:02d}:{s:06.3f}"
    return fmt"{sign}{h:02d}:{m:02d}:{s:06.3f}"
  of srt, mov_text:
    let s_str = fmt"{s:06.3f}".replace(".", ",")
    return fmt"{sign}{h:02d}:{m:02d}:{s_str}"
  of standard:
    return fmt"{sign}{h:02d}:{m:02d}:{s:06.3f}"
  of ass:
    return fmt"{sign}{h:d}:{m:02d}:{s:05.2f}"
  of rass:
    return fmt"{sign}{h:d}:{m:02d}:{s:02.0f}"
  of display:
    return fmt"{sign}{h:d}:{m:02d}:{s.round.int:02d}"
