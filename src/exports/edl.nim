## CMX 3600 edit decision lists, as Premiere Pro and Resolve read them.
##
## An EDL holds one video track and up to four audio channels, each event a
## cut or a dissolve/wipe into the next source, with `M2` lines for speed
## changes. Clip names, source files and transition names ride along as the
## `*` comments the editors recognise, which is also how the import gets
## them back.

import std/[algorithm, os, strformat, strutils, tables]
from std/math import round

import ../[log, timeline]
import ../lib/[speedmap, timecode]
import ../util/fun

type
  Channel = enum
    chV, chA1, chA2, chA3, chA4

  Line = object
    reel: string
    trans: string # C, D, W001
    dur: int64    # transition frames; -1 on a cut
    srcIn, srcOut, recIn, recOut: int64

  EventKey = (ptr string, int16, int64, int64, int64)

  Event = object
    lines: seq[Line]
    comments: seq[string]
    m2: string # the motion line, without its reel
    m2Reel: string
    channels: set[Channel]
    # Linked cut events of one clip on V and A merge into one: the clip's
    # source, stream, bounds and source in point.
    mergeable: bool
    key: EventKey
    order: (int64, int)

func channelCode(channels: set[Channel]): string =
  ## The channel column for a set EDLs can name; empty for the rest.
  if channels == {chV}: "V"
  elif channels == {chV, chA1}: "B"
  elif channels == {chV, chA1, chA2}: "AA/V"
  elif channels == {chV, chA2}: "A2/V"
  elif channels == {chA1}: "A"
  elif channels == {chA2}: "A2"
  elif channels == {chA1, chA2}: "AA"
  elif channels == {chA3}: "A3"
  elif channels == {chA4}: "A4"
  else: ""

func reelName(path: string): string =
  ## Eight characters of the file's stem, in the charset every reader takes.
  for ch in agSplitFile(path).name:
    if result.len == 8: break
    if ch in {'a' .. 'z'}: result.add toUpperAscii(ch)
    elif ch in {'A' .. 'Z', '0' .. '9'}: result.add ch
    elif ch in {' ', '-', '_', '.'}: result.add '_'
  if result.len == 0: result = "AX"

proc assignReels(tl: v3): Table[ptr string, string] =
  ## Distinct files get distinct reels.
  var used: Table[string, ptr string]
  var sources: seq[ptr string]
  for layer in tl.v:
    for clip in layer:
      if clip.src != nil and clip.src notin result:
        result[clip.src] = ""
        sources.add clip.src
  for layer in tl.a:
    for clip in layer:
      if clip.src != nil and clip.src notin result:
        result[clip.src] = ""
        sources.add clip.src
  for src in sources:
    let base = reelName(src[])
    var reel = base
    var n = 1
    while reel in used:
      inc n
      let suffix = $n
      reel = base[0 ..< min(base.len, 8 - suffix.len)] & suffix
    used[reel] = src
    result[src] = reel

func transitionName(kind: TransitionKind, video: bool): string =
  if not video and kind == tkDissolve: "CONSTANT GAIN"
  else: transitionInfo[kind].name.toUpperAscii

func transitionCode(kind: TransitionKind): string =
  if kind == tkWipe: "W001" else: "D"

type TrackExport = object
  channel: Channel
  video: bool
  clips: seq[Clip]
  transitions: seq[Transition]

proc trackEvents(tl: v3, track: TrackExport, reels: Table[ptr string, string],
    paths: Table[ptr string, string], base: int64, drop: bool): seq[Event] =
  let plan = transitionPlan(track.clips, track.transitions)
  let order = (if track.video: 0 else: ord(track.channel))

  proc sourceAt(clip: Clip, frame: int64): int64 =
    ## The source frame a clip shows at timeline `frame`, which may lie just
    ## past its ends.
    let map = initSpeedMap(tl.effects[clip.effects])
    int64(round((clip.offset.float64 + float64(frame - clip.start)) * map.mean))

  for j, clip in track.clips:
    if clip.src == nil: continue
    let reel = reels[clip.src]
    let speed = initSpeedMap(tl.effects[clip.effects]).mean
    let name = extractFilename(clip.src[])
    let clipEnd = clip.start + clip.dur
    var recIn = clip.start
    var recOut = clipEnd
    var ev = Event(channels: {track.channel})
    var fromLine = Line(dur: -1)
    var hasFrom = false

    if plan[j].outgoing >= 0:
      let t = track.transitions[plan[j].outgoing]
      # The record out of this clip's own event is where the transition
      # begins; the transition's event carries the rest.
      recOut = t.spanStart
    if plan[j].incoming >= 0:
      let t = track.transitions[plan[j].incoming]
      recIn = t.spanStart
      hasFrom = true
      if t.alignment == taStart or j == 0 or track.clips[j - 1].src == nil:
        fromLine.reel = "BL"
      else:
        let prev = track.clips[j - 1]
        fromLine.reel = reels[prev.src]
        let src = prev.sourceAt(recIn)
        fromLine.srcIn = src
        fromLine.srcOut = src
        ev.comments.add "FROM CLIP NAME: " & extractFilename(prev.src[])
      fromLine.trans = "C"
      fromLine.recIn = recIn
      fromLine.recOut = recIn
      ev.lines.add fromLine
      var line = Line(reel: reel, trans: transitionCode(t.kind), dur: t.dur)
      line.srcIn = max(0'i64, clip.sourceAt(recIn))
      line.srcOut = line.srcIn + (recOut - recIn)
      line.recIn = recIn
      line.recOut = recOut
      ev.lines.add line
      ev.comments.add "TO CLIP NAME: " & name
      ev.comments.add "SOURCE FILE: " & paths[clip.src]
      ev.comments.add "EFFECT NAME: " & transitionName(t.kind, track.video)
    else:
      let srcIn = clip.sourceAt(recIn)
      ev.lines.add Line(reel: reel, trans: "C", dur: -1, srcIn: srcIn,
        srcOut: srcIn + (recOut - recIn), recIn: recIn, recOut: recOut)
      ev.comments.add "FROM CLIP NAME: " & name
      ev.comments.add "SOURCE FILE: " & paths[clip.src]

    if speed != 1.0:
      # `M2 REEL fps source-in`: the source frames played a second.
      ev.m2Reel = reel
      ev.m2 = &"{speed * base.float64:05.1f}" & "                " &
        formatTimecode(ev.lines[^1].srcIn, base, drop)
    ev.mergeable = not hasFrom and speed == 1.0
    ev.key = (clip.src, clip.stream, recIn, recOut, ev.lines[^1].srcIn)
    ev.order = (recIn, order)
    if recOut > recIn:
      result.add ev

    if plan[j].outgoing >= 0:
      let t = track.transitions[plan[j].outgoing]
      if t.alignment == taEnd:
        # Fade to black: the clip plays on under the transition.
        let src = clip.sourceAt(recOut)
        var fade = Event(channels: {track.channel}, order: (recOut, order))
        fade.lines.add Line(reel: reel, trans: "C", dur: -1, srcIn: src,
          srcOut: src, recIn: recOut, recOut: recOut)
        fade.lines.add Line(reel: "BL", trans: transitionCode(t.kind),
          dur: t.dur, srcIn: 0, srcOut: t.dur, recIn: recOut,
          recOut: recOut + t.dur)
        fade.comments.add "FROM CLIP NAME: " & name
        fade.comments.add "EFFECT NAME: " & transitionName(t.kind, track.video)
        result.add fade

proc edlWrite*(name, output: string, tl: v3) =
  let base = timecodeBase(tl.tb)
  # Drop-frame numbering exists only for 29.97 and 59.94, where editors
  # expect it so record timecode keeps up with the clock.
  let drop = tl.tb.den == 1001 and tl.tb.num mod 30000 == 0
  let reels = assignReels(tl)
  # absolutePath reads the cwd from the OS each call; resolve each file once.
  var paths: Table[ptr string, string]
  for src in reels.keys:
    paths[src] = absolutePath(src[])

  var tracks: seq[TrackExport]
  if tl.v.len > 0:
    tracks.add TrackExport(channel: chV, video: true, clips: tl.v[0],
      transitions: (if tl.vt.len > 0: tl.vt[0] else: @[]))
  for i in 0 ..< min(tl.a.len, 4):
    tracks.add TrackExport(channel: Channel(ord(chA1) + i), clips: tl.a[i],
      transitions: (if i < tl.at.len: tl.at[i] else: @[]))
  if tl.a.len > 4:
    warning "EDLs hold four audio channels; audio tracks past the fourth were left out"

  var events: seq[Event]
  var mergeable: Table[EventKey, seq[int]] # key to events, in order
  for track in tracks:
    for ev in trackEvents(tl, track, reels, paths, base, drop):
      var merged = false
      if ev.mergeable:
        for i in mergeable.getOrDefault(ev.key):
          if channelCode(events[i].channels + ev.channels) != "":
            events[i].channels.incl ev.channels
            merged = true
            break
      if not merged:
        if ev.mergeable:
          mergeable.mgetOrPut(ev.key, @[]).add events.len
        events.add ev
  events.sort(proc (a, b: Event): int = cmp(a.order, b.order))

  var text = "TITLE: " & name & "\n"
  text.add (if drop: "FCM: DROP FRAME\n" else: "FCM: NON-DROP FRAME\n")
  for i, ev in events:
    text.add "\n"
    let num = align($(i + 1), 3, '0')
    let chan = channelCode(ev.channels)
    for line in ev.lines:
      let dur = (if line.dur < 0: "" else: align($line.dur, 3, '0'))
      text.add &"{num}  {line.reel:<8} {chan:<5} {line.trans:<4} {dur:>3} "
      text.add formatTimecode(line.srcIn, base, drop) & " " &
        formatTimecode(line.srcOut, base, drop) & " " &
        formatTimecode(line.recIn, base, drop) & " " &
        formatTimecode(line.recOut, base, drop) & "\n"
    if ev.m2 != "":
      text.add &"M2   {ev.m2Reel:<8}       {ev.m2}\n"
    for c in ev.comments:
      text.add "* " & c & "\n"

  if output == "-":
    stdout.write text
  else:
    writeFile(output, text)
