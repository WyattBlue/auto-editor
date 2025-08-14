import std/sets
import std/[strutils, strformat]
import std/algorithm
from std/math import round

import av
import ffmpeg
import timeline
import log

proc timeFrame(title: string, ticks: int, tb: float, per: string = ""): string =
  let tc = toTimecode(ticks.float64 / tb, Code.ass)
  let tp = (if tc.startsWith("-"): 9 else: 10)
  let tcp = (if tc.startsWith("-"): 12 else: 11)
  let endStr = (if per == "": "" else: " " & alignLeft(per, 7))

  let titlePart = alignLeft(title & ":", tp)
  let tcPart = alignLeft(tc, tcp)
  let ticksPart = alignLeft(fmt"({ticks})", 6)

  return fmt" - {titlePart} {tcPart} {ticksPart}{endStr}"

proc timeFrame(title: string, ticks: float, tb: float, per: string = ""): string =
  let tc = toTimecode(ticks / tb, Code.ass)
  let tp = (if tc.startsWith("-"): 9 else: 10)
  let tcp = (if tc.startsWith("-"): 12 else: 11)
  let endStr = (if per == "": "" else: " " & alignLeft(per, 7))

  let titlePart = alignLeft(title & ":", tp)
  let tcPart = alignLeft(tc, tcp)
  let ticksPart = alignLeft(fmt"({ticks:.2f})", 6)

  return fmt" - {titlePart} {tcPart} {ticksPart}{endStr}"


func mean(data: seq[int]): float =
  var sum = 0
  for d in data:
    sum += d

  return sum / data.len

func median(data: seq[int]): float =
  if data.len == 0:
    return 0.0

  var sortedData = data
  sortedData.sort()

  let n = sortedData.len
  if n mod 2 == 1:
    return float(sortedData[n div 2])
  else:
    let mid1 = sortedData[(n div 2) - 1]
    let mid2 = sortedData[n div 2]
    return (mid1 + mid2) / 2


func round(a: float): int =
  int(math.round(a))

func allCuts(tl: v3, inLen: int): seq[int] =
  # Calculate cuts
  let tb = tl.tb
  var clipSpans: seq[(int, int)] = @[]

  for clip in tl.a[0].clips:
    let oldOffset = clip.offset.float64 * clip.speed
    clipSpans.add((round(oldOffset), round(oldOffset + clip.dur.float64)))

  var cutLens: seq[int] = @[]
  var i = 0
  while i < len(clipSpans) - 1:
    if i == 0 and clipSpans[i][0] != 0:
      cutLens.add(clipSpans[i][0])

    cutLens.add(clipSpans[i + 1][0] - clipSpans[i][1])
    i += 1

  if clipSpans.len > 0 and clipSpans[^1][1] < round(inLen / tb):
    cutLens.add(inLen - clipSpans[^1][1])

  return cutLens


proc preview*(tl: v3) =
  conwrite("")

  var inputLength = 0
  for src in tl.uniqueSources:
    let container = av.open(src[])
    let mediaLength: AVRational = container.mediaLength()
    inputLength += round((mediaLength * tl.tb).float64).int

  let outputLength = tl.len
  let diff = outputLength - inputLength
  let tb = tl.tb.float64

  stdout.write("\nlength:\n")
  echo timeFrame("input", inputLength, tb, "100.0%")

  if inputLength != 0:
    let outputPercent = fmt"{round((outputLength / inputLength) * 100, 2)}%"
    echo timeFrame("output", outputLength, tb, outputPercent)
    echo timeFrame("diff", diff, tb, fmt"{round((diff / inputLength) * 100, 2)}%")
  else:
    echo timeFrame("output", outputLength, tb, "0.0%")
    echo timeFrame("diff", diff, tb, "0.0%")

  var clipLens: seq[int] = @[]
  for clip in tl.a[0].clips:
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
