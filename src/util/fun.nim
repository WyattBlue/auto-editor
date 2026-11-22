import std/[base64, os, strutils, strformat]
from std/uri import decodeUrl
from std/math import ceil, gcd, `mod`, round, trunc, pow

import ../log
import ../lib/[dnorm16, timecode, timeunit]

func b64urlDecode*(s: string): seq[byte] =
  var padded = s.replace('-', '+').replace('_', '/')
  while padded.len mod 4 != 0:
    padded &= "="
  cast[seq[byte]](base64.decode(padded))

func visibleLen(s: string): int =
  # Count only visible characters, skipping OSC escape sequences (\e]...\e\)
  var i = 0
  while i < s.len:
    if s[i] == '\e' and i + 1 < s.len and s[i + 1] == ']':
      i += 2
      while i < s.len:
        if s[i] == '\e' and i + 1 < s.len and s[i + 1] == '\\':
          i += 2
          break
        i += 1
    else:
      result += 1
      i += 1

func wrapText*(text: string, width, indent: int): string =
  let text = text.strip(leading = true, trailing = true, chars = {'\n'})
  if text.len == 0:
    return ""
  let indentStr = " ".repeat(indent)
  var outLines: seq[string] = @[]
  var isFirst = true

  for line in text.split("\n"):
    if line.len == 0:
      outLines.add("")
      continue

    # Detect leading whitespace
    var leadingSpaces = 0
    for c in line:
      if c == ' ':
        leadingSpaces += 1
      else:
        break
    let lineIndent = " ".repeat(leadingSpaces)
    let content = line[leadingSpaces .. ^1]

    var currentLine = ""
    for word in content.splitWhitespace():
      if currentLine.len == 0:
        currentLine = word
      elif leadingSpaces + visibleLen(currentLine) + 1 + visibleLen(word) <= width:
        currentLine &= " " & word
      else:
        if isFirst:
          outLines.add(lineIndent & currentLine)
          isFirst = false
        else:
          outLines.add(indentStr & lineIndent & currentLine)
        currentLine = word
    if currentLine.len > 0:
      if isFirst:
        outLines.add(lineIndent & currentLine)
        isFirst = false
      else:
        outLines.add(indentStr & lineIndent & currentLine)

  result = outLines.join("\n")

type Code* = enum
  standard, ass, display

func toTimecode*(secs: float, fmt: Code): string =
  var sign = ""
  var seconds = secs
  if seconds < 0:
    sign = "-"
    seconds = -seconds

  # Quantize to the format's precision before splitting into h/m/s, so a
  # seconds field that would format as 60 carries into the minute
  # (59.9996 -> 00:01:00.000, not 00:00:60.000).
  let quantum = case fmt
    of standard: 1000.0
    of ass: 100.0
    of display: 1.0
  let totalSeconds = round(seconds * quantum) / quantum
  let mFloat = totalSeconds / 60.0
  let hFloat = mFloat / 60.0

  let h = int(hFloat)
  let m = int(mFloat) mod 60
  let s = totalSeconds mod 60.0

  case fmt:
  of standard:
    &"{sign}{h:02d}:{m:02d}:{s:06.3f}"
  of ass:
    &"{sign}{h:d}:{m:02d}:{s:05.2f}"
  of display:
    &"{sign}{h:d}:{m:02d}:{s.round.int:02d}"

when defined(posix):
  from std/posix import Stat, stat, S_ISREG, S_ISDIR, S_ISFIFO, S_ISSOCK

proc isDevicePath*(path: string): bool {.raises: [].} =
  ## Whether `path` names something other than a file to create or replace:
  ## a device (/dev/null), a pipe (/dev/stdout, `>(cmd)`), or a socket. Its
  ## name is fixed, so nothing may add an extension or derive siblings from it.
  when defined(windows):
    let (_, name, _) = splitFile(path)
    path.startsWith(r"\\.\") or name.toUpperAscii in ["NUL", "CON", "PRN",
      "AUX", "COM1", "COM2", "COM3", "COM4", "LPT1", "LPT2", "LPT3"]
  elif defined(posix) and not defined(emscripten):
    # An alias of an open descriptor (/dev/stdout redirected to a file)
    # stats as whatever it points at.
    if path in ["/dev/stdout", "/dev/stderr"] or path.startsWith("/dev/fd/") or
        path.startsWith("/proc/") and "/fd/" in path:
      return true
    var st: Stat
    stat(path.cstring, st) == 0 and not S_ISREG(st.st_mode) and
      not S_ISDIR(st.st_mode)
  else:
    false

proc isPipePath*(path: string): bool {.raises: [].} =
  ## Whether writing `path` can't seek back, as a muxer finishing its header
  ## would.
  when defined(posix) and not defined(emscripten):
    var st: Stat
    stat(path.cstring, st) == 0 and (S_ISFIFO(st.st_mode) or S_ISSOCK(st.st_mode))
  else:
    false

func agSplitFile*(path: string): tuple[dir, name, ext: string] =
  ## Platform-independent splitFile. Treats both '/' and '\' as path separators
  ## on every OS, so results don't drift between Linux, macOS, and Windows.
  var namePos = 0
  var dotPos = 0
  for i in countdown(path.len - 1, 0):
    if path[i] == '.' and dotPos == 0:
      dotPos = i
    elif path[i] == '/' or path[i] == '\\':
      if namePos == 0:
        namePos = i + 1
      if dotPos > namePos and dotPos < path.len - 1:
        result.name = substr(path, namePos, dotPos - 1)
        result.ext = substr(path, dotPos)
      else:
        result.name = substr(path, namePos)
      result.dir = substr(path, 0, max(0, namePos - 2))
      return
  if dotPos > 0 and dotPos < path.len - 1:
    result.name = substr(path, 0, dotPos - 1)
    result.ext = substr(path, dotPos)
  else:
    result.name = path

type AbsPath* = distinct string
  ## A filesystem path known to be absolute. `absPath` is the only
  ## constructor, so consumers can rely on the invariant (and stay `func`).

proc absPath*(path: string): AbsPath {.raises: [AutoEditorError].} =
  # absolutePath only fails if the cwd is gone or unreadable; nothing
  # downstream can recover from that.
  try:
    AbsPath(path.absolutePath())
  except CatchableError:
    error &"Cannot resolve path: {path}"
func `$`*(path: AbsPath): string {.borrow.}

func pathToUri*(path: AbsPath): string {.raises: [].} =
  ## file:// URL for a path. Bytes outside the RFC 3986 path set (spaces,
  ## '#', '%', non-ASCII, ...) are percent-encoded.
  var p = $path
  when defined(windows):
    p = p.replace('\\', '/')
    result = "file:///"
  else:
    result = "file://"
  for c in p:
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '-', '.', '_', '~', '/', ':'}:
      result.add c
    else:
      result.add '%'
      result.add toHex(ord(c), 2)

func uriToPath*(uri: string): string {.raises: [].} =
  ## The path a file:// URL names, decoded; other strings unchanged.
  var path = uri
  if path.startsWith("file://localhost/"):
    # Windows-style: file://localhost/C:/... -> C:/...
    if path.len > 18 and path[18] == ':':
      path = path[17..^1]
    else:
      path = path[16..^1]
  elif path.startsWith("file://"):
    # Windows-style: file:///C:/... -> C:/...
    if path.len > 9 and path[9] == ':':
      path = path[8..^1]
    else:
      # Unix-style: file:///path -> /path
      path = path[7..^1]
  else:
    return uri
  return decodeUrl(path, decodePlus = false)

const
  commonAspectRatios = [
    (1, 1), (5, 4), (4, 3), (3, 2), (16, 10), (16, 9), (2, 1), (64, 27)
  ]
  # Max drift, in stored pixels, between a dimension and what a common ratio
  # would produce for us to treat the difference as codec-friendly rounding
  # rather than a deliberate ratio. Absolute (not relative) so the snap stays
  # tight at high resolutions where a percentage would be many pixels wide.
  aspectSnapDrift = 2.0

func aspectRatio*(width, height: int, sarNum = 1, sarDen = 1): tuple[w, h: int] =
  if width <= 0 or height <= 0:
    return (0, 0)

  # Fold the sample (pixel) aspect ratio into the dimensions so anamorphic video
  # reports its true display aspect ratio, the way ffmpeg's DAR does.
  let
    sn = max(sarNum, 1)
    sd = max(sarDen, 1)
    dispW = width * sn
    dispH = height * sd
    c = gcd(dispW, dispH)
  result = (dispW div c, dispH div c)

  # A clean, small reduction is already a meaningful ratio (16:9, 4:3, 8:5...).
  if max(result.w, result.h) <= 50:
    return

  let (w, h) = (width.float, height.float)
  var bestDrift = aspectSnapDrift
  for (cw, ch) in commonAspectRatios:
    for (a, b) in [(cw, ch), (ch, cw)]:
      # Stored dimensions that would yield this display ratio for the given SAR.
      let
        ta = float(a * sd) # storage-width units
        tb = float(b * sn) # storage-height units
        drift = max(abs(w - h * ta / tb), abs(h - w * tb / ta))
      if drift < bestDrift:
        bestDrift = drift
        result = (a, b)

const
  minSampleRate* = 100
  maxSampleRate* = 768_000 ## the highest PCM rate in use

proc splitNumStr*(val: string): (float64, string) =
  var index = 0
  for char in val:
    if char notin "0123456789_ .-":
      break
    index += 1
  let (num, unit) = (val[0 ..< index], val[index .. ^1])
  var floatNum: float64
  try:
    floatNum = parseFloat(num.replace(" ", ""))
  except:
    error &"Invalid number: '{val}'"
  return (floatNum, unit)

proc parseThres*(val: string): Unorm16 =
  let (num, unit) = splitNumStr(val)
  var r: float32
  if unit == "%":
    r = float32(num / 100)
  elif unit == "dB":
    r = float32(pow(10, num / 20))
  elif unit == "":
    r = float32(num)
  else:
    error &"Unknown unit: {unit}"
  if r < 0 or r > 1:
    error &"Threshold not in range: {val} ({r})"
  return toUnorm16(r)

proc parseBitrate*(input: string): int =
  if input == "auto":
    return -1

  let (val, unit) = splitNumStr(input)
  let scale =
    if unit.toLowerAscii() == "k": 1000.0
    elif unit == "M": 1_000_000.0
    elif unit == "G": 1_000_000_000.0
    elif unit == "": 1.0
    else: error &"Unknown bitrate: {input}"
  let bits = val * scale
  # float -> int is unchecked: out of range or NaN, it's garbage. `not (a and
  # b)` so NaN fails too. A negative one would read as "auto".
  if not (bits >= 0 and bits < high(int).float64):
    error &"Bitrate out of range: {input}"
  int(bits)

# Times stay well inside int64 so arithmetic on them can't overflow; "end"
# is the largest.
const timeSpan = float64(1'i64 shl 62)
const endFrames = 0x3FFFFFFFFFFFFFFF'i64

proc parseTimeSimple*(val: string): TimeSpec =
  let (num, unit) = splitNumStr(val)
  # float -> int is unchecked: out of range or NaN, it's garbage. `not (a and
  # b)` so NaN fails too.
  template checked(x: float64): int64 =
    let f = x
    if not (f > -timeSpan and f < timeSpan):
      error &"'{val}': Time is out of range"
    f.int64
  var tu: TimeUnit
  if not parseTimeUnit(unit, tu):
    error &"'{val}': Time format got unknown unit: `{unit}`"
  if tu != tuFrames:
    return millis(checked(round(num * 1000 * tu.seconds)))

  if num != trunc(num):
    if unit == "":
      error &"'{val}': A time without a unit is a frame count, so it must be " &
        &"whole. For seconds, write '{val}s'"
    error &"'{val}': A frame count must be whole"
  return frames(checked(num))

proc parseClock(val: string): TimeSpec =
  ## `HH:MM:SS:FF` timecode (`;FF` for drop frame), or `MM:SS` and
  ## `HH:MM:SS` clock time with optional decimal seconds. MM:SS:FF isn't
  ## taken: it reads the same as HH:MM:SS.
  let neg = val.startsWith("-")
  let body = (if neg: val[1 .. ^1] else: val)
  var seps = 0
  for c in body:
    if c in {':', ';'}: inc seps
  if seps == 3:
    let semi = body.find(';')
    if '.' in body or ',' in body or semi >= 0 and semi < body.rfind(':'):
      error &"'{val}': Timecode is HH:MM:SS:FF, or HH:MM:SS;FF for drop frame"
    var tc: Timecode
    if not parseTimecode(body, tc):
      error &"'{val}': Timecode is HH:MM:SS:FF, or HH:MM:SS;FF for drop frame"
    if tc.m >= 60 or tc.s >= 60:
      error &"'{val}': Timecode minutes and seconds must be under 60"
    return TimeSpec(kind: tkTimecode, tc: tc, neg: neg)
  if seps notin 1..2 or ';' in body:
    error &"'{val}': Write a time as MM:SS or HH:MM:SS, or timecode as HH:MM:SS:FF"
  let parts = body.split(':')
  var total = 0.0
  for i, part in parts:
    var dots = 0
    for c in part:
      if c == '.': inc dots
      elif c notin Digits: dots = 2
    if part.len == 0 or dots > 1 or dots == 1 and i < parts.high:
      error &"'{val}': Write a time as MM:SS or HH:MM:SS, or timecode as HH:MM:SS:FF"
    let x = (try: parseFloat(part) except ValueError: 0.0)
    if i > 0 and x >= 60:
      error &"'{val}': Minutes and seconds must be under 60"
    total = total * 60 + x
  let ms = round(total * 1000)
  if not (ms < timeSpan):
    error &"'{val}': Time is out of range"
  millis(if neg: -ms.int64 else: ms.int64)

proc parseTime*(val: string): TimeSpec =
  if val == "start":
    return frames(0)
  if val == "end":
    return frames(endFrames)
  if ':' in val or ';' in val:
    return parseClock(val)
  return parseTimeSimple(val)

proc toTb*(val: TimeSpec, tb: float64): int =
  case val.kind
  of tkFrames:
    int(val.n)
  of tkMillis:
    # A time that far out is past "end" anyway; it saturates.
    let f = round(val.n.float64 / 1000.0 * tb)
    if not (f > low(int).float64 and f < high(int).float64):
      return (if f < 0: low(int) else: high(int))
    f.int
  of tkTimecode:
    # Timecode counts whole frames a second: 30 for 29.97.
    let base = max(1'i64, int64(ceil(tb - 1e-9)))
    if val.tc.f >= base:
      error &"Timecode frame {val.tc.f} is past the timeline's {base} frames a second"
    let ntsc = base mod 30 == 0 and abs(tb - base.float64) > 1e-6
    if val.tc.drop and not ntsc:
      error "Drop-frame timecode (with ';') needs a 29.97 or 59.94 fps timeline"
    let n = val.tc.toFrames(base, val.tc.drop)
    int(if val.neg: -n else: n)
