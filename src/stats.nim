import std/[sets, strutils, strformat]
from std/math import round
import csort

import av
import ffmpeg
import log
import timeline

type f64 = float64

func timeFrame(title: string, ticks: int64, tb: f64, per: string = ""): string =
  let tc = toTimecode(ticks.f64 / tb, Code.ass)
  let tp = (if tc.startsWith("-"): 9 else: 10)
  let tcp = (if tc.startsWith("-"): 12 else: 11)
  let endStr = (if per == "": "" else: " " & alignLeft(per, 7))

  let titlePart = alignLeft(title & ":", tp)
  let tcPart = alignLeft(tc, tcp)
  let ticksPart = alignLeft(&"({ticks})", 6)

  return &" - {titlePart} {tcPart} {ticksPart}{endStr}"

func timeFrame(title: string, ticks, tb: f64, per: string = ""): string =
  let tc = toTimecode(ticks / tb, Code.ass)
  let tp = (if tc.startsWith("-"): 9 else: 10)
  let tcp = (if tc.startsWith("-"): 12 else: 11)
  let endStr = (if per == "": "" else: " " & alignLeft(per, 7))

  let titlePart = alignLeft(title & ":", tp)
  let tcPart = alignLeft(tc, tcp)
  let ticksPart = alignLeft(&"({ticks:.2f})", 6)

  return &" - {titlePart} {tcPart} {ticksPart}{endStr}"

func mean(data: seq[int64]): f64 =
  var sum: int64 = 0
  for d in data:
    sum += d

  return sum / data.len

func median(data: seq[int64]): f64 =
  if data.len == 0:
    return 0.0

  var sortedData = data
  sortedData.sort()

  let n = sortedData.len
  if n mod 2 == 1:
    return f64(sortedData[n div 2])
  else:
    let mid1 = sortedData[(n div 2) - 1]
    let mid2 = sortedData[n div 2]
    return (mid1 + mid2) / 2

func round(a: f64): int64 =
  int64(math.round(a))

func allCuts(tl: v3, inLen: int64): seq[int64] =
  # Calculate cuts
  let tb = tl.tb
  var clipSpans: seq[(int64, int64)] = @[]

  for clip in tl.a[0]:
    let effectGroup = tl.effects[clip.effects]
    var speed = 1.0
    for effect in effectGroup:
      if effect.kind in [actSpeed, actVarispeed]:
        speed *= effect.val
    let oldOffset = clip.offset.f64 * speed
    clipSpans.add((round(oldOffset), round(oldOffset + clip.dur.f64)))

  var cutLens: seq[int64] = @[]
  var i = 0
  while i < len(clipSpans) - 1:
    if i == 0 and clipSpans[i][0] != 0:
      cutLens.add(clipSpans[i][0])

    let cutLen = clipSpans[i + 1][0] - clipSpans[i][1]
    if cutLen > 0:
      cutLens.add(cutLen)
    i += 1

  if clipSpans.len > 0 and clipSpans[^1][1] < round(inLen / tb):
    let trailingCut = inLen - clipSpans[^1][1]
    if trailingCut > 0:
      cutLens.add(trailingCut)

  return cutLens


proc preview*(tl: var v3) =
  clearline()

  var inputLength: int64 = 0
  for src in tl.uniqueSources:
    let container = av.open(src[])
    let mediaLength: AVRational = container.mediaLength()
    inputLength += round((mediaLength * tl.tb).f64).int64

  let outputLength = tl.len
  let diff = outputLength - inputLength
  let tb: f64 = tl.tb.f64

  stdout.write("\nlength:\n")
  echo timeFrame("input", inputLength, tb, "100.0%")

  if inputLength != 0:
    let outputPercent = &"{round((outputLength.f64 / inputLength.f64) * 100, 2)}%"
    echo timeFrame("output", outputLength, tb, outputPercent)
    echo timeFrame("diff", diff, tb, &"{round((diff.f64 / inputLength.f64) * 100, 2)}%")
  else:
    echo timeFrame("output", outputLength, tb, "0.0%")
    echo timeFrame("diff", diff, tb, "0.0%")

  var clipLens: seq[int64] = @[]
  if tl.a.len == 0:
    if tl.v.len != 0:
      tl.a.add move(tl.v[0])
    else:
      tl.a.add @[]

  for clip in tl.a[0]:
    clipLens.add clip.dur

  stdout.write("clips:\n - amount:    " & $clipLens.len & "\n")
  if clipLens.len > 0:
    echo timeFrame("smallest", min(clipLens), tb)
    echo timeFrame("largest", max(clipLens), tb)
  if clipLens.len > 1:
    echo timeFrame("median", median(clipLens), tb)
    echo timeFrame("average", mean(clipLens), tb)

  let cutLens = allCuts(tl, inputLength)
  stdout.write("cuts:\n - amount:    " & $cutLens.len & "\n")
  if len(cutLens) > 0:
    echo timeFrame("smallest", min(cutLens), tb)
    echo timeFrame("largest", max(cutLens), tb)
  if len(cutLens) > 1:
    echo timeFrame("median", median(cutLens), tb)
    echo timeFrame("average", mean(cutLens), tb)

  stdout.write("\n")
  stdout.flushFile()
