import std/algorithm
from std/math import round

import ../[av, ffmpeg, log, timeline]
import ../util/rational

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
      result.addSpan(ssEncode, cursor, keyframe, clip.start + cursor - clip.offset)
      result.addSpan(ssCopy, keyframe, gopEnd, clip.start + keyframe - clip.offset)
      cursor = gopEnd
      inc i
    result.addSpan(ssEncode, cursor, clipSrcEnd, clip.start + cursor - clip.offset)

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
  if args.gop >= 1:
    encoder.gop_size = args.gop.cint

func frameAt*(ts: int64, tb, fps: AVRational): int64 =
  int64(round(float(ts) * float(tb) * float(fps)))

proc encoderSupports*(encoder: ptr AVCodec, format: AVPixelFormat): bool =
  if encoder == nil:
    return false
  let pixFmts = encoder.supportedPixFmts
  if pixFmts == nil:
    return true
  var i = 0
  while pixFmts[i] != AV_PIX_FMT_NONE:
    if pixFmts[i] == format:
      return true
    inc i
  false

# --- Annex B <-> four-byte-length NAL conversion, shared by H.264 and HEVC ---

func startCodeLen*(data: ptr UncheckedArray[uint8], size, pos: int): int =
  if pos + 3 <= size and data[pos] == 0 and data[pos + 1] == 0:
    if data[pos + 2] == 1:
      return 3
    if pos + 4 <= size and data[pos + 2] == 0 and data[pos + 3] == 1:
      return 4
  0

proc appendNal*(result: var seq[uint8], data: ptr UncheckedArray[uint8],
    first, last: int) =
  let size = last - first
  if size <= 0:
    return
  result.add uint8(size shr 24)
  result.add uint8(size shr 16)
  result.add uint8(size shr 8)
  result.add uint8(size)
  for i in first..<last:
    result.add data[i]

proc annexBToLengthPrefixed*(data: ptr uint8, size: int): seq[uint8] =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  var pos = 0
  while pos < size and startCodeLen(bytes, size, pos) == 0:
    inc pos
  if pos == size:
    result.setLen(size)
    if size > 0:
      copyMem(addr result[0], data, size)
    return

  while pos < size:
    let codeLen = startCodeLen(bytes, size, pos)
    if codeLen == 0:
      inc pos
      continue
    let nalStart = pos + codeLen
    var next = nalStart
    while next < size and startCodeLen(bytes, size, next) == 0:
      inc next
    result.appendNal(bytes, nalStart, next)
    pos = next

proc normalizeLengthPrefixed*(packet: ptr AVPacket,
    parameterSets: openArray[uint8], label: string) =
  ## Rewrite an Annex B packet in place as four-byte-length NALs, optionally
  ## prefixed with `parameterSets`, preserving the packet's timing fields.
  let bytes = cast[ptr UncheckedArray[uint8]](packet.data)
  var start = 0
  while start < packet.size.int and
      startCodeLen(bytes, packet.size.int, start) == 0:
    inc start
  if start == packet.size.int and parameterSets.len == 0:
    return

  let payload = annexBToLengthPrefixed(packet.data, packet.size.int)
  let pts = packet.pts
  let dts = packet.dts
  let duration = packet.duration
  let flags = packet.flags
  let streamIndex = packet.stream_index
  let timeBase = packet.time_base
  av_packet_unref(packet)
  let total = parameterSets.len + payload.len
  if av_new_packet(packet, total.cint) < 0:
    error "Could not allocate normalized " & label & " packet"
  if parameterSets.len > 0:
    copyMem(packet.data, unsafeAddr parameterSets[0], parameterSets.len)
  if payload.len > 0:
    copyMem(cast[pointer](cast[int](packet.data) + parameterSets.len),
      unsafeAddr payload[0], payload.len)
  packet.pts = pts
  packet.dts = dts
  packet.duration = duration
  packet.flags = flags
  packet.stream_index = streamIndex
  packet.time_base = timeBase
