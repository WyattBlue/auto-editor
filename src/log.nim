import std/[envvars, options, os, strformat, tables, times]
when not defined(emscripten):
  import std/strutils

import ./[action, cli, ffmpeg]
import ./util/[color, rational, term]

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

type mainArgs* = object
  inputs*: seq[string]

  # Editing Options
  margin*: (PackedInt, PackedInt) = (pack(true, 200), pack(true, 200)) # 0.2s
  smooth*: (PackedInt, PackedInt) = (pack(true, 200), pack(true, 100)) # 0.2s,0.1s
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
  resolution*: (int32, int32) = (0, 0)
  sampleRate*: cint = -1
  frameRate*: AVRational = AVRational(num: 0, den: 0)
  background*: Option[RGBColor] = none(RGBColor)

  # Rendering
  videoCodec*: string = "auto"
  preset*: string = ""
  vprofile*: string = ""
  audioCodec*: string = "auto"
  audioLayout*: string = ""
  videoBitrate*: int = -1
  audioBitrate*: int = -1
  scale*: float = 1.0
  crf*: int8 = -1

  audioNormalize*: Norm = Norm(kind: nkNull)
  progress*: BarType = modern
  flags: uint32

genFlagInterface(mainArgs)

var isDebug* = false
var quiet* = false
var noCache* = false
var tempDir* = ""
let start* = epochTime()
let noColor* = getEnv("NO_COLOR") != "" or getEnv("AV_LOG_FORCE_NOCOLOR") != ""

proc conwrite*(msg: string) {.raises: [].} =
  if not quiet:
    try:
      when defined(emscripten):
        wasmProgressWrite(("  " & msg).cstring)
      else:
        let columns = terminalWidth()
        let buffer: string = " ".repeat(columns - msg.len - 3)
        stdout.write("  " & msg & buffer & "\r")
      stdout.flushFile()
    except IOError:
      discard

proc clearline* = (when not defined(emscripten): conwrite(""))

proc debug*(msg: string) =
  if isDebug:
    clearline()
    if not noColor:
      stderr.styledWriteLine(fgGreen, "Debug: ", resetStyle, msg)
    else:
      stderr.writeLine(&"Debug: {msg}")

proc warning*(msg: string) =
  if not quiet:
    clearline()
    stderr.write(&"Warning! {msg}\n")

proc closeTempDir*() {.raises: [].} =
  if tempDir != "":
    try:
      removeDir(tempDir)
    except OSError:
      discard

proc error*(msg: string) {.noreturn.} =
  closeTempDir()
  clearline()
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
