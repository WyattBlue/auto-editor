import std/[strformat, strutils, json]

import ../log
import ../timeline
import ../ffmpeg
import ../media
import ../util/color

proc parseEffect(val: string): Action =
  if val == "cut":
    return Action(kind: actCut)

  let parts = val.split(":")
  if parts.len == 2:
    let effectType = parts[0]
    let effectVal = parseFloat(parts[1])
    case effectType
    of "speed": return Action(kind: actSpeed, val: effectVal)
    of "volume": return Action(kind: actVolume, val: effectVal)
    of "varispeed": return Action(kind: actVarispeed, val: effectVal)
    else: error &"unknown action: {effectType}"

  error &"unknown action: {val}"

proc parseClip(node: JsonNode, interner: var StringInterner, effects: var seq[seq[Action]]): Clip =
  result.src = interner.intern(node["src"].getStr())
  result.start = node["start"].getInt()
  result.dur = node["dur"].getInt()
  result.offset = node["offset"].getInt()
  result.stream = node["stream"].getInt().int32

  var clipActions: seq[Action] = @[]
  if node.hasKey("effects") and node["effects"].kind == JArray:
    for effectNode in node["effects"]:
      let effectStr = effectNode.getStr()
      if effectStr != "nil":
        clipActions.add parseEffect(effectStr)

  let effectIndex = effects.find(clipActions)
  if effectIndex == -1:
    effects.add(clipActions)
    result.effects = uint32(effects.len - 1)
  else:
    result.effects = uint32(effectIndex)

proc parseV3*(jsonNode: JsonNode, interner: var StringInterner): v3 =
  var tb: AVRational
  try:
    tb = jsonNode["timebase"].getStr()
  except ValueError as e:
    error(e.msg)

  result.tb = jsonNode["timebase"].getStr()

  if not jsonNode.hasKey("samplerate") or not jsonNode.hasKey("background"):
    error("sr/bg bad structure")

  result.sr = jsonNode["samplerate"].getInt().cint
  result.bg = parseColor(jsonNode["background"].getStr())

  if not jsonNode.hasKey("resolution") or jsonNode["resolution"].kind != JArray:
    error("'resolution' has bad structure")

  result.layout = jsonNode["layout"].getStr()

  let resArray = jsonNode["resolution"]
  if resArray.len >= 2:
    result.res = (resArray[0].getInt(), resArray[1].getInt())
  else:
    result.res = (1920, 1080)

  result.effects = @[]

  result.v = @[]
  if jsonNode.hasKey("v") and jsonNode["v"].kind == JArray:
    for trackNode in jsonNode["v"]:
      var track = ClipLayer(lang: "und", c: @[])
      if trackNode.kind == JArray:
        for videoNode in trackNode:
          track.c.add(parseClip(videoNode, interner, result.effects))
      result.v.add(track)

  # Parse audio tracks
  result.a = @[]
  if jsonNode.hasKey("a") and jsonNode["a"].kind == JArray:
    for trackNode in jsonNode["a"]:
      var track = ClipLayer(lang: "und", c: @[])
      if trackNode.kind == JArray:
        for audioNode in trackNode:
          track.c.add(parseClip(audioNode, interner, result.effects))
      result.a.add(track)

proc parseV2*(jsonNode: JsonNode, interner: var StringInterner): v3 =
  let input = jsonNode["source"].getStr()
  let ptrInput = intern(interner, input)
  var effects: seq[seq[Action]]
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
      # Support single action strings or arrays of actions
      var actionGroup: seq[Action] = @[]
      if effectNode.kind == JString:
        actionGroup.add parseEffect(effectNode.getStr())
      elif effectNode.kind == JArray:
        for actionStr in effectNode:
          actionGroup.add parseEffect(actionStr.getStr())

      let effectIndex = effects.find(actionGroup)
      if effectIndex == -1:
        effects.add(actionGroup)

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
