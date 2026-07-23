import std/algorithm

import ../[ffmpeg, log, timeline]

type
  SmartSpanKind* = enum
    ssEncode, ssCopy
  SmartSpan* = object
    kind*: SmartSpanKind
    srcStart*, srcEnd*: int64
    outStart*: int64
  SmartPlanStats* = object
    copiedFrames*, encodedFrames*: int64
    copySpans*, encodeSpans*, encodeRuns*: int

func addSpan(spans: var seq[SmartSpan], kind: SmartSpanKind,
    srcStart, srcEnd, outStart: int64) =
  if srcEnd <= srcStart:
    return
  if spans.len > 0:
    let prev = spans[^1]
    let prevLen = prev.srcEnd - prev.srcStart
    if prev.kind == kind and prev.srcEnd == srcStart and
        prev.outStart + prevLen == outStart:
      spans[^1].srcEnd = srcEnd
      return
  spans.add SmartSpan(kind: kind, srcStart: srcStart, srcEnd: srcEnd,
    outStart: outStart)

func smartRenderPlan*(clips: openArray[Clip], keyframes: openArray[int64],
    sourceEnd: int64): seq[SmartSpan] =
  ## Copy only complete GOPs. Partial GOPs touching either side of an edit are
  ## re-encoded so the output still begins and ends on the requested frame.
  for clip in clips:
    let clipSrcEnd = clip.offset + clip.dur
    var cursor = clip.offset
    var i = lowerBound(keyframes, clip.offset)
    while i < keyframes.len:
      let keyframe = keyframes[i]
      if keyframe >= clipSrcEnd:
        break
      let gopEnd = if i + 1 < keyframes.len: keyframes[i + 1] else: sourceEnd
      let finalGopNeedsHold = i + 1 == keyframes.len and clipSrcEnd > sourceEnd
      if gopEnd > clipSrcEnd or gopEnd <= keyframe or finalGopNeedsHold:
        inc i
        continue
      result.addSpan(ssEncode, cursor, keyframe,
        clip.start + cursor - clip.offset)
      result.addSpan(ssCopy, keyframe, gopEnd,
        clip.start + keyframe - clip.offset)
      cursor = gopEnd
      inc i
    result.addSpan(ssEncode, cursor, clipSrcEnd,
      clip.start + cursor - clip.offset)

func smartPlanStats*(spans: openArray[SmartSpan]): SmartPlanStats =
  var inEncodeRun = false
  for span in spans:
    let frames = span.srcEnd - span.srcStart
    case span.kind
    of ssCopy:
      result.copiedFrames += frames
      inc result.copySpans
      inEncodeRun = false
    of ssEncode:
      result.encodedFrames += frames
      inc result.encodeSpans
      if not inEncodeRun:
        inc result.encodeRuns
      inEncodeRun = true

func averageGopFrames*(keyframes: openArray[int64], sourceEnd: int64): int64 =
  var frames, count = 0'i64
  for i, keyframe in keyframes:
    let gopEnd = if i + 1 < keyframes.len: keyframes[i + 1] else: sourceEnd
    if gopEnd > keyframe:
      frames += gopEnd - keyframe
      inc count
  if count == 0:
    return max(sourceEnd, 1)
  return max(frames div count, 1)

func smartPlanIsWorthwhile*(stats: SmartPlanStats, timelineFrames,
    sourceFrames, averageGop: int64): bool =
  ## Estimate work in full-render frame equivalents. Demuxing the source is
  ## substantially cheaper than decoding and encoding it, while restarting an
  ## encoder costs about one GOP of useful work.
  if stats.copiedFrames <= 0 or timelineFrames <= 0:
    return false
  let scanCost = max(sourceFrames, 0) div 32
  let restartCost = int64(stats.encodeRuns) * max(averageGop, 1)
  return stats.encodedFrames + scanCost + restartCost < timelineFrames

proc applyPartialEncoderArgs*(encoder: ptr AVCodecContext, args: mainArgs) =
  if args.videoBitrate >= 0:
    encoder.bit_rate = args.videoBitrate
  if args.crf >= 0:
    discard av_opt_set_int(encoder.priv_data, "crf", args.crf.cint, 0)
  if args.preset != "":
    discard av_opt_set(encoder.priv_data, "preset", cstring(args.preset), 0)
