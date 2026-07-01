import std/[math, options, strformat]

import ../[av, cache, ffmpeg, log]
import ../util/[bar, rational, dnorm16]
import ./motion # reuse the generic VideoProcessor + videoPipeline frame pump

iterator blackness*(processor: var VideoProcessor, pixelBlack: float32): Unorm16 =
  ## Per-frame ratio of "black" pixels (gray luma <= pixelBlack). Mirrors
  ## `motionness`: one value per timebase index, filling gaps between source frames.
  var prevIndex: int64 = -1
  let blackThres = uint8(round(clamp(pixelBlack, 0.0'f32, 1.0'f32) * 255.0'f32))

  for filteredFrame in processor.videoPipeline("format=gray"):
    let frameTime = (filteredFrame.pts * processor.formatCtx.streams[
        processor.videoIndex].time_base).float64
    let index = round(frameTime * processor.tb.float64).int64

    let w = filteredFrame.width.int
    let h = filteredFrame.height.int
    let stride = filteredFrame.linesize[0].int
    let data = cast[ptr UncheckedArray[uint8]](filteredFrame.data[0])

    var blackCount = 0
    for y in 0 ..< h:
      let rowOff = y * stride
      for x in 0 ..< w:
        if data[rowOff + x] <= blackThres:
          inc blackCount

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

  var processor = VideoProcessor(
    formatCtx: container.formatContext,
    codecCtx: initDecoder(videoStream.codecpar),
    tb: tb,
    videoIndex: videoStream.index,
  )

  let inaccurateDur = (
    if videoStream.duration != AV_NOPTS_VALUE and videoStream.time_base.isValid:
      float(videoStream.duration) * float(videoStream.time_base * tb)
    else:
      container.duration * float(tb)
  )
  bar.start(inaccurateDur, "Analyzing blackness")

  var i: float = 0
  for value in processor.blackness(pixelBlack):
    result.add value
    bar.tick(i)
    i += 1

  bar.`end`()

  if not noCache:
    writeCache(result, tb, path, "blackdetect", cacheArgs)
