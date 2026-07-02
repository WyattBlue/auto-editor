import std/[json, strformat]

import ../[action, av, ffmpeg, media, log, timeline]
import ../util/[color, lang, rational]

proc parseActionOrErr(val: string): Action {.raises: [].} =
  try: parseAction(val)
  except ActionParseError as e: error e.msg

proc parseClip(node: JsonNode, interner: var StringInterner, effects: var seq[Actions]): Clip {.raises: [].} =
  let srcNode = node{"src"}
  if srcNode != nil and srcNode.kind == JNull:
    result.src = nil # synthesized base clip: a render canvas with no media
  else:
    let srcVal = srcNode.getStr("")
    if srcVal == "":
      error "Invalid src json value"
    result.src = interner.intern(srcVal)

  result.start = node{"start"}.getBiggestInt(-1)
  result.dur = node{"dur"}.getBiggestInt(-1)
  result.offset = node{"offset"}.getBiggestInt(-1)
  if result.start < 0:
    error "Invalid start json value"
  if result.dur <= 0:
    error "Invalid dur json value"
  if result.offset < 0:
    error "Invalid offset json value"

  let streamVal = node{"stream"}.getInt(0)
  if streamVal > 1000 or streamVal < 0:
    error &"Invalid stream: {streamVal}"

  result.stream = streamVal.int16

  var group = aNil
  if node{"effects"} != nil and node{"effects"}.kind == JArray:
    var list: seq[Action]
    for effectNode in node{"effects"}:
      let effectStr = effectNode.getStr()
      if effectStr == "cut":
        group = aCut
        break
      elif effectStr != "nil":
        list.add parseActionOrErr(effectStr)
    if group.isEmpty:
      try: group = newActions(list)
      except ActionParseError: error "Too many actions"

  let effectIndex = effects.find(group)
  if effectIndex == -1:
    effects.add(group)
    result.effects = uint32(effects.len - 1)
  else:
    result.effects = uint32(effectIndex)

proc parseV3*(jsonNode: JsonNode, interner: var StringInterner): v3 {.raises: [].} =
  let tbString = jsonNode{"timebase"}.getStr("")
  if tbString == "":
    error "Expected 'timebase' key to exist"
  result.tb = try: toAVRational(tbString) except ValueError as e: error e.msg
  if not result.tb.isValid:
    error "Invalid timebase json value"

  let srVal = jsonNode{"samplerate"}.getInt(0)
  if srVal > high(cint) or srVal < 100:
    error "Invalid samplerate json value"
  result.sr = srVal.cint

  let bgNode = jsonNode{"background"}
  if bgNode == nil:
    error "Expected 'background' key to exist"
  if bgNode.kind != JString:
    error "Expected 'background' key to be a string"
  result.bg = (
    try: parseColor(bgNode.getStr())
    except ValueError as e: error e.msg
  )

  result.layout = initLayout(jsonNode{"layout"}.getStr(""))

  let resArray = jsonNode{"resolution"}
  if resArray == nil:
    error "Expected 'resolution' to exist"
  if resArray.kind != JArray:
    error "Expected 'resolution' to be an array"
  if resArray.len >= 2:
    let w = resArray[0].getInt()
    let h = resArray[1].getInt()
    if w < 2 or w > high(int32).int or h < 2 or h > high(int32).int or
        ((w or h) and 1) != 0:
      error "Resolution must be even and >= 2"
    result.res = (w.int32, h.int32)
  else:
    error "Expected two elements in 'resolution' key"

  result.effects = @[]

  let vNode = jsonNode{"v"}
  if vNode != nil and vNode.kind == JArray:
    for trackNode in vNode:
      var track: seq[Clip]
      if trackNode.kind == JArray:
        for videoNode in trackNode:
          track.add(parseClip(videoNode, interner, result.effects))
      result.v.add track

  # Parse audio tracks
  let aNode = jsonNode{"a"}
  if aNode != nil and aNode.kind == JArray:
    for trackNode in aNode:
      var track: seq[Clip]
      if trackNode.kind == JArray:
        for audioNode in trackNode:
          track.add(parseClip(audioNode, interner, result.effects))
      result.a.add track

  let langsNode = jsonNode{"langs"}
  if langsNode != nil and langsNode.kind == JArray:
    for trackNode in langsNode:
      result.langs.add toLang(trackNode.getStr())

  if result.langs.len > result.v.len + result.a.len:
    result.langs.setLen(result.v.len + result.a.len)

  while result.langs.len < result.v.len + result.a.len:
    result.langs.add ['u', 'n', 'd', '\0']

  let tf = jsonNode{"templateFile"}.getStr("")
  result.templateFile = if tf != "": interner.intern(tf) else: result.firstSource


proc parseV2*(jsonNode: JsonNode, interner: var StringInterner): v3 {.raises: [].} =
  let input = jsonNode{"source"}.getStr("")
  if input == "":
    error "source is a required field"

  let ptrInput = intern(interner, input)
  var effects: seq[Actions]
  var clips: seq[Clip2]

  let tbString = jsonNode{"tb"}.getStr("")
  if tbString == "":
    error "Expected 'tb' key to exist"
  let tb = try: toAVRational(tbString) except ValueError as e: error e.msg
  if not tb.isValid:
    error "Invalid timebase json value"

  let clipsNode = jsonNode{"clips"}
  if clipsNode != nil and clipsNode.kind == JArray:
    for chunkNode in clipsNode:
      if chunkNode.kind == JArray and chunkNode.len >= 3:
        let start: int64 = chunkNode[0].getBiggestInt()
        let `end`: int64 = chunkNode[1].getBiggestInt()
        let effIdx = chunkNode[2].getBiggestInt()
        if effIdx < 0 or effIdx > high(uint32).int64:
          error "Invalid effect index"
        clips.add Clip2(start: start, `end`: `end`, effect: uint32(effIdx))

  let effectsNode = jsonNode{"effects"}
  if effectsNode != nil and effectsNode.kind == JArray:
    for effectNode in effectsNode:
      var group = aNil
      if effectNode.kind == JArray:
        var list: seq[Action]
        for actionNode in effectNode:
          let s = actionNode.getStr()
          if s == "cut":
            group = aCut
            break
          elif s != "nil":
            list.add parseActionOrErr(s)
        if group.isEmpty:
          try: group = newActions(list)
          except ActionParseError: error "Too many actions"
      else:
        error "effects must be a list of lists"

      let effectIndex = effects.find(group)
      if effectIndex == -1:
        effects.add(group)

  let mi = (
    try: initMediaInfo(input)
    except IOError as e: error e.msg
  )
  result = toNonLinear2(ptrInput, tb, mi, clips, effects)


proc parseV1*(jsonNode: JsonNode, interner: var StringInterner): v3 {.raises: [].} =
  let input = jsonNode{"source"}.getStr("")
  if input == "":
    error "source is a required field"
  let ptrInput = intern(interner, input)

  let chunksNode = jsonNode{"chunks"}
  if chunksNode == nil:
    error "chunks is a required field"
  if chunksNode.kind != JArray:
    error "chunks must be an array"

  var chunks = newSeqOfCap[(int64, int64, float64)](chunksNode.len)
  for chunkNode in chunksNode:
    if chunkNode.kind != JArray or chunkNode.len != 3:
      error "Invalid chunk structure"
    let start: int64 = chunkNode[0].getBiggestInt()
    let `end`: int64 = chunkNode[1].getBiggestInt()
    let speed = chunkNode[2].getFloat()
    chunks.add (start, `end`, speed)

  let mi = (
    try: initMediaInfo(input)
    except IOError as e: error e.msg
  )
  let tb = (
    if mi.v.len > 0: makeSaneTimebase(mi.v[0].avgRate)
    else: AVRational(num: 30, den: 1)
  )
  result = toNonLinear(ptrInput, tb, mi, chunks)

proc readJson*(jsonStr: string, interner: var StringInterner): v3 =
  let jsonNode = try: parseJson(jsonStr)
    except CatchableError as e: error "Invalid JSON: " & e.msg
  let version = jsonNode{"version"}.getStr("unknown")

  case version:
    of "3": return parseV3(jsonNode, interner)
    of "2": return parseV2(jsonNode, interner)
    of "1": return parseV1(jsonNode, interner)
    else: error &"Unsupported version: {version}"
