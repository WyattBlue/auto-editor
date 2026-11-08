## CMX 3600 edit decision lists: cut, dissolve and wipe events on V and
## A1 to A4, `M2` speed changes, and the `* FROM CLIP NAME`, `* TO CLIP NAME`,
## `* SOURCE FILE` and `* EFFECT NAME` comments that name the media and the
## transitions.
##
## An EDL carries no frame rate. The one asked for with `--frame-rate` is
## used; otherwise the first video file's, or failing that one guessed from
## the highest frame number the timecodes reach.

import std/[algorithm, os, strformat, strutils, tables]
from std/math import round

import ../[action, av, ffmpeg, log, media, timeline]
import ../lib/timecode
import ../util/[color, rational]

type
  Trans = enum
    trCut, trDissolve, trWipe, trKey

  Line = object
    num: string
    reel: string
    video: bool
    audio: seq[int] # 1-based channels
    trans: Trans
    dur: int64
    tcs: array[4, Timecode]
    src: ptr string # resolved later

  Event = object
    lines: seq[Line]
    fromClip, toClip, effect: string
    files: seq[string]
    m2: seq[(string, float64)] # reel, source frames a second
    drop: bool # the FCM in force

  Parsed = object
    events: seq[Event]
    anyDrop: bool
    maxFrame: int64

func parseChannels(text: string, line: var Line): bool =
  case text.toUpperAscii
  of "B":
    line.video = true
    line.audio.add 1
    return true
  of "NONE":
    return true
  else: discard
  for part in text.toUpperAscii.split('/'):
    case part
    of "V": line.video = true
    of "A", "A1": line.audio.add 1
    of "AA": line.audio.add [1, 2]
    else:
      if part.len < 2 or part[0] != 'A': return false
      var n = 0
      for ch in part[1 .. ^1]:
        if ch notin Digits or n > 99: return false
        n = n * 10 + (ord(ch) - ord('0'))
      if n == 0: return false
      line.audio.add n
  true

func parseInt64(text: string, value: var int64): bool =
  if text.len == 0 or text.len > 9: return false
  value = 0
  for ch in text:
    if ch notin Digits: return false
    value = value * 10 + int64(ord(ch) - ord('0'))
  true

func parseEventLine(text: string, line: var Line): bool =
  let toks = text.splitWhitespace()
  if toks.len < 8 or toks[0].len > 6: return false
  for ch in toks[0]:
    if ch notin Digits: return false
  let n = toks.len
  line = Line(num: toks[0], reel: toks[1])
  for i in 0 .. 3:
    if not parseTimecode(toks[n - 4 + i], line.tcs[i]): return false
  if not parseChannels(toks[2], line): return false
  let mid = toks[3 ..< n - 4]
  if mid.len == 0: return false
  let first = mid[0].toUpperAscii
  proc numAt(i: int): int64 =
    if i < mid.len and parseInt64(mid[i], result): return result
    0
  case first
  of "C": line.trans = trCut
  of "D":
    line.trans = trDissolve
    line.dur = numAt(1)
  of "K", "KB", "KO":
    line.trans = trKey
  else:
    if first[0] != 'W': return false
    line.trans = trWipe
    line.dur = numAt(1)
  true

proc parse(text: string): Parsed =
  var drop = false
  var skipMetadata = false
  var unknown = 0
  for raw in text.splitLines:
    let l = raw.strip()
    if l.len == 0: continue
    let upper = l.toUpperAscii
    if upper.startsWith("TITLE:"): continue
    if upper.startsWith("FCM:"):
      drop = "DROP" in upper and "NON" notin upper
      result.anyDrop = result.anyDrop or drop
      continue
    if skipMetadata and (l[0] == '*' or upper.startsWith("M2") or
        upper.startsWith("AUD")):
      continue
    if l[0] == '*':
      if result.events.len == 0: continue
      let c = l[1 .. ^1].strip()
      let cu = c.toUpperAscii
      template value(prefix: string): string = c[prefix.len .. ^1].strip()
      if cu.startsWith("FROM CLIP NAME:"):
        result.events[^1].fromClip = value("FROM CLIP NAME:")
      elif cu.startsWith("TO CLIP NAME:"):
        result.events[^1].toClip = value("TO CLIP NAME:")
      elif cu.startsWith("SOURCE FILE:"):
        result.events[^1].files.add value("SOURCE FILE:")
      elif cu.startsWith("EFFECT NAME:"):
        result.events[^1].effect = value("EFFECT NAME:")
      continue
    if upper.startsWith("M2"):
      # `M2 REEL fps source-in`; a reel with spaces is joined back.
      let toks = l.splitWhitespace()
      if toks.len >= 3 and result.events.len > 0:
        var fpsAt = -1
        var tc: Timecode
        for i in countdown(toks.len - 1, 2):
          if not parseTimecode(toks[i], tc):
            try:
              discard parseFloat(toks[i])
              fpsAt = i
              break
            except ValueError: discard
        if fpsAt >= 2:
          let fps = (try: parseFloat(toks[fpsAt]) except ValueError: 0.0)
          result.events[^1].m2.add (toks[1 ..< fpsAt].join(" "), fps)
      continue
    if upper.startsWith("AUD"):
      if result.events.len > 0 and result.events[^1].lines.len > 0:
        for tok in l.splitWhitespace()[1 .. ^1]:
          var n: int64
          if parseInt64(tok, n) and n in 1 .. 99:
            result.events[^1].lines[^1].audio.add n.int
      continue
    if upper.startsWith(">>>") or upper.startsWith("REM"): continue
    var line: Line
    if parseEventLine(l, line):
      for tc in line.tcs:
        result.maxFrame = max(result.maxFrame, tc.f)
        result.anyDrop = result.anyDrop or tc.drop
      if result.events.len > 0 and not skipMetadata and
          result.events[^1].lines[^1].num == line.num:
        result.events[^1].lines.add line
      else:
        result.events.add Event(lines: @[line], drop: drop)
      skipMetadata = false
      continue
    if upper.startsWith("SPLIT:"):
      warning "EDL split (L-cut/J-cut) lines are not supported; the split was ignored"
      continue
    if l[0] in Digits:
      # Comments after a rejected event aren't the previous event's.
      skipMetadata = true
    inc unknown
  if unknown > 0:
    warning &"Ignored {unknown} unrecognised EDL line(s)"

func guessRate(p: Parsed): AVRational =
  ## The lowest common rate whose timecodes reach the frame numbers seen.
  if p.anyDrop:
    if p.maxFrame >= 30: AVRational(num: 60000, den: 1001)
    else: AVRational(num: 30000, den: 1001)
  elif p.maxFrame >= 30: AVRational(num: 60, den: 1)
  elif p.maxFrame >= 25: AVRational(num: 30, den: 1)
  elif p.maxFrame >= 24: AVRational(num: 25, den: 1)
  else: AVRational(num: 24, den: 1)

type Track = object
  clips: seq[Clip] # by start, none overlapping
  maxDur: int64

func byStart(c: Clip, key: int64): int = cmp(c.start, key)

func has(track: Track, clip: Clip): bool =
  ## Whether the track holds `clip`. No two of its clips start together.
  let i = track.clips.lowerBound(clip.start, byStart)
  i < track.clips.len and track.clips[i] == clip

proc overwrite(track: var Track, clip: Clip) =
  ## Lay `clip` over the track, as an EDL event records over what was there.
  let lo = clip.start
  let hi = clip.start + clip.dur
  # Clips starting by lo - maxDur end by lo, so only those after them can be
  # cut; rebuilding just that tail keeps a long cut list linear.
  let first = track.clips.upperBound(lo - track.maxDur, byStart)
  var kept: seq[Clip]
  for c in track.clips.toOpenArray(first, track.clips.high):
    let cEnd = c.start + c.dur
    if cEnd <= lo or c.start >= hi:
      kept.add c
      continue
    if c.start < lo:
      var left = c
      left.dur = lo - c.start
      kept.add left
    if cEnd > hi:
      var right = c
      right.start = hi
      right.offset = c.offset + (hi - c.start)
      right.dur = cEnd - hi
      kept.add right
  kept.add clip
  kept.sort(proc (a, b: Clip): int = cmp(a.start, b.start))
  track.clips.setLen(first)
  track.clips.add kept
  track.maxDur = max(track.maxDur, clip.dur)

type Importer = object
  base: int64
  startFrames: int64
  video: Track
  audio: seq[Track]
  placed: seq[PlacedTransition]
  effects: seq[Actions]
  effectIndex: EffectIndex
  audioStreams: Table[ptr string, int] # probed audio stream counts
  dropped: CountTable[string]

func frames(im: Importer, tc: Timecode, drop: bool): int64 =
  toFrames(tc, im.base, tc.drop or drop)

func rec(im: Importer, tc: Timecode, drop: bool): int64 =
  im.frames(tc, drop) - im.startFrames

proc speedOf(im: var Importer, ev: Event, reel: string): float64 =
  ## The clip's speed from the event's `M2` line for its reel, at 1 for
  ## what v3 can't play.
  result = 1.0
  for (r, fps) in ev.m2:
    if r != reel: continue
    if fps == 0.0:
      im.dropped.inc "freeze frame"
      return
    let speed = abs(fps) / im.base.float64
    if speed != speed or speed < 0.0001 or speed > 1000.0:
      warning &"EDL motion line for reel {reel} has an unusable speed ({fps}); the clip keeps normal speed"
      return
    if fps < 0: im.dropped.inc "reversed clip"
    return speed

proc effectsFor(im: var Importer, speed: float64): uint32 =
  var acts: seq[Action]
  if speed != 1.0:
    acts.add Action(kind: actSpeed, val: speed.float32)
  im.effectIndex.intern(im.effects, newActions(acts))

proc audioLayer(im: var Importer, src: ptr string, channel: int): (int, int16) =
  ## The audio track and source stream an EDL audio channel plays.
  let streams = im.audioStreams.getOrDefault(src, 1)
  let stream = (if channel - 1 < streams: int16(channel - 1) else: 0'i16)
  (channel - 1, stream)

proc lay(im: var Importer, line: Line, start, dur, srcFrames: int64,
    speed: float64, effects: uint32) =
  ## Put the line's clip on each of its channels.
  if dur <= 0 or line.src == nil: return
  let offset = int64(round(srcFrames.float64 / speed))
  if line.video:
    im.video.overwrite Clip(src: line.src, start: start, dur: dur,
      offset: offset, effects: effects)
  # Two audio channels on one line are one stream's channels.
  if line.audio.len > 0:
    let (layer, stream) = im.audioLayer(line.src, min(line.audio))
    let clip = Clip(src: line.src, start: start, dur: dur, offset: offset,
      effects: effects, stream: stream)
    # The same stream laid again on another channel would play twice over.
    for i in 0 ..< min(layer, im.audio.len):
      if im.audio[i].has(clip): return
    while im.audio.len <= layer: im.audio.add Track()
    im.audio[layer].overwrite clip

proc transitionKind(ev: Event, line: Line, video: bool): TransitionKind =
  if ev.effect != "" and kindFromName(ev.effect, video, result): return
  if line.trans == trWipe and video: return tkWipe
  if video: tkDissolve else: tkConstantPower

proc importEvent(im: var Importer, ev: Event) =
  let drop = ev.drop
  if ev.lines.len == 2 and ev.lines[1].trans in {trDissolve, trWipe}:
    let l1 = ev.lines[0]
    let l2 = ev.lines[1]
    let t0 = im.rec(l2.tcs[2], drop)
    let t1 = im.rec(l2.tcs[3], drop)
    let d = max(0'i64, l2.dur)
    let speed = im.speedOf(ev, l2.reel)
    let effects = im.effectsFor(speed)
    let toBlack = l2.reel.toUpperAscii == "BL"
    let fromBlack = l1.reel.toUpperAscii == "BL" or l1.src == nil
    var kinds: seq[(bool, TransitionKind)]
    if l2.video: kinds.add (true, transitionKind(ev, l2, true))
    if l2.audio.len > 0: kinds.add (false, transitionKind(ev, l2, false))
    # The outgoing line is normally zero-length, a marker of where the
    # transition starts; one with a record range is a cut of its own.
    if not fromBlack:
      let from0 = im.rec(l1.tcs[2], drop)
      let from1 = im.rec(l1.tcs[3], drop)
      if from1 > from0:
        let fromSpeed = im.speedOf(ev, l1.reel)
        im.lay(l1, from0, from1 - from0, im.frames(l1.tcs[0], drop), fromSpeed,
          im.effectsFor(fromSpeed))

    # Two audio channels on one line are one stream's channels, on the
    # lowest channel's track.
    let audioLayer = (if l2.audio.len > 0: min(l2.audio) - 1 else: -1)
    template endsAtT0(track: Track): bool =
      track.clips.len > 0 and track.clips[^1].start + track.clips[^1].dur == t0

    if toBlack:
      # Fade out: the outgoing clip plays on through the transition.
      if l2.video and endsAtT0(im.video): im.video.clips[^1].dur += d
      if audioLayer >= 0 and audioLayer < im.audio.len and
          endsAtT0(im.audio[audioLayer]):
        im.audio[audioLayer].clips[^1].dur += d
      for (video, kind) in kinds:
        im.placed.add PlacedTransition(at: t0 + d, dur: d, align: 2,
          video: video, kind: kind)
      return

    var before = 0'i64
    var align = 0
    if not fromBlack:
      # A dissolve between two sources is centered on the cut between them.
      var joins = (if l2.video: endsAtT0(im.video) else: true)
      if audioLayer >= 0 and
          (audioLayer >= im.audio.len or not endsAtT0(im.audio[audioLayer])):
        joins = false
      if joins and d >= 2:
        before = d div 2
        align = 1
        if l2.video: im.video.clips[^1].dur += before
        if audioLayer >= 0: im.audio[audioLayer].clips[^1].dur += before
      elif d > 0:
        warning &"EDL event {l2.num}: transition without an outgoing clip was imported as a fade in"
    let srcIn = im.frames(l2.tcs[0], drop) + int64(round(before.float64 * speed))
    im.lay(l2, t0 + before, t1 - t0 - before, srcIn, speed, effects)
    if d > 0:
      for (video, kind) in kinds:
        im.placed.add PlacedTransition(at: t0 + before, dur: d, align: align,
          video: video, kind: kind)
    return

  if ev.lines.len > 1:
    warning &"EDL event {ev.lines[0].num} has {ev.lines.len} lines; imported as separate cuts"
  for line in ev.lines:
    if line.trans == trKey:
      im.dropped.inc "keyed clip"
      continue
    if line.trans != trCut:
      warning &"EDL event {line.num}: transition without an outgoing source line imported as a cut"
    if line.reel.toUpperAscii == "BL": continue
    let t0 = im.rec(line.tcs[2], drop)
    let t1 = im.rec(line.tcs[3], drop)
    let speed = im.speedOf(ev, line.reel)
    im.lay(line, t0, t1 - t0, im.frames(line.tcs[0], drop), speed,
      im.effectsFor(speed))

proc resolvePath(name, edlDir: string): string =
  if name.isAbsolute: name else: edlDir / name

proc resolveSources(p: var Parsed, edlDir: string, interner: var StringInterner) =
  ## Each line's media: its `SOURCE FILE`, else its clip name, else its reel,
  ## relative to the EDL.
  for ev in p.events.mitems:
    for i, line in ev.lines.mpairs:
      if line.reel.toUpperAscii == "BL": continue
      let incoming = i > 0 and line.trans in {trDissolve, trWipe}
      var name = ""
      if ev.files.len > 0:
        name = (if incoming and ev.files.len > 1: ev.files[1] else: ev.files[0])
      elif incoming and ev.toClip != "": name = ev.toClip
      elif ev.fromClip != "": name = ev.fromClip
      elif incoming and ev.toClip != "": name = ev.toClip
      else: name = line.reel
      line.src = interner.intern(resolvePath(name, edlDir))

proc edlRead*(path: string, interner: var StringInterner,
    frameRate: AVRational): v3 =
  let text = (try: readFile(path) except IOError: error "Cannot read: " & path)
  var parsed = parse(text)
  if parsed.events.len == 0:
    error "No events found in EDL"
  resolveSources(parsed, path.parentDir, interner)

  # Probe the files that exist: the frame rate, canvas, and stream counts
  # come from them.
  var probed: Table[ptr string, MediaInfo]
  var sources: seq[ptr string]
  for ev in parsed.events:
    for line in ev.lines:
      if line.src != nil and line.src notin probed:
        if fileExists(line.src[]):
          try:
            probed[line.src] = initMediaInfo(line.src[])
            sources.add line.src
          except AutoEditorError:
            discard

  var tb = frameRate
  if not tb.isValid:
    for src in sources:
      let mi = probed[src]
      if mi.v.len > 0 and mi.v[0].avg_rate.isValid:
        tb = makeSaneTimebase(mi.v[0].avg_rate)
        break
  if not tb.isValid:
    tb = guessRate(parsed)
    warning &"EDL has no frame rate; assumed {tb.float64:.3f} (set --frame-rate to override)"

  var im = Importer(base: timecodeBase(tb))
  for src in sources:
    im.audioStreams[src] = probed[src].a.len
  # The sequence starts on the hour of the first record timecode.
  var firstRec = high(int64)
  for ev in parsed.events:
    for line in ev.lines:
      firstRec = min(firstRec, im.frames(line.tcs[2], ev.drop))
  im.startFrames = (firstRec div (im.base * 3600)) * im.base * 3600

  for ev in parsed.events:
    im.importEvent(ev)

  result = v3(tb: tb, bg: RGBColor(red: 0, green: 0, blue: 0), sr: 48000,
    res: (1920'i32, 1080'i32), effects: im.effects)
  if im.video.clips.len > 0:
    result.v.add im.video.clips
  for track in im.audio:
    if track.clips.len > 0:
      result.a.add track.clips
  if result.v.len == 0 and result.a.len == 0:
    error "EDL places no clips"
  var layout = "stereo"
  for src in sources:
    let mi = probed[src]
    if mi.v.len > 0:
      result.res = mi.getRes()
      break
  for layer in result.a:
    if layer.len > 0 and layer[0].src in probed:
      let mi = probed[layer[0].src]
      let stream = layer[0].stream
      if stream < mi.a.len:
        result.sr = mi.a[stream].sampleRate
        layout = mi.a[stream].layout
      break
  result.layout = initLayout(layout)
  if im.placed.len > 0:
    result.placeTransitions(im.placed)
    result.validateTransitions()
  result.templateFile = result.firstSource
  result.updateNumberOfSrc()
  while result.langs.len < result.v.len + result.a.len:
    result.langs.add ['u', 'n', 'd', '\0']

  if im.dropped.len > 0:
    var parts: seq[string]
    for what, count in im.dropped:
      parts.add (if count == 1: &"1 {what}" else: &"{count} {what}s")
    parts.sort()
    warning "Left out of the import: " & parts.join(", ")
