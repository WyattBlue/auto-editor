import std/[json, strformat]

import ../[action, av, ffmpeg, media, log, timeline]
import ../util/[color, lang, rational]

proc parseActionOrErr(val: string): Action {.raises: [].} =
  try: parseAction(val)
  except ActionParseError as e: error e.msg

proc parseClip(node: JsonNode, interner: var StringInterner, effects: var seq[Actions]): Clip =
  result.src = interner.intern(node["src"].getStr())
  result.start = node["start"].getInt()
  result.dur = node["dur"].getInt()
  result.offset = node["offset"].getInt()
  result.stream = node["stream"].getInt().int32

  var group = aNil
  if node.hasKey("effects") and node["effects"].kind == JArray:
    var list: seq[Action]
    for effectNode in node["effects"]:
      let effectStr = effectNode.getStr()
      if effectStr == "cut":
        group = aCut
        break
      elif effectStr != "nil":
        list.add parseActionOrErr(effectStr)
    if group.isEmpty:
      group = newActions(list)

  let effectIndex = effects.find(group)
  if effectIndex == -1:
    effects.add(group)
    result.effects = uint32(effects.len - 1)
  else:
    result.effects = uint32(effectIndex)

proc parseV3*(jsonNode: JsonNode, interner: var StringInterner): v3 =
  result.tb = (
    try: jsonNode["timebase"].getStr()
    except ValueError as e: error e.msg
  )
  if not jsonNode.hasKey("samplerate"):
    error "Expected 'samplerate' key to exist"
  result.sr = jsonNode["samplerate"].getInt().cint

  if not jsonNode.hasKey("background"):
    error "Expected 'background' key to exist"
  if jsonNode["background"].kind != JString:
    error "Expected 'background' key to be a string"
  result.bg = (
    try: parseColor(jsonNode["background"].getStr())
    except ValueError as e: error e.msg
  )

  if not jsonNode.hasKey("layout"):
    error "Expected 'layout' key to exist"
  result.layout = initLayout(jsonNode["layout"].getStr())

  if not jsonNode.hasKey("resolution"):
    error "Expected 'resolution' to exist"
  if jsonNode["resolution"].kind != JArray:
    error "Expected 'resolution' to be an array"
  let resArray = jsonNode["resolution"]
  if resArray.len >= 2:
    result.res = (resArray[0].getInt().int32, resArray[1].getInt().int32)
  else:
    error "Expected two elements in 'resolution' key"

  result.effects = @[]

  if jsonNode.hasKey("v") and jsonNode["v"].kind == JArray:
    for trackNode in jsonNode["v"]:
      var track: seq[Clip]
      if trackNode.kind == JArray:
        for videoNode in trackNode:
          track.add(parseClip(videoNode, interner, result.effects))
      result.v.add track

  # Parse audio tracks
  if jsonNode.hasKey("a") and jsonNode["a"].kind == JArray:
    for trackNode in jsonNode["a"]:
      var track: seq[Clip]
      if trackNode.kind == JArray:
        for audioNode in trackNode:
          track.add(parseClip(audioNode, interner, result.effects))
      result.a.add track

  if jsonNode.hasKey("langs") and jsonNode["langs"].kind == JArray:
    for trackNode in jsonNode["langs"]:
      result.langs.add toLang(trackNode.getStr())

  if result.langs.len > result.v.len + result.a.len:
    result.langs.setLen(result.v.len + result.a.len)

  while result.langs.len < result.v.len + result.a.len:
    result.langs.add ['u', 'n', 'd', '\0']


proc parseV2*(jsonNode: JsonNode, interner: var StringInterner): v3 =
  let input = jsonNode["source"].getStr()
  let ptrInput = intern(interner, input)
  var effects: seq[Actions]
  var clips: seq[Clip2]
  let tb: AVRational = jsonNode["tb"].getStr()

  if jsonNode.hasKey("clips") and jsonNode["clips"].kind == JArray:
    for chunkNode in jsonNode["clips"]:
      if chunkNode.kind == JArray and chunkNode.len >= 3:
        let start: int64 = chunkNode[0].getInt()
        let `end`: int64 = chunkNode[1].getInt()
        let effect = uint32(chunkNode[2].getInt())
        clips.add Clip2(start: start, `end`: `end`, effect: effect)

  if jsonNode.hasKey("effects") and jsonNode["effects"].kind == JArray:
    for effectNode in jsonNode["effects"]:
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
          group = newActions(list)
      else:
        error "effects must be a list of lists"

      let effectIndex = effects.find(group)
      if effectIndex == -1:
        effects.add(group)

  let mi = initMediaInfo(input)
  let bg = RGBColor(red: 0, green: 0, blue: 0)
  result = toNonLinear2(ptrInput, tb, bg, mi, clips, effects)


proc parseV1*(jsonNode: JsonNode, interner: var StringInterner): v3 =
  var chunks: seq[(int64, int64, float64)] = @[]

  let input = jsonNode["source"].getStr()
  let ptrInput = intern(interner, input)

  if jsonNode.hasKey("chunks") and jsonNode["chunks"].kind == JArray:
    for chunkNode in jsonNode["chunks"]:
      if chunkNode.kind == JArray and chunkNode.len >= 3:
        let start: int64 = chunkNode[0].getInt()
        let `end`: int64 = chunkNode[1].getInt()
        let speed = chunkNode[2].getFloat()
        chunks.add((start, `end`, speed))

  let mi = initMediaInfo(input)
  var tb = AVRational(num: 30, den: 1)
  if mi.v.len > 0:
    tb = makeSaneTimebase(mi.v[0].avgRate)

  let bg = RGBColor(red: 0, green: 0, blue: 0)
  result = toNonLinear(ptrInput, tb, bg, mi, chunks)

proc readJson*(jsonStr: string, interner: var StringInterner): v3 =
  let jsonNode = parseJson(jsonStr)
  let version: string = jsonNode["version"].getStr("unknown")

  case version:
    of "3": return parseV3(jsonNode, interner)
    of "2": return parseV2(jsonNode, interner)
    of "1": return parseV1(jsonNode, interner)
    else: error &"Unsupported version: {version}"
