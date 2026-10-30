import std/[math, options, strformat]

import ../[av, cache, ffmpeg, log]
import ../util/[bar, rational]
import ../lib/dnorm16
import ./motion # reuse the generic VideoProcessor + videoPipeline frame pump

const AV_PIX_FMT_FLAG_PAL = 1'u64 shl 1

func lumaIsPlane(fmt: AVPixelFormat): bool =
  ## 8-bit luma alone in the first plane, as in yuv420p, nv12 and gray.
  let d = av_pix_fmt_desc_get(fmt)
  d != nil and d.nb_components > 0 and
    (d.flags and (AV_PIX_FMT_FLAG_RGB or AV_PIX_FMT_FLAG_PAL or
    AV_PIX_FMT_FLAG_BITSTREAM)) == 0 and
    d.comp[0].plane == 0 and d.comp[0].step == 1 and d.comp[0].offset == 0 and
    d.comp[0].shift == 0 and d.comp[0].depth == 8

proc blackLumaMax(fmt: AVPixelFormat, range: AVColorRange, thres: uint8): int =
  ## The highest luma that swscale turns into gray at or below `thres`, or -1
  ## if none. -2 when gray isn't a rising function of luma alone, so luma can't
  ## stand in for it. Found by converting a frame holding every luma value.
  const w = 256
  const h = 8 # a dithered conversion would vary by row
  var src = av_frame_alloc()
  var dst = av_frame_alloc()
  var sws = sws_alloc_context()
  defer:
    av_frame_free(addr src)
    av_frame_free(addr dst)
    sws_free_context(addr sws)
  if src == nil or dst == nil or sws == nil:
    error "Could not allocate luma probe"
  src.format = fmt.cint
  src.width = w
  src.height = h
  src.color_range = range
  src.colorspace = AVColorSpace(2) # AVCOL_SPC_UNSPECIFIED, like videoPipeline
  if av_frame_get_buffer(src, 0) < 0:
    error "Could not allocate luma probe"
  let vsub = av_pix_fmt_desc_get(fmt).log2_chroma_h.int
  for p in 0 ..< src.data.len:
    if src.data[p] == nil: continue
    # Other planes get neutral chroma; fill no more rows than a subsampled
    # plane has.
    let rows = (if p == 0: h else: (h + (1 shl vsub) - 1) shr vsub)
    for y in 0 ..< rows:
      let row = cast[ptr UncheckedArray[uint8]](cast[int](src.data[p]) +
        y * src.linesize[p].int)
      for x in 0 ..< src.linesize[p].int:
        row[x] = (if p == 0: uint8(min(x, 255)) else: 128'u8)
  dst.format = AV_PIX_FMT_GRAY8.cint
  dst.width = w
  dst.height = h
  if sws_scale_frame(sws, dst, src) < 0:
    return -2

  let first = cast[ptr UncheckedArray[uint8]](dst.data[0])
  result = -1
  for x in 0 ..< w:
    if x > 0 and first[x] < first[x - 1]: return -2
    for y in 1 ..< h:
      let row = cast[ptr UncheckedArray[uint8]](cast[int](dst.data[0]) +
        y * dst.linesize[0].int)
      if row[x] != first[x]: return -2
    if first[x] <= thres: result = x

iterator blackness*(processor: var VideoProcessor, pixelBlack: float32): Unorm16 =
  ## Per-frame ratio of "black" pixels (gray luma <= pixelBlack). Mirrors
  ## `motionness`: one value per timebase index, filling gaps between source frames.
  var prevIndex: int64 = -1
  let blackThres = uint8(round(clamp(pixelBlack, 0.0'f32, 1.0'f32) * 255.0'f32))

  # Converting each frame to gray is most of the work. When luma has its own
  # plane, count the luma at or below the value that becomes the threshold.
  let fmt = processor.codecCtx.pix_fmt
  var lumaRange = processor.codecCtx.color_range
  var lumaMax =
    if fmt.lumaIsPlane: blackLumaMax(fmt, lumaRange, blackThres) else: -2
  let direct = lumaMax != -2

  let filter = (if direct: "format=" & $fmt else: "format=gray")
  for frame in processor.videoPipeline(filter):
    let frameTime = (frame.pts * processor.formatCtx.streams[
        processor.videoIndex].time_base).float64
    let index = round(frameTime * processor.tb.float64).int64

    if direct and frame.color_range != lumaRange:
      lumaRange = frame.color_range
      lumaMax = blackLumaMax(fmt, lumaRange, blackThres)
      if lumaMax == -2:
        error "blackdetect: can't read gray from luma at this color range"
    let limit = (if direct: lumaMax else: blackThres.int)

    let w = frame.width.int
    let h = frame.height.int
    let stride = frame.linesize[0].int
    let data = cast[ptr UncheckedArray[uint8]](frame.data[0])

    var blackCount = 0
    if limit >= 0:
      let lim = uint8(limit)
      for y in 0 ..< h:
        let rowOff = y * stride
        for x in 0 ..< w:
          blackCount += int(data[rowOff + x] <= lim)

    let value = toUnorm16(float32(blackCount) / float32(w * h))
    for i in 0 ..< index - prevIndex:
      yield value
    prevIndex = index

proc blackdetect*(bar: Bar, container: InputContainer, path: string, tb: AVRational,
    stream: int16, pixelBlack: float32): seq[Unorm16] =
  let cacheArgs = &"{stream},{pixelBlack}"
  if not noCache:
    let cacheData = readCache[Unorm16](path, tb, "blackdetect", cacheArgs)
    if cacheData.isSome:
      return cacheData.get()

  if stream < 0 or stream >= container.video.len:
    error &"blackdetect: video stream '{stream}' does not exist."

  let videoStream: ptr AVStream = container.video[stream]
  # Rewind so a shared container can be re-read for additional streams.
  container.seek(0)
  let errorsBefore = decodeErrors

  var processor = VideoProcessor(formatCtx: container.formatContext,
    codecCtx: initDecoder(videoStream.codecpar), tb: tb,
    videoIndex: videoStream.index)

  let inaccurateDur =
    if videoStream.duration != AV_NOPTS_VALUE and videoStream.time_base.isValid:
      float(videoStream.duration) * float(videoStream.time_base * tb)
    else:
      container.duration * float(tb)
  bar.start(inaccurateDur, "Analyzing blackness")

  var i: float = 0
  for value in processor.blackness(pixelBlack):
    result.add value
    bar.tick(i)
    i += 1

  bar.`end`()

  if not noCache and decodeErrors == errorsBefore:
    writeCache(result, tb, path, "blackdetect", cacheArgs)
