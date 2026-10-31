## Read Final Cut Pro's FCPXML (1.10 and later) into a timeline: the primary
## storyline, connected clips, transitions, speed and volume. What a v3
## timeline can't hold is left out with a warning.

import std/[algorithm, math, os, strformat, strutils, tables]

import ../[action, av, log, timeline]
import ../util/[color, fun, rational, xml]
import ../lib/speedmap

# Tags common in FCPXML, so the parsed tree can share their strings.
const fcp11Tags = ["fcpxml", "resources", "format", "asset", "media-rep",
  "effect", "library", "event", "project", "sequence", "spine", "asset-clip",
  "clip", "video", "audio", "gap", "transition", "filter-video",
  "filter-audio", "param", "timeMap", "timept", "adjust-volume", "metadata",
  "md", "array", "string", "conform-rate", "audio-channel-source"]

type
  Asset = object
    src: ptr string
    start: float64 # seconds where the media's own time begins (its timecode)
    hasVideo, hasAudio: bool

  Placed = object
    clip: Clip
    video, audio: bool

  StoryKind = enum skClip, skGap, skTransition

  StoryItem = object # the primary storyline in order, for placing transitions
    kind: StoryKind
    start, stop: int64 # timeline frames; a transition's span
    transition: TransitionKind

  Reader = object
    tb: AVRational
    assets: Table[string, Asset]
    effects: seq[Actions]
    effectIndex: EffectIndex
    lanes: Table[int, seq[Placed]] # connected clips by lane
    dropped: CountTable[string]

func uiName(tag: string): string =
  ## What Final Cut Pro calls an element it writes as `tag`.
  case tag
  of "ref-clip": "compound clip"
  of "sync-clip": "synchronized clip"
  of "mc-clip": "multicam clip"
  of "video": "generator"
  else: tag

proc seconds(s, what: string): float64 =
  ## An FCPXML time: "N/Ds" or "Ns".
  if s.len < 2 or s[^1] != 's':
    error &"Invalid {what} time: '{s}'"
  let body = s[0 ..< ^1]
  try:
    let slash = body.find('/')
    if slash < 0:
      return parseBiggestInt(body).float64
    let den = parseBiggestInt(body[slash + 1 .. ^1])
    if den <= 0: error &"Invalid {what} time: '{s}'"
    return parseBiggestInt(body[0 ..< slash]).float64 / den.float64
  except ValueError:
    error &"Invalid {what} time: '{s}'"

proc attrSeconds(n: XmlNode, name: string, default = 0.0): float64 =
  let s = n.attr(name)
  if s == "": default else: seconds(s, name)

func frames(r: Reader, secs: float64): int64 =
  int64(round(secs * r.tb.num.float64 / r.tb.den.float64))

proc speedOf(r: var Reader, timeMap: XmlNode, inSecs: float64, dur: int64,
    offset: var int64): Action =
  ## The speed a time map plays the clip at from its in point for `dur`
  ## frames. A ramp sets `offset` from where in the media the clip begins.
  var points: seq[(float64, float64)]
  for p in timeMap:
    if p.kind == xnElement and p.tag == "timept":
      points.add (p.attrSeconds("time"), p.attrSeconds("value"))
  let secs = dur.float64 * r.tb.den.float64 / r.tb.num.float64
  let (speed, mediaIn, ok) = speedFromMap(points, inSecs, secs)
  if not ok:
    r.dropped.inc "speed ramp"
    return Action(kind: actSpeed, val: 1)
  if speed.sKf.len > 0: offset = r.frames(mediaIn / speed.val)
  speed

proc clipEffects(r: var Reader, n: XmlNode, inSecs: float64, dur: int64,
    offset: var int64): uint32 =
  var acts: seq[Action]
  for c in n:
    if c.kind != xnElement: continue
    case c.tag
    of "timeMap":
      let speed = r.speedOf(c, inSecs, dur, offset)
      if speed.val != 1.0 or speed.sKf.len > 0: acts.add speed
    of "adjust-volume":
      let amount = c.attr("amount")
      if amount.endsWith("dB"):
        var db: float64
        try:
          db = parseFloat(amount[0 ..< ^2])
        except ValueError:
          error &"Invalid adjust-volume amount: '{amount}'"
        let gain = clamp(pow(10.0, db / 20.0), 0.0, 3.98109)
        if gain != 1.0:
          acts.add Action(kind: actVolume, kf: @[gain.float32])
    else: discard
  r.effectIndex.intern(r.effects, newActions(acts))

proc place(r: var Reader, n: XmlNode, start: int64): (bool, Placed) =
  ## `n` as a clip starting at timeline frame `start`, if it is one this reads.
  var asset: Asset
  var mediaSecs: float64 # media time at the clip's in point
  case n.tag
  of "asset-clip":
    let id = n.attr("ref")
    if id notin r.assets: error &"asset-clip refers to unknown asset '{id}'"
    asset = r.assets[id]
    mediaSecs = n.attrSeconds("start", asset.start)
    case n.attr("srcEnable")
    of "video": asset.hasAudio = false
    of "audio": asset.hasVideo = false
    else: discard
  of "clip":
    # A clip holds its media as video and audio children, each mapping the
    # clip's own time to its asset's.
    var media: XmlNode = nil
    var hasVideo, hasAudio = false
    for c in n:
      if c.kind != xnElement or c.attr("ref") == "": continue
      if c.tag == "video": hasVideo = true
      elif c.tag == "audio": hasAudio = true
      else: continue
      if media == nil or c.tag == "video": media = c
    if media == nil:
      r.dropped.inc "empty clip"
      return
    let id = media.attr("ref")
    if id notin r.assets: error &"{media.tag} refers to unknown asset '{id}'"
    asset = r.assets[id]
    asset.hasVideo = asset.hasVideo and hasVideo
    asset.hasAudio = asset.hasAudio and hasAudio
    mediaSecs = media.attrSeconds("start", asset.start) +
      n.attrSeconds("start") - media.attrSeconds("offset")
  else:
    r.dropped.inc uiName(n.tag)
    return

  let dur = r.frames(n.attrSeconds("offset") + n.attrSeconds("duration")) -
    r.frames(n.attrSeconds("offset"))
  if dur <= 0 or not (asset.hasVideo or asset.hasAudio):
    return
  var offset = r.frames(mediaSecs) - r.frames(asset.start)
  let effects = r.clipEffects(n, mediaSecs, dur, offset)
  if offset < 0:
    error &"{n.tag} starts before its media"
  let clip = Clip(src: asset.src, start: start, dur: dur, offset: offset,
    effects: effects, stream: 0)
  (true, Placed(clip: clip, video: asset.hasVideo, audio: asset.hasAudio))

proc readConnected(r: var Reader, parent: XmlNode, parentStart: int64) =
  ## Clips connected to `parent`, which starts at timeline frame `parentStart`.
  ## Their offsets are in the parent's own time, which begins at its start.
  let origin = parent.attrSeconds("start")
  for c in parent:
    if c.kind != xnElement or c.attr("lane") == "": continue
    var lane: int
    try:
      lane = parseInt(c.attr("lane"))
    except ValueError:
      error "Invalid lane: '" & c.attr("lane") & "'"
    if c.tag == "spine":
      r.dropped.inc "connected storyline"
      continue
    if c.attr("enabled") == "0": continue
    let start = parentStart + r.frames(c.attrSeconds("offset") - origin)
    let (ok, placed) = r.place(c, start)
    if ok:
      r.lanes.mgetOrPut(lane, @[]).add placed

func layered(clips: seq[Clip]): seq[seq[Clip]] =
  ## `clips` as few layers as hold them without overlap, in start order.
  var sorted = clips
  sorted.sort(proc(a, b: Clip): int = cmp(a.start, b.start))
  for clip in sorted:
    var placed = false
    for layer in result.mitems:
      if layer[^1].start + layer[^1].dur <= clip.start:
        layer.add clip
        placed = true
        break
    if not placed:
      result.add @[clip]

proc readAssets(r: var Reader, resources: XmlNode,
    interner: var StringInterner): Table[string, XmlNode] =
  ## Fill `r.assets`; return the formats by id.
  for n in resources:
    if n.kind != xnElement: continue
    case n.tag
    of "format":
      result[n.attr("id")] = n
    of "asset":
      var src = ""
      for c in n:
        if c.kind == xnElement and c.tag == "media-rep" and
            c.attr("kind") in ["", "original-media"]:
          src = uriToPath(c.attr("src"))
          break
      if src == "" and n.attr("src") != "": # FCPXML 1.8 and earlier
        src = uriToPath(n.attr("src"))
      if src == "":
        error &"asset '{n.attr(\"id\")}' has no media"
      r.assets[n.attr("id")] = Asset(src: interner.intern(src),
        start: n.attrSeconds("start"), hasVideo: n.attr("hasVideo") == "1",
        hasAudio: n.attr("hasAudio") == "1")
    else: discard

proc findFirst(n: XmlNode, tag: string): XmlNode =
  for c in n:
    if c.kind != xnElement: continue
    if c.tag == tag: return c
    let found = c.findFirst(tag)
    if found != nil: return found
  nil

proc parseSampleRate(s: string): cint =
  ## "48k", "44.1k", ...; 48000 when absent.
  if s == "": return 48000
  var rate: float64
  try:
    rate = parseFloat(s.strip(leading = false, chars = {'k'}))
  except ValueError:
    error &"Invalid audioRate: '{s}'"
  cint(round(rate * (if s.endsWith('k'): 1000.0 else: 1.0)))

proc fcp11ReadXml*(path: string, interner: var StringInterner): v3 =
  ## Read a .fcpxml file, or the Info.fcpxml in a .fcpxmld bundle.
  let file = (if dirExists(path): path / "Info.fcpxml" else: path)
  let root = parseXmlFile(file, fcp11Tags)
  if root == nil or root.tag != "fcpxml":
    error "Expected 'fcpxml' root tag, got '" &
      (if root == nil: "nil" else: root.tag) & "'"

  var r = Reader()
  var formats: Table[string, XmlNode]
  for c in root:
    if c.kind == xnElement and c.tag == "resources":
      formats = r.readAssets(c, interner)

  let sequence = root.findFirst("sequence")
  if sequence == nil:
    error "No <sequence> found in FCPXML"
  let format = formats.getOrDefault(sequence.attr("format"))
  if format == nil:
    error &"sequence refers to unknown format '{sequence.attr(\"format\")}'"

  let fd = format.attr("frameDuration")
  let slash = fd.find('/')
  let (fdNum, fdDen) =
    try:
      if fd.len > 1 and fd[^1] == 's' and slash > 0:
        (parseInt(fd[0 ..< slash]), parseInt(fd[slash + 1 ..< ^1]))
      else: (0, 0)
    except ValueError: (0, 0)
  if fdNum <= 0 or fdDen <= 0:
    error &"Invalid frameDuration: '{fd}'"
  let g = gcd(fdNum, fdDen)
  r.tb = AVRational(num: cint(fdDen div g), den: cint(fdNum div g))

  let w = (try: parseInt(format.attr("width")) except ValueError: 1920)
  let h = (try: parseInt(format.attr("height")) except ValueError: 1080)

  var spine: XmlNode = nil
  for c in sequence:
    if c.kind == xnElement and c.tag == "spine":
      spine = c
      break
  if spine == nil:
    error "No <spine> found in the sequence"

  # Spine offsets count from the sequence's start, often 01:00:00:00.
  let tcStart = sequence.attrSeconds("tcStart")
  var video, audio: seq[Clip]
  var story: seq[StoryItem]
  for n in spine:
    if n.kind != xnElement: continue
    let start = r.frames(n.attrSeconds("offset") - tcStart)
    case n.tag
    of "asset-clip", "clip":
      if n.attr("enabled") != "0":
        let (ok, placed) = r.place(n, start)
        if ok:
          if placed.video: video.add placed.clip
          if placed.audio: audio.add placed.clip
          story.add StoryItem(kind: skClip, start: start,
            stop: start + placed.clip.dur)
      r.readConnected(n, start)
    of "gap":
      story.add StoryItem(kind: skGap)
      r.readConnected(n, start)
    of "transition":
      let stop = n.attrSeconds("offset") + n.attrSeconds("duration") - tcStart
      var kind = tkDissolve
      if not kindFromName(n.attr("name"), true, kind):
        for f in n:
          if f.kind == xnElement and f.tag == "filter-video" and
              kindFromName(f.attr("name"), true, kind):
            break
      story.add StoryItem(kind: skTransition, start: start, stop: r.frames(stop),
        transition: kind)
    else:
      r.dropped.inc uiName(n.tag)

  # A transition sits between the story items it joins; where it starts
  # against their edit point gives its alignment.
  var transitions: seq[Transition]
  for k, item in story:
    if item.kind != skTransition: continue
    let hasPrev = k > 0 and story[k - 1].kind == skClip
    let hasNext = k + 1 < story.len and story[k + 1].kind == skClip
    let dur = item.stop - item.start
    if dur <= 0 or not (hasPrev or hasNext):
      r.dropped.inc "transition"
      continue
    let at = (if hasNext: story[k + 1].start else: story[k - 1].stop)
    let alignment =
      if not hasPrev or item.start == at: taStart
      elif not hasNext or item.stop == at: taEnd
      else: taCenter
    transitions.add Transition(kind: item.transition, at: at, dur: dur,
      alignment: alignment)

  result.tb = r.tb
  result.res = (int32(w), int32(h))
  result.bg = RGBColor(red: 0, green: 0, blue: 0)
  result.sr = parseSampleRate(sequence.attr("audioRate"))
  result.layout = initLayout(
    case sequence.attr("audioLayout")
    of "mono": "mono"
    of "surround": "5.1"
    else: "stereo")
  if video.len > 0: result.v.add video
  if audio.len > 0: result.a.add audio

  var laneKeys: seq[int]
  for lane in r.lanes.keys: laneKeys.add lane
  laneKeys.sort()
  # Above the storyline, each lane is a video layer over the last.
  for lane in laneKeys:
    if lane < 0: continue
    var laneVideo: seq[Clip]
    for p in r.lanes[lane]:
      if p.video: laneVideo.add p.clip
    for layer in layered(laneVideo): result.v.add layer
  # Every lane's audio mixes in; nearest the storyline first.
  for lane in laneKeys.sortedByIt(abs(it)):
    var laneAudio: seq[Clip]
    for p in r.lanes[lane]:
      if p.audio: laneAudio.add p.clip
      # v3 has no layer under the base, so only its audio comes through.
      if lane < 0 and p.video: r.dropped.inc "below-storyline video clip"
    for layer in layered(laneAudio): result.a.add layer

  if result.v.len == 0 and result.a.len == 0:
    error "No clips found in the FCPXML"

  if transitions.len > 0:
    if video.len > 0:
      result.vt = newSeq[seq[Transition]](result.v.len)
      result.vt[0] = transitions
    if audio.len > 0:
      # A storyline transition crossfades the audio.
      result.at = newSeq[seq[Transition]](result.a.len)
      result.at[0] = transitions
      for t in result.at[0].mitems: t.kind = tkDissolve
    result.validateTransitions()

  result.effects = r.effects
  result.templateFile = result.firstSource
  result.updateNumberOfSrc()
  while result.langs.len < result.v.len + result.a.len:
    result.langs.add ['u', 'n', 'd', '\0']

  if r.dropped.len > 0:
    var parts: seq[string]
    for what, count in r.dropped:
      parts.add (if count == 1: &"1 {what}" else: &"{count} {what}s")
    parts.sort()
    warning "Left out of the import: " & parts.join(", ")
