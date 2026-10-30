import std/[algorithm, sequtils, strformat, strutils, tables, uri]

import ../[action, av, ffmpeg, log, timeline]
import ../util/[color, rational, xml]

func uriToPath(uri: string): string =
  var path = uri
  if path.startsWith("file://localhost/"):
    # Windows-style: file://localhost/C:/... -> C:/...
    if path.len > 18 and path[18] == ':':
      path = path[17..^1]
    else:
      path = path[16..^1]
  elif path.startsWith("file://"):
    # Windows-style: file:///C:/... -> C:/...
    if path.len > 9 and path[9] == ':':
      path = path[8..^1]
    else:
      # Unix-style: file:///path -> /path
      path = path[7..^1]
  else:
    return uri
  return decodeUrl(path, decodePlus = false)

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
  if pts.len == 1:
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

proc resolveFile(fileNode: XmlNode, sources: var Table[string, ptr string],
                 interner: var StringInterner): ptr string =
  let fileId = fileNode.attr("id")
  if fileId in sources:
    return sources[fileId]
  for fc in fileNode:
    if fc.kind != xnElement: continue
    if fc.tag == "pathurl":
      let filePath = uriToPath(fc.innerText.strip())
      let p = interner.intern(filePath)
      sources[fileId] = p
      return p
  return nil

proc readTransition(node: XmlNode): Transition =
  var startVal, endVal = -1'i64
  var alignment = taCenter
  for c in node:
    if c.kind != xnElement: continue
    case c.tag
    of "start": startVal = xmlInt(c, lo = 0)
    of "end": endVal = xmlInt(c, lo = 0)
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
  # Every transition is read as a dissolve, the only kind the timeline has.
  Transition(kind: tkDissolve, at: startVal + before, dur: dur, alignment: alignment)

proc parseTrack(trackNode: XmlNode, sources: var Table[string, ptr string],
    effects: var seq[Actions], effectIndex: var EffectIndex,
    interner: var StringInterner):
    tuple[clips: seq[Clip], transitions: seq[Transition]] =
  var items: seq[XmlNode]
  for c in trackNode:
    if c.kind == xnElement and c.tag in ["clipitem", "transitionitem"]:
      items.add c
  var parsed = newSeq[Transition](items.len)
  for k, node in items:
    if node.tag == "transitionitem":
      parsed[k] = readTransition(node)
      result.transitions.add parsed[k]

  for k, trackChild in items:
    if trackChild.tag != "clipitem": continue

    var startVal = 0i64
    var endVal = 0i64
    var inVal = 0i64
    var outVal = -1i64
    var fileNode: XmlNode = nil
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
      of "file": fileNode = ci
      of "filter": filterNodes.add ci
      else: discard

    if fileNode == nil: continue
    let srcPtr = resolveFile(fileNode, sources, interner)
    if srcPtr == nil: continue

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
    if outVal <= inVal: outVal = inVal + dur + inExt + outExt
    # <in> is clamped at 0 when the handle runs past the media start, so take
    # the offset from <out> instead.
    let offset = (if inExt > 0: max(0'i64, outVal - outExt - dur) else: inVal)
    for fn in filterNodes:
      readFilters(fn, acts, inVal.float, outVal.float)
    let e = effectIndex.intern(effects, newActions(acts))
    result.clips.add Clip(src: srcPtr, start: startVal, dur: dur, offset: offset,
      effects: e, stream: 0)

proc fcp7ReadXml*(path: string, interner: var StringInterner): v3 =
  let root = parseXmlFile(path)
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
  var sources: Table[string, ptr string]
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
          let (clips, transitions) = parseTrack(vidChild, sources, effects,
            effectIndex, interner)
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
          let (clips, transitions) = parseTrack(audChild, sources, effects,
            effectIndex, interner)
          if clips.len > 0:
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
  result.layout = initLayout("stereo")
  while result.langs.len < result.v.len + result.a.len:
    result.langs.add ['u', 'n', 'd', '\0']
