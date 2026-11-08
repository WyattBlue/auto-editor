## SMPTE timecode, as EDLs count it: whole frames at an integer base, with
## drop-frame numbering for the NTSC rates.

from std/math import ceil
import std/strutils

import ../ffmpeg
import ../util/rational

type Timecode* = object
  h*, m*, s*, f*: int64
  drop*: bool ## written with a `;`, `.` or `,` separator

func timecodeBase*(tb: AVRational): int64 =
  ## The frames a second holds in timecode: 30 for 29.97, 24 for 23.976.
  max(1'i64, int64(ceil(tb.float64 - 1e-9)))

func dropPerMinute(base: int64): int64 =
  ## 29.97 skips two numbers a minute, 59.94 four.
  base div 15

func toFrames*(tc: Timecode, base: int64, drop: bool): int64 =
  let minutes = tc.h * 60 + tc.m
  result = (minutes * 60 + tc.s) * base + tc.f
  if drop:
    # Every minute but the tenth begins a few numbers in.
    result -= dropPerMinute(base) * (minutes - minutes div 10)

func formatTimecode*(frames: int64, base: int64, drop = false): string =
  var n = max(0'i64, frames)
  var h, m, s, f: int64
  if drop:
    let d = dropPerMinute(base)
    let perTenMinutes = base * 600 - d * 9
    let perMinute = base * 60 - d
    let tens = n div perTenMinutes
    var rest = n mod perTenMinutes
    var minutes = tens * 10
    if rest >= base * 60:
      # The first minute of each ten is full; the rest each skip `d`.
      rest -= base * 60
      minutes += 1 + rest div perMinute
      rest = rest mod perMinute + d
    f = rest mod base
    s = rest div base
    h = minutes div 60
    m = minutes mod 60
  else:
    f = n mod base
    n = n div base
    s = n mod 60
    n = n div 60
    m = n mod 60
    h = n div 60
  let sep = (if drop: ";" else: ":")
  result = align($h, 2, '0') & ":" & align($m, 2, '0') & ":" &
    align($s, 2, '0') & sep & align($f, 2, '0')

func parseTimecode*(text: string, tc: var Timecode): bool =
  ## `hh:mm:ss:ff`; a `;`, `.` or `,` before the frames marks drop frame.
  var fields: seq[int64]
  var drop = false
  var i = 0
  while i < text.len:
    var j = i
    var value = 0'i64
    while j < text.len and text[j] in Digits:
      if j - i >= 9: return false
      value = value * 10 + int64(ord(text[j]) - ord('0'))
      inc j
    if j == i: return false
    fields.add value
    if j == text.len: break
    case text[j]
    of ':': discard
    of ';', '.', ',': drop = true
    else: return false
    i = j + 1
    if i == text.len: return false
  if fields.len != 4: return false
  tc = Timecode(h: fields[0], m: fields[1], s: fields[2], f: fields[3], drop: drop)
  true
