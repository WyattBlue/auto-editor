import std/[algorithm, sequtils, strformat, strutils, tables]
from std/math import round

import ../[action, ffmpeg, log, timeline]
import ../util/[color, fun, rational, xml]

# Tags common in FCP7 XML, so the parsed tree can share their strings.
const fcp7Tags = ["xmeml", "sequence", "media", "video", "audio", "track",
  "clipitem", "transitionitem", "file", "name", "start", "end", "in", "out",
  "enabled", "mediatype", "trackindex", "link", "linkclipref", "clipindex",
  "sourcetrack", "labels", "label2", "compositemode", "filter", "effect",
  "effectid", "effecttype", "parameter", "parameterid", "value", "valuemin",
  "valuemax", "keyframe", "when", "rate", "timebase", "ntsc", "duration",
  "pathurl", "masterclipid", "pproTicksIn", "pproTicksOut", "alphatype",
  "pixelaspectratio", "anamorphic", "logginginfo", "colorinfo", "comments"]

func readTbNtsc(tb: int, ntsc: bool): AVRational =
  if ntsc:
    # ntsc scales the timebase by 1000/1001 (30 -> 29.97002997...), per the
    # chart in Apple's FCP7 XML docs; see the link in exports/fcp7.nim.
    return tb.int64 * AVRational(num: 1000, den: 1001)
  return AVRational(num: tb.cint, den: 1)

proc xmlInt(node: XmlNode, lo = low(int64), hi = high(int64)): int64 =
  let s = node.innerText.strip()
  result = try: parseBiggestInt(s)
    except ValueError: error &"Invalid <{node.tag}> value: '{s}'"
  if result < lo or result > hi:
    error &"Invalid <{node.tag}> value: '{s}'"

func num(s: string): (bool, float) =
  try: (true, parseFloat(s.strip()))
  except ValueError: (false, 0.0)

func readParam(parmNode: XmlNode): (string, seq[(float, float)]) =
  for c in parmNode:
    if c.kind != xnElement: continue
    case c.tag
    of "parameterid":
      result[0] = c.innerText.strip()
    of "value":
      let (ok, v) = num(c.innerText)
      if ok: result[1].add (0.0, v)
    of "keyframe":
      var timeOk, valOk = false
      var time, value = 0.0
      for kc in c:
        if kc.kind != xnElement: continue
        case kc.tag
        of "when": (timeOk, time) = num(kc.innerText)
        of "value": (valOk, value) = num(kc.innerText)
        else: discard
      if timeOk and valOk: result[1].add (time, value)
    else: discard

func addFixed(acts: var seq[Action], act: Action) =
  for a in acts:
    if a.kind == act.kind: return
  acts.add act

func lerpAt(pts: seq[(float, float)], time: float): float =
  if time <= pts[0][0]: return pts[0][1]
  for i in 1 ..< pts.len:
    let (t0, v0) = pts[i - 1]
    let (t1, v1) = pts[i]
    if time <= t1:
      if t1 <= t0: return v1
      return v0 + (v1 - v0) * (time - t0) / (t1 - t0)
  pts[^1][1]

func onGrid(pts: seq[(float, float)], srcIn, span: float): bool =
  for i, p in pts:
    if abs(p[0] - (srcIn + float(i) / float(pts.len - 1) * span)) > 0.5:
      return false
  true

func kfSeq(pts: seq[(float, float)], srcIn, srcOut, scale, lo, hi: float):
    seq[float32] =
  if pts.len == 0: return
  # Premiere keyframes even an untouched opacity, as a run of equal values.
  if pts.allIt(it[1] == pts[0][1]):
    if pts[0][1] * scale == 1.0: return
    return @[clamp(pts[0][1] * scale, lo, hi).float32]

  let ordered = pts.sorted
  let span = max(srcOut - srcIn - 1.0, 1.0)
  if ordered.len <= 255 and ordered.onGrid(srcIn, span):
    for p in ordered:
      result.add clamp(p[1] * scale, lo, hi).float32
    return

  let n = min(int(span) + 1, 255)
  for i in 0 ..< n:
    let time = srcIn + float(i) / float(n - 1) * span
    result.add clamp(ordered.lerpAt(time) * scale, lo, hi).float32

proc readFilters(filterNode: XmlNode, acts: var seq[Action],
    srcIn, srcOut: float) =
  for c in filterNode:
    if c.kind == xnElement and c.tag == "enabled" and
        c.innerText.strip() == "FALSE":
      return

  for effectTag in filterNode:
    if effectTag.kind != xnElement or effectTag.tag != "effect": continue

    var effectId = ""
    var params: Table[string, seq[(float, float)]]
    for effectChild in effectTag:
      if effectChild.kind != xnElement: continue
      if effectChild.tag == "effectid":
        effectId = effectChild.innerText.strip()
      elif effectChild.tag == "parameter":
        let (id, vals) = readParam(effectChild)
        if id != "" and vals.len > 0:
          params[id] = vals

    case effectId
    of "timeremap":
      if "speed" in params:
        let speed = float32(params["speed"][0][1] / 100.0)
        if speed > 0.0 and speed < 99999.0 and speed != 1.0:
          acts.addFixed Action(kind: actSpeed, val: speed)
    of "opacity":
      let kf = kfSeq(params.getOrDefault("opacity"), srcIn, srcOut, 0.01, 0.0, 1.0)
      if kf.len > 0:
        acts.addFixed Action(kind: actOpacity, kf: kf)
    of "audiolevels":
      let kf = kfSeq(params.getOrDefault("level"), srcIn, srcOut, 1.0, 0.0, 3.98109)
      if kf.len > 0:
        acts.addFixed Action(kind: actVolume, kf: kf)
    else: discard

type FileInfo = object
  src: ptr string
  channels: seq[int] # each audio stream's channel count, in stream order

proc resolveFile(fileNode: XmlNode, files: var Table[string, FileInfo],
    interner: var StringInterner): FileInfo =
  ## A file is described once; later clips refer to it by id alone.
  let fileId = fileNode.attr("id")
  if fileId in files:
    return files[fileId]
  for fc in fileNode:
    if fc.kind != xnElement: continue
    if fc.tag == "pathurl":
      result.src = interner.intern(uriToPath(fc.innerText.strip()))
    elif fc.tag == "media":
      for m in fc:
        if m.kind != xnElement or m.tag != "audio": continue
        var channels = 2
        for a in m:
          if a.kind == xnElement and a.tag == "channelcount":
            channels = int(xmlInt(a, 1, 64))
        result.channels.add channels
  if result.src != nil:
    files[fileId] = result

func streamOf(file: FileInfo, trackIndex: int64): tuple[stream: int16, firstChannel: bool] =
  ## The audio stream holding the file's 1-based channel `trackIndex`, and
  ## whether it is that stream's first channel. Premiere points both sides of
  ## a stereo pair at its first channel.
  var first = 1'i64
  for i, n in file.channels:
    if trackIndex < first + n: return (int16(i), trackIndex == first)
    first += n
  (0'i16, true)

proc readTransition(node: XmlNode, audio: bool): Transition =
  var startVal, endVal = -1'i64
  var alignment = taCenter
  var kind = tkDissolve
  for c in node:
    if c.kind != xnElement: continue
    case c.tag
    of "start": startVal = xmlInt(c, lo = 0)
    of "end": endVal = xmlInt(c, lo = 0)
    of "effect":
      # An unknown transition plays as a dissolve.
      for f in c:
        if f.kind == xnElement and f.tag in ["effectid", "name"] and
            kindFromName(f.innerText.strip(), not audio, kind):
          break
    of "alignment":
      alignment = case c.innerText.strip()
        of "start", "start-black": taStart
        of "center": taCenter
        of "end", "end-black": taEnd
        else: error &"Unsupported transition alignment: '{c.innerText.strip()}'"
    else: discard
  if startVal < 0 or endVal <= startVal:
    error "Invalid transitionitem: <start> must come before <end>"
  let dur = endVal - startVal
  let before = case alignment
    of taStart: 0'i64
    of taCenter: dur div 2
    of taEnd: dur
  Transition(kind: kind, at: startVal + before, dur: dur, alignment: alignment)

proc generatorColor(effect: XmlNode): (bool, RGBColor) =
  ## The color a Slug or Color generator fills the frame with. Titles, bars
  ## and the rest have no such color.
  var name, id: string
  var color = RGBColor(red: 0, green: 0, blue: 0)
  for c in effect:
    if c.kind != xnElement: continue
    case c.tag
    of "name": name = c.innerText.strip().toLowerAscii()
    of "effectid": id = c.innerText.strip().toLowerAscii()
    of "parameter":
      var isFill = false
      var value: XmlNode = nil
      for pc in c:
        if pc.kind != xnElement: continue
        if pc.tag == "parameterid": isFill = pc.innerText.strip() == "fillcolor"
        elif pc.tag == "value": value = pc
      if isFill and value != nil:
        for ch in value:
          if ch.kind != xnElement or ch.tag notin ["red", "green", "blue"]: continue
          let v = uint8(xmlInt(ch, 0, 255))
          case ch.tag
          of "red": color.red = v
          of "green": color.green = v
          else: color.blue = v
    else: discard
  if id == "slug" or name in ["slug", "black video"]: return (true, color)
  if id == "color" or name in ["color", "color matte", "colour matte"]:
    return (true, color)
  (false, color)

proc parseTrack(trackNode: XmlNode, files: var Table[string, FileInfo],
    effects: var seq[Actions], effectIndex: var EffectIndex,
    interner: var StringInterner, audio: bool, res: (int32, int32),
    tb: AVRational, dropped: var CountTable[string]):
    tuple[clips: seq[Clip], transitions: seq[Transition], laterChannels: bool] =
  ## `laterChannels` is set when every audio clip names a channel past the
  ## first of its stream, as on the per-channel tracks resolve-fcp7 writes.
  result.laterChannels = audio
  var items: seq[XmlNode]
  for c in trackNode:
    if c.kind == xnElement and
        c.tag in ["clipitem", "generatoritem", "transitionitem"]:
      items.add c
  var parsed = newSeq[Transition](items.len)
  for k, node in items:
    if node.tag == "transitionitem":
      parsed[k] = readTransition(node, audio)
      result.transitions.add parsed[k]

  for k, trackChild in items:
    if trackChild.tag == "transitionitem": continue
    let generator = trackChild.tag == "generatoritem"

    var startVal = 0i64
    var endVal = 0i64
    var inVal = 0i64
    var outVal = -1i64
    var ticksIn = -1'i64
    var fileNode, effectNode: XmlNode = nil
    var nested = false
    var enabled = true
    var trackIndex = 1'i64
    var acts: seq[Action]
    var filterNodes: seq[XmlNode]

    for ci in trackChild:
      if ci.kind != xnElement: continue
      case ci.tag
      # -1 marks a start or end inside a transition.
      of "start": startVal = xmlInt(ci, lo = -1)
      of "end": endVal = xmlInt(ci, lo = -1)
      of "in": inVal = xmlInt(ci, lo = 0)
      of "out": outVal = xmlInt(ci, lo = -1)
      of "pproTicksIn": ticksIn = xmlInt(ci, lo = 0)
      of "file": fileNode = ci
      of "effect": effectNode = ci
      of "sequence": nested = true
      of "enabled": enabled = ci.innerText.strip() != "FALSE"
      of "filter": filterNodes.add ci
      of "sourcetrack":
        for st in ci:
          if st.kind == xnElement and st.tag == "trackindex":
            trackIndex = xmlInt(st, 1, high(int32))
      else: discard

    if not enabled: continue
    var fill: RGBColor
    var file: FileInfo
    if generator:
      var known = false
      if effectNode != nil: (known, fill) = generatorColor(effectNode)
      if not known or audio:
        dropped.inc "generated clip"
        continue
    elif fileNode == nil:
      if nested: dropped.inc "nested sequence"
      continue
    else:
      file = resolveFile(fileNode, files, interner)
      if file.src == nil: continue

    # An edge inside a transition is the transition's edit point. A centered
    # transition also extends the clip's media by its half on that side.
    var inExt, outExt = 0'i64
    if startVal == -1:
      if k == 0 or items[k - 1].tag != "transitionitem":
        error "clipitem <start> of -1 has no transition before it"
      let t = parsed[k - 1]
      startVal = t.at
      if t.alignment == taCenter: inExt = t.dur div 2
    if endVal == -1:
      if k + 1 >= items.len or items[k + 1].tag != "transitionitem":
        error "clipitem <end> of -1 has no transition after it"
      let t = parsed[k + 1]
      endVal = t.at
      if t.alignment == taCenter: outExt = t.dur - t.dur div 2
    if endVal <= startVal:
      error "Invalid clipitem: <start> must come before <end>"
    let dur = endVal - startVal
    if generator:
      # A source-less clip paints its effects on the canvas.
      let box = Action(kind: actDrawbox, dbX: 0, dbY: 0, dbW: res[0], dbH: res[1],
        dbColor: fill)
      result.clips.add Clip(src: nil, start: startVal, dur: dur,
        effects: effectIndex.intern(effects, newActions(@[box])))
      continue
    if outVal <= inVal: outVal = inVal + dur + inExt + outExt
    for fn in filterNodes:
      readFilters(fn, acts, inVal.float, outVal.float)
    var speed = 1.0
    for a in acts:
      if a.kind == actSpeed: speed *= a.val
    # <in> is clamped at 0 when the handle runs past the media start, so take
    # the offset from <out> instead. Premiere's ticks give the source time
    # exactly, where <in> is rounded to a frame after the speed change.
    let offset =
      if inExt > 0: max(0'i64, outVal - outExt - dur)
      elif ticksIn >= 0:
        int64(round(ticksIn.float * tb.float / pproTicksPerSecond.float / speed))
      else: inVal
    let e = effectIndex.intern(effects, newActions(acts))
    var stream = 0'i16
    if audio:
      let (s, firstChannel) = file.streamOf(trackIndex)
      stream = s
      if firstChannel: result.laterChannels = false
    result.clips.add Clip(src: file.src, start: startVal, dur: dur,
      offset: offset, effects: e, stream: stream)

proc fcp7ReadXml*(path: string, interner: var StringInterner): v3 =
  let root = parseXmlFile(path, fcp7Tags)
  if root == nil or root.tag != "xmeml":
    let tag = if root == nil: "nil" else: root.tag
    error "Expected 'xmeml' root tag, got '" & tag & "'"

  var seqNode: XmlNode = nil
  for child in root:
    if child.kind == xnElement and child.tag == "sequence":
      seqNode = child
      break

  if seqNode == nil:
    error "No <sequence> found in XML"

  var tb = AVRational(num: 30, den: 1)
  var mediaNode: XmlNode = nil

  for child in seqNode:
    if child.kind != xnElement: continue
    case child.tag
    of "rate":
      var timebase = 30
      var ntsc = false
      for rc in child:
        if rc.kind != xnElement: continue
        if rc.tag == "timebase":
          timebase = xmlInt(rc, 1, high(cint)).int
        elif rc.tag == "ntsc":
          ntsc = rc.innerText.strip() == "TRUE"
      tb = readTbNtsc(timebase, ntsc)
    of "media":
      mediaNode = child
    else: discard

  if mediaNode == nil:
    error "No <media> found in XML"

  var sr: cint = 48000
  var res = (1920'i32, 1080'i32)
  var files: Table[string, FileInfo]
  var dropped: CountTable[string]
  var effects: seq[Actions] = @[]
  var effectIndex: EffectIndex
  var vobjs: seq[seq[Clip]] = @[]
  var aobjs: seq[seq[Clip]] = @[]
  var vtrans, atrans: seq[seq[Transition]]

  for mediaChild in mediaNode:
    if mediaChild.kind != xnElement: continue
    case mediaChild.tag
    of "video":
      for vidChild in mediaChild:
        if vidChild.kind != xnElement: continue
        case vidChild.tag
        of "format":
          for fc in vidChild:
            if fc.kind != xnElement: continue
            if fc.tag == "samplecharacteristics":
              var w = 1920'i32
              var h = 1080'i32
              for sc in fc:
                if sc.kind != xnElement: continue
                if sc.tag == "width": w = xmlInt(sc, 1, high(int32)).int32
                elif sc.tag == "height": h = xmlInt(sc, 1, high(int32)).int32
              res = (w, h)
        of "track":
          let (clips, transitions, _) = parseTrack(vidChild, files, effects,
            effectIndex, interner, audio = false, res, tb, dropped)
          if clips.len > 0:
            vobjs.add clips
            vtrans.add transitions
        else: discard
    of "audio":
      for audChild in mediaChild:
        if audChild.kind != xnElement: continue
        case audChild.tag
        of "format":
          for fc in audChild:
            if fc.kind != xnElement: continue
            if fc.tag == "samplecharacteristics":
              for sc in fc:
                if sc.kind != xnElement: continue
                if sc.tag == "samplerate":
                  sr = xmlInt(sc, 1, high(cint)).cint
        of "track":
          let idx = audChild.attr("currentExplodedTrackIndex")
          if idx != "" and idx != "0": continue
          let (clips, transitions, laterChannels) = parseTrack(audChild, files,
            effects, effectIndex, interner, audio = true, res, tb, dropped)
          # Clips play whole streams, which the stream's first-channel track
          # already holds.
          if clips.len > 0 and not laterChannels:
            aobjs.add clips
            atrans.add transitions
        else: discard
    else: discard

  let bg = RGBColor(red: 0, green: 0, blue: 0)
  result = v3(tb: tb, bg: bg, sr: sr, res: res, v: vobjs, a: aobjs, effects: effects)
  if vtrans.anyIt(it.len > 0) or atrans.anyIt(it.len > 0):
    result.vt = vtrans
    result.at = atrans
    result.validateTransitions()
  result.templateFile = result.firstSource
  result.updateNumberOfSrc()
  # The layout of the first audio clip's stream, as rendering its source would.
  var channels = 2
  if aobjs.len > 0 and aobjs[0].len > 0:
    let first = aobjs[0][0]
    for file in files.values:
      if file.src == first.src and first.stream < file.channels.len:
        channels = file.channels[first.stream]
        break
  result.layout = (ref AVChannelLayout)()
  av_channel_layout_default(addr result.layout[], channels.cint)
  while result.langs.len < result.v.len + result.a.len:
    result.langs.add ['u', 'n', 'd', '\0']

  if dropped.len > 0:
    var parts: seq[string]
    for what, count in dropped:
      parts.add (if count == 1: &"1 {what}" else: &"{count} {what}s")
    parts.sort()
    warning "Left out of the import: " & parts.join(", ")
