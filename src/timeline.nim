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

type
  TransitionKind* = enum
    tkDissolve
  TransitionAlignment* = enum
    taStart, taCenter, taEnd
  Transition* = object
    kind*: TransitionKind
    at*: int64
    dur*: int64
    alignment*: TransitionAlignment
  TransitionLink* = object
    incoming*: int32 = -1
    outgoing*: int32 = -1

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
  vt*: seq[seq[Transition]]
  at*: seq[seq[Transition]]

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

func hasTransitions*(self: v3): bool =
  for track in self.vt:
    if track.len > 0: return true
  for track in self.at:
    if track.len > 0: return true

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
    start: int64, clips2: var seq[Clip2]): seq[Clip] {.inline.} =
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

    clips2.add Clip2(start: chunk[0], `end`: chunk[1], effect: e)

    if speed != 99999.0:
      let (offset, dur) = clipBounds(chunk[0], chunk[1], speed)
      if dur == 0:
        continue

      result.add Clip(src: src, start: timelineStart, dur: dur,
        offset: offset, effects: e)
      timelineStart += dur

proc initLinearTimeline*(src: ptr string, tb: AVRational, bg: RGBColor,
    mi: MediaInfo,
  effects: seq[Actions], actionIndex: seq[int]): v3 =
  var clips2: seq[Clip2]
  let clips = linearClips(src, effects, actionIndex, 0, clips2)

  result = v3(tb: tb, bg: bg, effects: effects, clips2: clips2,
      res: mi.getRes(),
    templateFile: src)
  mutHelper(result, mi, clips)

proc appendLinearTimeline*(tl: var v3, src: ptr string, mi: MediaInfo,
    actionIndex: seq[int]) =
  let clips = linearClips(src, tl.effects, actionIndex, tl.len, tl.clips2)

  if mi.v.len > 0:
    if tl.v.len == 0:
      tl.v.add @[]
      tl.langs.insert(mi.v[0].lang, 0)
    for clip in clips:
      var videoClip = clip
      videoClip.stream = 0
      tl.v[0].add videoClip

  for i in 0 ..< mi.a.len:
    if tl.a.len <= i:
      tl.a.add @[]
      tl.langs.add mi.a[i].lang
    for clip in clips:
      var audioClip = clip
      audioClip.stream = i.int16
      tl.a[i].add audioClip

  for i in 0 ..< mi.s.len:
    while tl.s.len <= i:
      tl.s.add @[]
    for clip in clips:
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
  var clips: seq[Clip] = @[]
  var clips2: seq[Clip2] = @[]
  var effects: seq[Actions] = @[]
  var start: int64 = 0

  for chunk in chunks:
    if chunk[2] > 0.0 and chunk[2] < 99999.0:
      let (offset, dur) = clipBounds(chunk[0], chunk[1], chunk[2])
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
      let e = uint32(effectIndex)
      clips.add Clip(src: src, start: start, dur: dur, offset: offset, effects: e)
      clips2.add Clip2(start: chunk[0], `end`: chunk[1], effect: e)
      start += dur

  result = v3(tb: tb, effects: effects, clips2: clips2, templateFile: src)
  result.res = mi.getRes()
  mutHelper(result, mi, clips)

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

proc validateTransitions*(tl: v3)

func transitionPlan*(clips: seq[Clip], transitions: seq[Transition]):
    seq[TransitionLink] =
  ## Match sorted edit-point transitions to sorted clips in linear time. A
  ## centered transition is outgoing for the left clip and incoming for the
  ## right clip; endpoint transitions appear on only one side.
  result = newSeq[TransitionLink](clips.len)
  var inCursor, outCursor = 0
  for i, clip in clips:
    while inCursor < transitions.len and transitions[inCursor].at < clip.start:
      inc inCursor
    if inCursor < transitions.len and transitions[inCursor].at == clip.start and
        transitions[inCursor].alignment != taEnd:
      result[i].incoming = inCursor.int32

    let clipEnd = clip.start + clip.dur
    while outCursor < transitions.len and transitions[outCursor].at < clipEnd:
      inc outCursor
    if outCursor < transitions.len and transitions[outCursor].at == clipEnd and
        transitions[outCursor].alignment != taStart:
      result[i].outgoing = outCursor.int32

proc addDissolveTransitions*(tl: var v3, requested: int64,
    minCut: int64 = 0) =
  ## Add portable start/center/end aligned dissolves to primary A/V tracks.
  ## Centered transitions are shortened symmetrically so they cannot overlap a
  ## neighboring transition or consume an entire visible clip.
  if requested <= 0: return
  let timelineEffects = tl.effects

  proc build(clips: seq[Clip]): seq[Transition] =
    if clips.len == 0: return
    var speeds = newSeq[float64](clips.len)
    for i, clip in clips:
      speeds[i] = 1.0
      for action in timelineEffects[clip.effects]:
        if action.kind in [actSpeed, actVarispeed]: speeds[i] *= action.val

    var centers: seq[Transition]
    for i in 0 ..< clips.len - 1:
      let left = clips[i]
      let right = clips[i + 1]
      if left.start + left.dur != right.start: continue
      let leftSpeed = speeds[i]
      let rightSpeed = speeds[i + 1]
      let leftSourceEnd = int64(round((left.offset + left.dur).float64 * leftSpeed))
      let rightSourceStart = int64(round(right.offset.float64 * rightSpeed))
      let cutDur = max(0'i64, rightSourceStart - leftSourceEnd)
      if left.src == right.src and cutDur < minCut:
        continue
      var half = min(requested div 2, min(left.dur, right.dur))
      # Incoming preroll is explicit in offset. For cuts within one source, the
      # removed source interval also bounds the outgoing postroll.
      half = min(half, int64(rightSourceStart.float64 / rightSpeed))
      if left.src != nil and right.src == left.src:
        half = min(half, int64(cutDur.float64 / max(leftSpeed, rightSpeed)))
      if half > 0:
        centers.add Transition(kind: tkDissolve, at: right.start,
          dur: half * 2, alignment: taCenter)

    var firstDur = min(requested, clips[0].dur)
    if centers.len > 0:
      firstDur = min(firstDur,
        centers[0].at - centers[0].dur div 2 - clips[0].start)
    if firstDur > 0:
      result.add Transition(kind: tkDissolve, at: clips[0].start,
        dur: firstDur, alignment: taStart)
    result.add centers
    let last = clips[^1]
    var lastDur = min(requested, last.dur)
    if centers.len > 0:
      let c = centers[^1]
      lastDur = min(lastDur, last.start + last.dur - (c.at + c.dur - c.dur div 2))
    if lastDur > 0:
      result.add Transition(kind: tkDissolve, at: last.start + last.dur,
        dur: lastDur, alignment: taEnd)

  tl.vt.setLen(tl.v.len)
  if tl.v.len > 0: tl.vt[0] = build(tl.v[0])
  tl.at.setLen(tl.a.len)
  for i in 0 ..< tl.a.len: tl.at[i] = build(tl.a[i])
  tl.validateTransitions()

func spanStart*(t: Transition): int64 =
  ## First timeline frame of the transition's span.
  t.at - (case t.alignment
    of taStart: 0'i64
    of taCenter: t.dur div 2
    of taEnd: t.dur)

proc validateTransitions*(tl: v3) =
  proc validateTrack(clips: seq[Clip], transitions: seq[Transition]) =
    var priorEnd = low(int64)
    var priorAt = low(int64)
    var leftCursor, rightCursor = 0
    for t in transitions:
      let spanStart = t.spanStart
      let spanEnd = spanStart + t.dur
      if t.dur <= 0 or spanStart < priorEnd or t.at < priorAt:
        error "Transitions must have positive, non-overlapping ranges"
      while leftCursor < clips.len and
          clips[leftCursor].start + clips[leftCursor].dur < t.at:
        inc leftCursor
      while rightCursor < clips.len and clips[rightCursor].start < t.at:
        inc rightCursor
      let hasLeft = leftCursor < clips.len and
        clips[leftCursor].start + clips[leftCursor].dur == t.at
      let hasRight = rightCursor < clips.len and clips[rightCursor].start == t.at
      case t.alignment
      of taStart:
        if not hasRight: error "Start-aligned transition has no clip at its edit point"
      of taCenter:
        if not hasLeft or not hasRight:
          error "Centered transition must join adjacent clips"
      of taEnd:
        if not hasLeft: error "End-aligned transition has no clip at its edit point"
      priorEnd = spanEnd
      priorAt = t.at
  if tl.vt.len notin [0, tl.v.len] or tl.at.len notin [0, tl.a.len]:
    error "Transition track count must match media track count"
  for i in 0 ..< tl.vt.len: validateTrack(tl.v[i], tl.vt[i])
  for i in 0 ..< tl.at.len: validateTrack(tl.a[i], tl.at[i])

type RampKey = tuple[effectIdx: uint32, kind: ActionKind, fadeIn: bool, dur: int64]

proc withRamp(tl: var v3, cache: var Table[RampKey, uint32], effectIdx: uint32,
    kind: ActionKind, fadeIn: bool, dur: int64): uint32 =
  let key = (effectIdx, kind, fadeIn, dur)
  if key in cache: return cache[key]
  var actions: seq[Action]
  for a in tl.effects[effectIdx]: actions.add a
  let values = if fadeIn: @[0.0'f32, 1.0'f32] else: @[1.0'f32, 0.0'f32]
  let ramp = case kind
    of actOpacity: Action(kind: actOpacity, kf: values, hasEase: true,
      easeCurve: easeLinear, easeDurUnit: duFrames, easeDur: dur.float32)
    of actVolume: Action(kind: actVolume, kf: values, hasEase: true,
      easeCurve: easeLinear, easeDurUnit: duFrames, easeDur: dur.float32)
    else: error "Internal error: unsupported transition ramp"
  actions.add ramp
  let group = newActions(actions)
  let found = tl.effects.find(group)
  result = if found >= 0: found.uint32 else:
    tl.effects.add group
    uint32(tl.effects.len - 1)
  cache[key] = result

proc bakeTransitions*(source: v3): v3 =
  ## Lower edit-point transitions to clip overlaps and linear ramps for the
  ## native renderer. Exporters continue to consume the unmodified timeline.
  result = source
  var rampCache: Table[RampKey, uint32]

  proc bakeTrack(tl: var v3, track: var seq[Clip], transitions: seq[Transition],
      isVideo: bool) =
    if track.len == 0 or transitions.len == 0: return
    let plan = transitionPlan(track, transitions)
    let k = (if isVideo: actOpacity else: actVolume)
    let partsPerClip = (if isVideo: 2 else: 3)
    var outTrack = newSeqOfCap[Clip](track.len * partsPerClip + 2)
    for i, original in track:
      var clip = original
      var fadeInEnd = clip.start
      var fadeOutStart = 0'i64
      var hasFadeOut = false

      if plan[i].incoming >= 0:
        let t = transitions[plan[i].incoming]
        let before = (if t.alignment == taCenter: t.dur div 2 else: 0'i64)
        clip.start -= before
        clip.offset = max(0'i64, clip.offset - before)
        clip.dur += before
        fadeInEnd = clip.start + t.dur

      if plan[i].outgoing >= 0:
        let t = transitions[plan[i].outgoing]
        if t.alignment == taCenter:
          let after = t.dur - t.dur div 2
          clip.dur += after
          if not isVideo:
            fadeOutStart = t.at - t.dur div 2
            hasFadeOut = true
        else:
          fadeOutStart = t.at - t.dur
          hasFadeOut = true

      let clipEnd = clip.start + clip.dur
      fadeInEnd = min(fadeInEnd, clipEnd)
      if hasFadeOut:
        fadeOutStart = max(fadeInEnd, min(fadeOutStart, clipEnd))
      else:
        fadeOutStart = clipEnd

      template addPart(lo, hi: int64, fadeIn, fadeOut: bool) =
        if hi > lo:
          var part = clip
          part.start = lo
          part.offset = clip.offset + (lo - clip.start)
          part.dur = hi - lo
          if fadeIn:
            part.effects = tl.withRamp(rampCache, part.effects, k, true, hi - lo)
          if fadeOut:
            part.effects = tl.withRamp(rampCache, part.effects, k, false, hi - lo)
          outTrack.add part

      addPart(clip.start, fadeInEnd, fadeIn = fadeInEnd > clip.start,
        fadeOut = false)
      addPart(fadeInEnd, fadeOutStart, fadeIn = false, fadeOut = false)
      addPart(fadeOutStart, clipEnd, fadeIn = false,
        fadeOut = fadeOutStart < clipEnd)
    track = outTrack

  for i in 0 ..< result.v.len:
    if i < result.vt.len: result.bakeTrack(result.v[i], result.vt[i], true)
  for i in 0 ..< result.a.len:
    if i < result.at.len: result.bakeTrack(result.a[i], result.at[i], false)
  result.vt.setLen(0)
  result.at.setLen(0)

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
