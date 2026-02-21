import std/[strutils, streams, tables, uri, xmlparser, xmltree]

import ../[ffmpeg, log, timeline]
import ../util/color

func uriToPath(uri: string): string =
  var path = uri
  if path.startsWith("file://localhost/"):
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
    if tb == 24: return AVRational(num: 24000, den: 1001)
    if tb == 30: return AVRational(num: 30000, den: 1001)
    if tb == 60: return AVRational(num: 60000, den: 1001)
    return AVRational(num: (tb * 999).cint, den: 1000)
  return AVRational(num: tb.cint, den: 1)

func readFilters(filterNode: XmlNode): float =
  result = 1.0
  for effectTag in filterNode:
    if effectTag.kind != xnElement: continue
    if effectTag.tag in ["enabled", "start", "end"]: continue
    # Process <effect>: i=0 is <name>, i=1 is <effectid>, i>1 are <parameter>s
    var paramIdx = 0
    for effectChild in effectTag:
      if effectChild.kind != xnElement: continue
      if paramIdx > 1:
        var parmIdx = 0
        var isSpeed = false
        for parm in effectChild:
          if parm.kind != xnElement: continue
          if parmIdx == 0:
            if parm.tag == "parameterid" and parm.innerText.strip() == "speed":
              isSpeed = true
            else:
              break
          elif isSpeed and parm.tag == "value":
            let text = parm.innerText.strip()
            if text != "":
              return parseFloat(text) / 100.0
          inc parmIdx
      inc paramIdx

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

proc getEffect(speed: float, effects: var seq[seq[Action]]): uint32 =
  let actionGroup: seq[Action] =
    if speed == 1.0: @[]
    else: @[Action(kind: actSpeed, val: speed.float32)]
  let idx = effects.find(actionGroup)
  if idx == -1:
    effects.add(actionGroup)
    return uint32(effects.len - 1)
  return uint32(idx)

proc parseTrack(trackNode: XmlNode, sources: var Table[string, ptr string],
                effects: var seq[seq[Action]], interner: var StringInterner): seq[Clip] =
  for trackChild in trackNode:
    if trackChild.kind != xnElement: continue
    if trackChild.tag != "clipitem": continue

    var startVal = 0i64
    var endVal = 0i64
    var inVal = 0i64
    var fileNode: XmlNode = nil
    var filterNode: XmlNode = nil

    for ci in trackChild:
      if ci.kind != xnElement: continue
      case ci.tag
      of "start": startVal = parseInt(ci.innerText.strip())
      of "end": endVal = parseInt(ci.innerText.strip())
      of "in": inVal = parseInt(ci.innerText.strip())
      of "file": fileNode = ci
      of "filter": filterNode = ci
      else: discard

    if fileNode == nil: continue
    let srcPtr = resolveFile(fileNode, sources, interner)
    if srcPtr == nil: continue

    let speed = if filterNode != nil: readFilters(filterNode) else: 1.0
    let dur = endVal - startVal
    let e = getEffect(speed, effects)
    result.add Clip(src: srcPtr, start: startVal, dur: dur, offset: inVal, effects: e, stream: 0)

proc fcp7ReadXml*(path: string, interner: var StringInterner): v3 =
  let xmlContent = readFile(path)
  let stream = newStringStream(xmlContent)
  var parseErrors: seq[string] = @[]
  let root = parseXml(stream, path, parseErrors)
  stream.close()

  if parseErrors.len > 0:
    error "Failed to parse XML: " & parseErrors[0]

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
          timebase = parseInt(rc.innerText.strip())
        elif rc.tag == "ntsc":
          ntsc = rc.innerText.strip() == "TRUE"
      tb = readTbNtsc(timebase, ntsc)
    of "media":
      mediaNode = child
    else: discard

  if mediaNode == nil:
    error "No <media> found in XML"

  var sr: cint = 48000
  var res = (1920, 1080)
  var sources: Table[string, ptr string]
  var effects: seq[seq[Action]] = @[]
  var vobjs: seq[seq[Clip]] = @[]
  var aobjs: seq[seq[Clip]] = @[]

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
              var w = 1920
              var h = 1080
              for sc in fc:
                if sc.kind != xnElement: continue
                if sc.tag == "width": w = parseInt(sc.innerText.strip())
                elif sc.tag == "height": h = parseInt(sc.innerText.strip())
              res = (w, h)
        of "track":
          let clips = parseTrack(vidChild, sources, effects, interner)
          if clips.len > 0:
            vobjs.add clips
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
                  sr = parseInt(sc.innerText.strip()).cint
        of "track":
          let idx = audChild.attr("currentExplodedTrackIndex")
          if idx != "" and idx != "0": continue
          let clips = parseTrack(audChild, sources, effects, interner)
          if clips.len > 0:
            aobjs.add clips
        else: discard
    else: discard

  let bg = RGBColor(red: 0, green: 0, blue: 0)
  result = v3(tb: tb, bg: bg, sr: sr, layout: "stereo", res: res,
              v: vobjs, a: aobjs, effects: effects)
  while result.langs.len < result.v.len + result.a.len:
    result.langs.add ['u', 'n', 'd', '\0']
