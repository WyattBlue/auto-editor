import std/json
import std/strutils

import ../log
import ../timeline
import ../ffmpeg
import ../media
import ../util/color

proc parseClip(node: JsonNode, interner: var StringInterner, effects: var seq[Action]): Clip =
  result.src = interner.intern(node["src"].getStr())
  result.start = node["start"].getInt()
  result.dur = node["dur"].getInt()
  result.offset = node["offset"].getInt()
  result.stream = node["stream"].getInt().int32

  # Parse effects array and find/add to effects list
  var clipAction = Action(kind: actNil)
  if node.hasKey("effects") and node["effects"].kind == JArray:
    for effectNode in node["effects"]:
      let effectStr = effectNode.getStr()
      # Parse effect strings like "speed:2.0", "volume:1.5"
      let parts = effectStr.split(":")
      if parts.len == 2:
        let effectType = parts[0]
        let effectVal = parseFloat(parts[1])
        case effectType
        of "speed":
          clipAction = Action(kind: actSpeed, val: effectVal)
        of "volume":
          clipAction = Action(kind: actVolume, val: effectVal)
        of "pitch":
          clipAction = Action(kind: actPitch, val: effectVal)
        else:
          discard

  # Find or add the action to the effects list
  let effectIndex = effects.find(clipAction)
  if effectIndex == -1:
    effects.add(clipAction)
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
  result.background = parseColor(jsonNode["background"].getStr())

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
  if version == "3":
    return parseV3(jsonNode, interner)
  if version == "1":
    return parseV1(jsonNode, interner)
  error("Unsupported version")
