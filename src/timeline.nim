import std/sets
import std/options
import std/os
import std/tables
from std/math import round

import ffmpeg
import media
import log
import wavutil
import util/color

type v1* = object
  chunks*: seq[(int64, int64, float64)]
  source*: string

type Clip2* = object
  start*: int64
  `end`*: int64
  effect*: uint32

type v2* = object
  source*: string
  tb*: AVRational
  effects*: seq[seq[Action]]
  clips*: seq[Clip2]

type Clip* = object
  src*: ptr string
  start*: int64
  dur*: int64
  offset*: int64
  effects*: uint32  # Reference to global effects in Timeline.
  stream*: int32

type ClipLayer* = object
  lang*: string = "und"
  c*: seq[Clip] = @[]

# Whatever floats your boat
func clips*(layer: ClipLayer): seq[Clip] =
  layer.c

func len*(layer: ClipLayer): int =
  len(layer.c)

type v3* = object
  tb*: AVRational
  bg*: RGBColor
  sr*: cint
  layout*: string
  res*: (int, int)
  v*: seq[ClipLayer]
  a*: seq[ClipLayer]
  s*: seq[ClipLayer]
  effects*: seq[seq[Action]]
  clips2*: Option[seq[Clip2]]  # Optional because tl might be non-linear.


func len*(self: v3): int64 =
  result = 0
  for clips in self.v:
    if len(clips) > 0:
      result = max(result, clips.c[^1].start + clips.c[^1].dur)
  for clips in self.a:
    if len(clips) > 0:
      result = max(result, clips.c[^1].start + clips.c[^1].dur)

func uniqueSources*(self: v3): HashSet[ptr string] =
  for vlayer in self.v:
    for video in vlayer.c:
      result.incl(video.src)

  for alayer in self.a:
    for audio in alayer.c:
      result.incl(audio.src)


func `end`*(self: v3): int64 =
  result = 0
  for vlayer in self.v:
    if vlayer.c.len > 0:
      let v = vlayer.c[^1]
      result = max(result, v.start + v.dur)
  for alayer in self.a:
    if alayer.c.len > 0:
      let a = alayer.c[^1]
      result = max(result, a.start + a.dur)

func timelineIsEmpty(self: v3): bool =
  (self.v.len == 0 or self.v[0].len == 0) and (self.a.len == 0 or self.a[0].len == 0)

proc chunkify(arr: seq[int], effects: seq[seq[Action]]): seq[(int64, int64, int, seq[Action])] =
  if arr.len == 0:
    return @[]

  var start: int64 = 0
  var j: int64 = 1
  while j < arr.len:
    if arr[j] != arr[j - 1]:
      result.add (start, j, arr[j-1], effects[arr[j - 1]])
      start = j
    inc j
  result.add (start, arr.len.int64, arr[j-1], effects[arr[j - 1]])

proc initLinearTimeline*(src: ptr string, tb: AvRational, bg: RGBColor, mi: MediaInfo, effects: seq[seq[Action]], actionIndex: seq[int]): v3 =
  var clips: seq[Clip] = @[]
  var i: int64 = 0
  var start: int64 = 0
  var dur: int64
  var offset: int64

  let pseudoChunks = chunkify(actionIndex, effects)
  var clips2: seq[Clip2]

  for chunk in pseudoChunks:
    let actionGroup = chunk[3]
    var speed = 1.0
    for action in actionGroup:
      if action.kind in [actSpeed, actVarispeed]:
        speed *= action.val
      elif action.kind == actCut:
        speed = 99999.0
        break

    let effectIndex = chunk[2]
    if effectIndex > int(high(uint32)):
      error "'Number of actions' limit for timeline reached."
    let e = uint32(effectIndex)

    # Always add to clips2, even for cuts (no holes)
    clips2.add Clip2(start: chunk[0], `end`: chunk[1], effect: e)

    # Make clips (skip cuts for actual output clips)
    if speed != 99999.0:
      dur = int64(round(float64(chunk[1] - chunk[0]) / speed))
      if dur == 0:
        continue

      offset = int64(float64(chunk[0]) / speed)

      if not (clips.len > 0 and clips[^1].start == start):
        clips.add Clip(src: src, start: start, dur: dur, offset: offset, effects: e)

      start += dur
      i += 1

  var vspace: seq[ClipLayer] = @[]
  var aspace: seq[ClipLayer] = @[]
  var sspace: seq[ClipLayer] = @[]

  if mi.v.len > 0:
    var vlayer = ClipLayer(lang: mi.v[0].lang, c: @[])
    for clip in clips:
      var videoClip = clip
      videoClip.stream = 0
      vlayer.c.add(videoClip)
    vspace.add(vlayer)

  for i in 0 ..< mi.a.len:
    var alayer = ClipLayer(lang: mi.a[i].lang, c: @[])
    for clip in clips:
      var audioClip = clip
      audioClip.stream = i.int32
      alayer.c.add(audioClip)
    aspace.add(alayer)

  for i in 0 ..< mi.s.len:
    var slayer = ClipLayer(lang: mi.s[i].lang, c: @[])
    for clip in clips:
      var subtitleClip = clip
      subtitleClip.stream = i.int32
      slayer.c.add(subtitleClip)
    sspace.add(slayer)

  result = v3(tb: tb, v: vspace, a: aspace, s: sspace, bg: bg, effects: effects)

  if result.timelineIsEmpty:
    error "Timeline is empty, nothing to do."

  result.clips2 = some(clips2)
  result.res = mi.getRes()
  result.sr = 48000
  result.layout = "stereo"
  if mi.a.len > 0:
    result.sr = mi.a[0].sampleRate
    result.layout = mi.a[0].layout


proc toNonLinear*(src: ptr string, tb: AvRational, bg: RGBColor, mi: MediaInfo,
    chunks: seq[(int64, int64, float64)]): v3 =
  var clips: seq[Clip] = @[]
  var clips2: seq[Clip2] = @[]
  var effects: seq[seq[Action]] = @[]
  var i: int64 = 0
  var start: int64 = 0
  var dur: int64
  var offset: int64

  for chunk in chunks:
    if chunk[2] > 0.0 and chunk[2] < 99999.0:
      dur = int64(round(float64(chunk[1] - chunk[0]) / chunk[2]))
      if dur == 0:
        continue

      offset = int64(float64(chunk[0]) / chunk[2])

      if not (clips.len > 0 and clips[^1].start == start):
        var effectIndex: int
        if chunk[2] == 1.0:
          let emptySeq: seq[Action] = @[]
          effectIndex = effects.find(emptySeq)
          if effectIndex == -1:
            effects.add emptySeq
            effectIndex = effects.len - 1
        else:
          effectIndex = effects.find(@[Action(kind: actSpeed, val: chunk[2])])
          if effectIndex == -1:
            effects.add @[Action(kind: actSpeed, val: chunk[2])]
            effectIndex = effects.len - 1

        if effectIndex > int(high(uint32)):
          error "'Number of actions' limit for timeline reached."
        let e = uint32(effectIndex)
        clips.add Clip(src: src, start: start, dur: dur, offset: offset, effects: e)
        clips2.add Clip2(start: chunk[0], `end`: chunk[1], effect: e)

      start += dur
      i += 1

  var vspace: seq[ClipLayer] = @[]
  var aspace: seq[ClipLayer] = @[]
  var sspace: seq[ClipLayer] = @[]

  if mi.v.len > 0:
    var vlayer = ClipLayer(lang: mi.v[0].lang, c: @[])
    for clip in clips:
      var videoClip = clip
      videoClip.stream = 0
      vlayer.c.add(videoClip)
    vspace.add(vlayer)

  for i in 0 ..< mi.a.len:
    var alayer = ClipLayer(lang: mi.a[i].lang, c: @[])
    for clip in clips:
      var audioClip = clip
      audioClip.stream = i.int32
      alayer.c.add(audioClip)
    aspace.add(alayer)

  for i in 0 ..< mi.s.len:
    var slayer = ClipLayer(lang: mi.s[i].lang, c: @[])
    for clip in clips:
      var subtitleClip = clip
      subtitleClip.stream = i.int32
      slayer.c.add(subtitleClip)
    sspace.add(slayer)

  result = v3(tb: tb, v: vspace, a: aspace, s: sspace, bg: bg, clips2: some(clips2))
  result.effects = effects

  if result.timelineIsEmpty:
    error "Timeline is empty, nothing to do."

  result.res = mi.getRes()
  result.sr = 48000
  result.layout = "stereo"
  if mi.a.len > 0:
    result.sr = mi.a[0].sampleRate
    result.layout = mi.a[0].layout


proc toNonLinear2*(src: ptr string, tb: AVRational, bg: RGBColor, mi: MediaInfo,
  clips2: seq[Clip2], effects: seq[seq[Action]]): v3 =
  var clips: seq[Clip] = @[]
  var start: int64 = 0
  var dur: int64
  var offset: int64

  for clip2 in clips2:
    let effectGroup = effects[clip2.effect]
    var isCut = false
    var speed = 1.0

    for effect in effectGroup:
      if effect.kind == actCut:
        isCut = true
        break
      elif effect.kind == actSpeed or effect.kind == actVarispeed:
        speed *= effect.val

    if isCut:
      continue

    dur = int64(round(float64(clip2.`end` - clip2.start) / speed))
    if dur == 0:
      continue

    offset = int64(float64(clip2.start) / speed)
    clips.add(Clip(src: src, start: start, dur: dur, offset: offset, effects: clip2.effect))

    start += dur

  var vspace: seq[ClipLayer] = @[]
  var aspace: seq[ClipLayer] = @[]
  var sspace: seq[ClipLayer] = @[]

  if mi.v.len > 0:
    var vlayer = ClipLayer(lang: mi.v[0].lang, c: @[])
    for clip in clips:
      var videoClip = clip
      videoClip.stream = 0
      vlayer.c.add(videoClip)
    vspace.add(vlayer)

  for i in 0 ..< mi.a.len:
    var alayer = ClipLayer(lang: mi.a[i].lang, c: @[])
    for clip in clips:
      var audioClip = clip
      audioClip.stream = i.int32
      alayer.c.add(audioClip)
    aspace.add(alayer)

  for i in 0 ..< mi.s.len:
    var slayer = ClipLayer(lang: mi.s[i].lang, c: @[])
    for clip in clips:
      var subtitleClip = clip
      subtitleClip.stream = i.int32
      slayer.c.add(subtitleClip)
    sspace.add(slayer)

  result = v3(tb: tb, v: vspace, a: aspace, s: sspace, bg: bg, clips2: some(clips2))
  result.effects = effects

  if result.timelineIsEmpty:
    error "Timeline is empty, nothing to do."

  result.res = mi.getRes()
  result.sr = 48000
  result.layout = "stereo"
  if mi.a.len > 0:
    result.sr = mi.a[0].sampleRate
    result.layout = mi.a[0].layout


proc applyArgs*(tl: var v3, args: mainArgs) =
  if args.sampleRate != -1:
    tl.sr = args.sampleRate
  if args.resolution[0] != 0:
    tl.res = args.resolution
  if args.audioLayout != "":
    tl.layout = args.audioLayout
  if args.frameRate != AVRational(num: 0, den: 0):
    tl.tb = args.frameRate

func stem(path: string): string =
  splitFile(path).name

func makeSaneTimebase*(tb: AVRational): AVRational =
  let tbFloat = round(tb.float64, 2)

  let ntsc60 = AVRational(num: 60000, den: 1001)
  let ntsc = AVRational(num: 30000, den: 1001)
  let filmNtsc = AVRational(num: 24000, den: 1001)

  if tbFloat == round(ntsc60.float64, 2):
    return ntsc60
  if tbFloat == round(ntsc.float64, 2):
    return ntsc
  if tbFloat == round(filmNtsc.float64, 2):
    return filmNtsc
  return av_d2q(tbFloat, 1000000)

proc setStreamTo0*(tl: var v3, interner: var StringInterner) =
  var dirExists = false
  var cache = initTable[string, MediaInfo]()

  proc makeTrack(i: int64, path: string): MediaInfo =
    let folder: string = path.parentDir / (path.stem & "_tracks")
    if not dirExists:
      try:
        createDir(folder)
      except OSError:
        removeDir(folder)
        createDir(folder)
      dirExists = true

    let newtrack: string = folder / (path.stem & "_" & $i & ".wav")
    if newtrack notin cache:
      transcodeAudio(path, newtrack, i)
      cache[newtrack] = initMediaInfo(newtrack)
    return cache[newtrack]

  for layer in tl.a.mitems:
    for clip in layer.c.mitems:
      if clip.stream > 0:
        let mi = makeTrack(clip.stream, clip.src[])
        clip.src = interner.intern(mi.path)
        clip.stream = 0
