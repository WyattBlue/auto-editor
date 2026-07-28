import std/[algorithm, strformat, strutils]
from std/math import round

import ../[action, av, ffmpeg, log, timeline]
import ../util/rational
import ./[h264, hevc, smart, vp9av1]

func frameAt(ts: int64, tb, fps: AVRational): int64 =
  int64(round(float(ts) * float(tb) * float(fps)))

func encoderSupports(encoder: ptr AVCodec, format: AVPixelFormat): bool =
  if encoder == nil:
    return false
  if encoder.pix_fmts == nil:
    return true
  var i = 0
  while encoder.pix_fmts[i] != AV_PIX_FMT_NONE:
    if encoder.pix_fmts[i] == format:
      return true
    inc i
  false

func supportsContainer(codecId: AVCodecID, formatName: string): bool =
  let isWebm = formatName == "webm"
  let isMatroska = "matroska" in formatName
  case codecId
  of ID_H264, ID_HEVC:
    formatName.isIsoBmff or isMatroska
  of ID_VP9:
    isWebm
  of ID_AV1:
    isWebm or isMatroska or formatName.isIsoBmff
  else:
    false

func supportsStream(stream: ptr AVStream, encoder: ptr AVCodec,
    codecId: AVCodecID): bool =
  let pixelFormat = AVPixelFormat(stream.codecpar.format)
  case codecId
  of ID_H264:
    stream.h264SupportsPartialLossless
  of ID_HEVC:
    stream.hevcSupportsPartialLossless(encoder)
  of ID_VP9:
    pixelFormat == AV_PIX_FMT_YUV420P
  of ID_AV1:
    encoder.encoderSupports(pixelFormat)
  else:
    false

func packetIsCopyBoundary(codecId: AVCodecID, data: ptr uint8, size: int): bool =
  case codecId
  of ID_H264:
    h264IsCopyBoundary(data, size)
  of ID_HEVC:
    hevcIsCopyBoundary(data, size)
  of ID_VP9:
    vp9IsKeyframe(data, size)
  of ID_AV1:
    true
  else:
    false

func codecLabel(codecId: AVCodecID): string =
  if codecId == ID_H264: "H.264" else: ($avcodec_get_name(codecId)).toUpperAscii

proc scanGops(input: InputContainer, stream: ptr AVStream, fps: AVRational,
    codecId: AVCodecID): tuple[keyframes: seq[int64], sourceEnd: int64] =
  while av_read_frame(input.formatContext, input.packet) >= 0:
    let packet = input.packet
    if packet.stream_index == stream.index and packet.pts != AV_NOPTS_VALUE:
      let frame = frameAt(packet.pts, stream.time_base, fps)
      result.sourceEnd = max(result.sourceEnd, frame + 1)
      if (packet.flags and AV_PKT_FLAG_KEY) != 0 and
          packetIsCopyBoundary(codecId, packet.data, packet.size.int):
        result.keyframes.add frame
    av_packet_unref(packet)

  result.keyframes.sort()
  var write = 0
  for keyframe in result.keyframes:
    if write == 0 or result.keyframes[write - 1] != keyframe:
      result.keyframes[write] = keyframe
      inc write
  result.keyframes.setLen(write)

proc partialLosslessPlan*(output: OutputContainer, tl: v3, args: mainArgs,
    codecId: AVCodecID): seq[SmartSpan] =
  if args.noPartialLossless or args.scale != 1.0 or args.pixFmt != "" or
      args.vprofile != "":
    return

  let encoder = initCodec(args.videoCodec)
  if encoder == nil or encoder.id != codecId:
    return
  let formatName = $output.formatCtx.oformat.name
  if not codecId.supportsContainer(formatName):
    return
  if tl.v.len != 1 or tl.v[0].len == 0:
    return

  let source = tl.v[0][0].src
  if source == nil:
    return
  var expectedStart = 0'i64
  for clip in tl.v[0]:
    if clip.src != source or clip.stream != 0 or clip.start != expectedStart or
        not tl.effects[clip.effects].isEmpty:
      return
    expectedStart = clip.start + clip.dur
  if expectedStart != tl.len:
    return

  var input = try: av.open(source[])
              except IOError: return
  defer: input.close()
  if input.video.len == 0:
    return

  let stream = input.video[0]
  if stream.codecpar.codec_id != codecId or
      stream.codecpar.width != tl.res[0] or
      stream.codecpar.height != tl.res[1] or
      not stream.supportsStream(encoder, codecId) or
      not stream.avg_frame_rate.isValid or stream.avg_frame_rate != tl.tb:
    return

  let (keyframes, sourceEnd) = scanGops(input, stream, tl.tb, codecId)
  for clip in tl.v[0]:
    if clip.offset < 0 or clip.offset >= sourceEnd or
        clip.offset + clip.dur > sourceEnd + 1:
      return

  let plan = smartRenderPlan(tl.v[0], keyframes, sourceEnd)
  let stats = smartPlanStats(plan)
  let averageGop = averageGopFrames(keyframes, sourceEnd)
  if not smartPlanIsWorthwhile(stats, tl.len, sourceEnd, averageGop):
    let label = codecId.codecLabel
    debug &"Skipping {label} partial-lossless rendering: copying {stats.copiedFrames}/{tl.len} frames across {plan.len} spans would not offset {stats.encodeRuns} encoder runs"
    return
  return plan
