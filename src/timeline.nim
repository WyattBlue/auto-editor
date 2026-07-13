import std/[options, os, sets, tables]
from std/math import round, ceil

import ./[action, av, ffmpeg, media, log, wavutil]
import ./util/[color, fun, lang, rational]

type v1* = object
  chunks*: seq[(int64, int64, float64)]
  source*: string
  tb*: AVRational

type Clip2* = object
  start*: int64
  `end`*: int64
  effect*: uint32

type v2* = object
  source*: string
  tb*: AVRational
  effects*: seq[Actions]
  clips*: seq[Clip2]

type Clip* = object
  src*: ptr string
  start*: int64
  dur*: int64
  offset*: int64
  stream*: int16
  effects*: uint32 # Reference to global effects in Timeline.

type v3* = object
  layout*: ref AVChannelLayout
  res*: (int32, int32)
  tb*: AVRational
  bg*: RGBColor
  sr*: cint
  v*: seq[seq[Clip]]
  a*: seq[seq[Clip]]
  s*: seq[seq[Clip]]
  langs*: seq[Lang]   # Video, Audio (flattened).
  effects*: seq[Actions]
  clips2*: seq[Clip2] # Empty when the timeline is non-linear.
  templateFile*: ptr string

func len*(self: v3): int64 =
  result = 0
  for clips in self.v:
    if len(clips) > 0:
      result = max(result, clips[^1].start + clips[^1].dur)
  for clips in self.a:
    if len(clips) > 0:
      result = max(result, clips[^1].start + clips[^1].dur)

func firstSource*(self: v3): ptr string =
  for vlayer in self.v:
    if vlayer.len > 0 and vlayer[0].src != nil:
      return vlayer[0].src
  for alayer in self.a:
    if alayer.len > 0 and alayer[0].src != nil:
      return alayer[0].src
  return nil

func uniqueSources*(self: v3): HashSet[ptr string] =
  for vlayer in self.v:
    for video in vlayer:
      if video.src != nil:
        result.incl(video.src)
  for alayer in self.a:
    for audio in alayer:
      if audio.src != nil:
        result.incl(audio.src)

func timelineIsEmpty(self: v3): bool =
  (self.v.len == 0 or self.v[0].len == 0) and (self.a.len == 0 or self.a[0].len == 0)

func isLinear*(self: v3): bool =
  return self.clips2.len > 0 or self.timelineIsEmpty

proc chunkify(arr: seq[int], effects: seq[Actions]): seq[(int64, int64, int, Actions)] =
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


proc mutHelper(tl: var v3, mi: MediaInfo, clips: seq[Clip]) =
  if mi.v.len > 0:
    var vlayer = newSeqOfCap[Clip](clips.len)
    for clip in clips:
      var videoClip = clip
      videoClip.stream = 0
      vlayer.add videoClip
    tl.v.add vlayer
    tl.langs.add mi.v[0].lang

  for i in 0 ..< mi.a.len:
    var alayer = newSeqOfCap[Clip](clips.len)
    for clip in clips:
      var audioClip = clip
      audioClip.stream = i.int16
      alayer.add audioClip
    tl.a.add alayer
    tl.langs.add mi.a[i].lang

  for i in 0 ..< mi.s.len:
    var slayer = newSeqOfCap[Clip](clips.len)
    for clip in clips:
      var subtitleClip = clip
      subtitleClip.stream = i.int16
      slayer.add subtitleClip
    tl.s.add slayer

  if tl.timelineIsEmpty:
    error "Timeline is empty, nothing to do."

  if mi.a.len > 0:
    tl.sr = mi.a[0].sampleRate
    tl.layout = initLayout(mi.a[0].layout)
  else:
    tl.sr = 48000
    tl.layout = initLayout("stereo")


func clipBounds(startFrame, endFrame: int64, speed: float64): (int64, int64) =
  if round(float64(endFrame - startFrame) / speed) == 0:
    return (0'i64, 0'i64)
  let offset = int64(ceil(float64(startFrame) / speed))
  (offset, int64(ceil(float64(endFrame) / speed)) - offset)

proc linearClips(src: ptr string, effects: seq[Actions], actionIndex: seq[int],
    start: int64): tuple[clips: seq[Clip], clips2: seq[Clip2]] =
  var timelineStart = start
  for chunk in chunkify(actionIndex, effects):
    let actionGroup = chunk[3]
    var speed = 1.0
    if actionGroup.isCut:
      speed = 99999.0
    else:
      for action in actionGroup:
        if action.kind in [actSpeed, actVarispeed]:
          speed *= action.val

    let effectIndex = chunk[2]
    if effectIndex > int64(high(uint32)):
      error "'Number of actions' limit for timeline reached."
    let e = uint32(effectIndex)

    result.clips2.add Clip2(start: chunk[0], `end`: chunk[1], effect: e)

    if speed != 99999.0:
      let (offset, dur) = clipBounds(chunk[0], chunk[1], speed)
      if dur == 0:
        continue

      result.clips.add Clip(src: src, start: timelineStart, dur: dur,
        offset: offset, effects: e)
      timelineStart += dur

proc initLinearTimeline*(src: ptr string, tb: AVRational, bg: RGBColor,
    mi: MediaInfo,
  effects: seq[Actions], actionIndex: seq[int]): v3 =
  let built = linearClips(src, effects, actionIndex, 0)

  result = v3(tb: tb, bg: bg, effects: effects, clips2: built.clips2,
      res: mi.getRes(),
    templateFile: src)
  mutHelper(result, mi, built.clips)

proc appendLinearTimeline*(tl: var v3, src: ptr string, mi: MediaInfo,
    actionIndex: seq[int]) =
  let built = linearClips(src, tl.effects, actionIndex, tl.len)
  tl.clips2.add built.clips2

  if mi.v.len > 0:
    if tl.v.len == 0:
      tl.v.add @[]
      tl.langs.insert(mi.v[0].lang, 0)
    for clip in built.clips:
      var videoClip = clip
      videoClip.stream = 0
      tl.v[0].add videoClip

  for i in 0 ..< mi.a.len:
    if tl.a.len <= i:
      tl.a.add @[]
      tl.langs.add mi.a[i].lang
    for clip in built.clips:
      var audioClip = clip
      audioClip.stream = i.int16
      tl.a[i].add audioClip

  for i in 0 ..< mi.s.len:
    while tl.s.len <= i:
      tl.s.add @[]
    for clip in built.clips:
      var subtitleClip = clip
      subtitleClip.stream = i.int16
      tl.s[i].add subtitleClip

proc initNonLinear(src: ptr string, tb: AVRational, mi: MediaInfo,
    clips2: seq[Clip2], effects: seq[Actions]): v3 =
  var clips: seq[Clip] = @[]
  var start: int64 = 0

  for clip2 in clips2:
    let effectGroup = effects[clip2.effect]
    if effectGroup.isCut:
      continue
    var speed = 1.0
    for effect in effectGroup:
      if effect.kind == actSpeed or effect.kind == actVarispeed:
        speed *= effect.val

    let (offset, dur) = clipBounds(clip2.start, clip2.`end`, speed)
    if dur == 0:
      continue

    clips.add(Clip(src: src, start: start, dur: dur, offset: offset,
        effects: clip2.effect))

    start += dur

  result = v3(tb: tb, effects: effects, clips2: clips2, templateFile: src)
  result.res = mi.getRes()
  mutHelper(result, mi, clips)

proc toNonLinear*(src: ptr string, tb: AVRational, mi: MediaInfo,
    chunks: seq[(int64, int64, float64)]): v3 {.raises: [].} =
  var clips2: seq[Clip2] = @[]
  var effects: seq[Actions] = @[]

  for chunk in chunks:
    if chunk[2] > 0.0 and chunk[2] < 99999.0:
      let (_, dur) = clipBounds(chunk[0], chunk[1], chunk[2])
      if dur == 0:
        continue

      let action = if chunk[2] == 1.0:
          aNil
        else:
          try: newActions([Action(kind: actSpeed, val: chunk[2].float32)])
          except ActionParseError: error "Too many actions"
      var effectIndex = effects.find(action)
      if effectIndex == -1:
        effects.add action
        effectIndex = effects.len - 1
      if effectIndex > int64(high(uint32)):
        error "'Number of actions' limit for timeline reached."
      clips2.add Clip2(start: chunk[0], `end`: chunk[1], effect: uint32(effectIndex))

  initNonLinear(src, tb, mi, clips2, effects)

proc toNonLinear2*(src: ptr string, tb: AVRational, mi: MediaInfo,
  clips2: seq[Clip2], effects: seq[Actions]): v3 =
  initNonLinear(src, tb, mi, clips2, effects)

proc applyArgs*(tl: var v3, args: mainArgs) =
  if args.sampleRate != -1:
    tl.sr = args.sampleRate
  if args.resolution[0] != 0:
    tl.res = args.resolution
  if args.audioLayout != "":
    tl.layout = initLayout(args.audioLayout)
  if args.frameRate != AVRational(num: 0, den: 0):
    tl.tb = args.frameRate
  if args.background.isSome:
    tl.bg = args.background.get()

func stem(path: string): string =
  agSplitFile(path).name

func makeSaneTimebase*(tb: AVRational): AVRational =
  # A 0/0 rate (no declared fps) is NaN as a float; av_d2q(NaN) is degenerate.
  if not tb.isValid:
    return AVRational(num: 30, den: 1)
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
  var createdDirs = initHashSet[string]()
  var cache = initTable[string, MediaInfo]()

  proc makeTrack(i: int32, path: string): MediaInfo =
    let folder: string = path.parentDir / (path.stem & "_tracks")
    if folder notin createdDirs:
      try:
        createDir(folder)
      except OSError:
        removeDir(folder)
        createDir(folder)
      createdDirs.incl folder

    let newtrack: string = folder / (path.stem & "_" & $i & ".wav")
    if newtrack notin cache:
      transcodeAudio(path, newtrack, i)
      cache[newtrack] = initMediaInfo(newtrack)
    return cache[newtrack]

  for layer in tl.a.mitems:
    for clip in layer.mitems:
      if clip.stream > 0:
        let mi = makeTrack(clip.stream, clip.src[])
        clip.src = interner.intern(mi.path)
        clip.stream = 0
