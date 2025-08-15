import std/json

import ../log
import ../timeline
import ../ffmpeg
import ../media
import ../util/color

proc parseClip(node: JsonNode, interner: var StringInterner): Clip =
  result.src = interner.intern(node["src"].getStr())
  result.start = node["start"].getInt()
  result.dur = node["dur"].getInt()
  result.offset = node["offset"].getInt()
  result.speed = node["speed"].getFloat()
  result.volume = node.getOrDefault("volume").getFloat(1.0)
  result.stream = node["stream"].getInt().int32

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

  result.v = @[]
  if jsonNode.hasKey("v") and jsonNode["v"].kind == JArray:
    for trackNode in jsonNode["v"]:
      var track = ClipLayer(lang: "und", c: @[])
      if trackNode.kind == JArray:
        for videoNode in trackNode:
          track.c.add(parseClip(videoNode, interner))
      result.v.add(track)

  # Parse audio tracks
  result.a = @[]
  if jsonNode.hasKey("a") and jsonNode["a"].kind == JArray:
    for trackNode in jsonNode["a"]:
      var track = ClipLayer(lang: "und", c: @[])
      if trackNode.kind == JArray:
        for audioNode in trackNode:
          track.c.add(parseClip(audioNode, interner))
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
