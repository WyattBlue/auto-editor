## The edit rendered frame by frame for a player, as an export would render
## it (effects, overlays, transitions, every track composited and mixed),
## with nothing encoded.

import std/[atomics, math, sequtils]

import ../[action, av, conductor, ffmpeg, log, timeline]
import ../util/[bar, rational]
import ./[audio, format, video]

type PreviewRender* = ref object
  ## Video and audio are pulled separately so the caller can keep them in
  ## step. Single-threaded: drive it from one thread.
  args: mainArgs
  interner: StringInterner
  tl, renderTl: v3
  sourceEffects: int
  cache: MediaCache
  output: OutputContainer
  encoder: ptr AVCodecContext
  video, audio: iterator(): (ptr AVFrame, int64)
  stop: Atomic[bool]
  audioAt: int # samples into the timeline that the next audio starts at
  tb*: AVRational ## the timeline's frame rate
  sampleRate*: int ## audio is interleaved float32 stereo at this rate
  quarterTurns*: int ## clockwise turns to show frames upright, as the output's display matrix says
  sar*: AVRational ## the output's sample aspect ratio; scaled frames don't carry it
  hasVideo*, hasAudio*: bool

proc openPreview*(args: sink mainArgs, startSeconds, scale: float64,
    withAudio = true): PreviewRender =
  ## The edit `args` describes, from `startSeconds` into the result, at
  ## `scale` of the timeline's frame size. Audio comes stereo at the
  ## timeline's rate, without normalization (which measures the whole
  ## timeline first). Owns `args` (its actions are freed on `close`).
  var r = PreviewRender(args: args)
  # ffv1 never encodes; it only settles the pixel format.
  let video = VideoSettings(codec: "ffv1", scale: scale)
  let built = buildTimeline(r.args, AudioSettings(layout: "stereo"), r.interner,
    initBar(BarType.none))
  r.tl = built.tl
  r.cache = newMediaCache()
  r.tl.dropUndecodableAudio(r.cache)
  r.sourceEffects = r.tl.effects.len
  r.renderTl = r.tl.bakeTransitions()
  let tb = r.renderTl.tb
  r.tb = tb
  r.sampleRate = r.renderTl.sr.int
  let start = clamp(int64(round(startSeconds * tb.float64)), 0, max(r.renderTl.len - 1, 0))
  if r.renderTl.v.len > 0 and r.renderTl.v[0].len > 0:
    # Frames come unturned; the export carries the template's display matrix.
    if r.renderTl.templateFile != nil:
      let vids = r.cache.getContainer(r.renderTl.templateFile).video
      if vids.len > 0: r.quarterTurns = quarterTurns(vids[0].codecpar)
    r.output = openWrite("preview.mkv")
    var stream: ptr AVStream
    (r.encoder, stream, r.video) = makeNewVideoFrames(r.output, r.renderTl,
      r.args, video, r.cache, start, addr r.stop)
    r.sar = r.encoder.sample_aspect_ratio
    r.hasVideo = true
  if withAudio and r.renderTl.a.anyIt(it.len > 0):
    let fromSample = audioSampleSpan(start, 0, r.renderTl.sr, tb).start
    r.audio = makeAudioFrames(AV_SAMPLE_FMT_FLT, r.renderTl, 1024,
      toSeq(0 ..< r.renderTl.a.len), Norm(kind: nkNull), r.cache,
      fromSample, addr r.stop)
    r.audioAt = fromSample
    r.hasAudio = true
  r

proc nextVideo*(r: PreviewRender): tuple[frame: ptr AVFrame, seconds: float64] =
  ## The next frame and when it shows, or nil at the end. The frame stays the
  ## render's: it's valid until the next call.
  if not r.hasVideo or finished(r.video): return (nil, 0.0)
  let (frame, index) = r.video()
  if frame == nil or finished(r.video): return (nil, 0.0)
  (frame, (index * r.tb.den).float64 / r.tb.num.float64)

proc nextAudio*(r: PreviewRender): tuple[frame: ptr AVFrame, seconds: float64] =
  ## The next chunk of audio and when it starts, or nil at the end. The
  ## caller frees the frame.
  if not r.hasAudio or finished(r.audio): return (nil, 0.0)
  let (frame, _) = r.audio()
  if frame == nil or finished(r.audio): return (nil, 0.0)
  result = (frame, r.audioAt.float64 / r.sampleRate.float64)
  r.audioAt += frame.nb_samples

proc close*(r: PreviewRender) =
  ## Stop early: each renderer frees what it holds when next resumed.
  r.stop.store(true)
  if r.hasVideo:
    while not finished(r.video): discard r.video()
  if r.hasAudio:
    # Frames already resampled come out first.
    while not finished(r.audio):
      var (frame, _) = r.audio()
      if frame != nil: av_frame_free(addr frame)
  if r.encoder != nil: avcodec_free_context(addr r.encoder)
  if r.output.formatCtx != nil: r.output.abandon()
  for i in r.sourceEffects ..< r.renderTl.effects.len:
    r.renderTl.effects[i].free()
  freeActions(r.args, r.tl)
  if r.cache != nil: r.cache.close()
  r.interner.cleanup()
