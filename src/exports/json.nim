import std/[json, options, sequtils]

import ../timeline
import ../log
import ../util/color


func effectToString(act: Action): string =
  case act.kind
  of actCut: "cut"
  of actSpeed: "speed:" & $act.val
  of actVarispeed: "varispeed:" & $act.val
  of actVolume: "volume:" & $act.val

func effectGroupToJson(actions: seq[Action]): JsonNode =
  if actions.len == 0:
    return %"nil"
  elif actions.len == 1:
    return %effectToString(actions[0])
  else:
    return %actions.mapIt(effectToString(it))

func `%`(self: v1): JsonNode =
  var jsonChunks = self.chunks.mapIt(%[%it[0], %it[1], %it[2]])
  return %* {"version": "1", "source": self.source, "chunks": jsonChunks}

func `%`(self: v2): JsonNode =
  let jsonClips = self.clips.mapIt(%[%it.start, %it.`end`, %it.`effect`])
  let jsonEffects = self.effects.mapIt(effectGroupToJson(it))
  return %* {
    "version": "2",
    "source": self.source,
    "tb": $self.tb.num & "/" & $self.tb.den,
    "effects": jsonEffects,
    "clips": jsonClips,
  }

func `%`*(self: v3): JsonNode =
  var videoTracks = newJArray()
  for track in self.v:
    var trackArray = newJArray()
    for clip in track.clips:
      var clipObj = newJObject()
      clipObj["name"] = %"video"
      clipObj["src"] = %(if clip.src != nil: clip.src[] else: "")
      clipObj["start"] = %clip.start
      clipObj["dur"] = %clip.dur
      clipObj["offset"] = %clip.offset
      clipObj["stream"] = %clip.stream
      let effectGroup = self.effects[clip.effects]
      var hasNonTrivialEffect = false
      if effectGroup.len > 0:
        for effect in effectGroup:
          if effect.kind != actCut:
            hasNonTrivialEffect = true
            break
      if hasNonTrivialEffect:
        var effectArray = newJArray()
        for effect in effectGroup:
          effectArray.add %effectToString(effect)
        clipObj["effects"] = effectArray
      trackArray.add(clipObj)
    videoTracks.add(trackArray)

  var audioTracks = newJArray()
  for track in self.a:
    var trackArray = newJArray()
    for clip in track.clips:
      var clipObj = newJObject()
      clipObj["name"] = %"audio"
      clipObj["src"] = %(if clip.src != nil: clip.src[] else: "")
      clipObj["start"] = %clip.start
      clipObj["dur"] = %clip.dur
      clipObj["offset"] = %clip.offset
      clipObj["stream"] = %clip.stream
      let effectGroup = self.effects[clip.effects]
      var hasNonTrivialEffect = false
      if effectGroup.len > 0:
        for effect in effectGroup:
          if effect.kind != actCut:
            hasNonTrivialEffect = true
            break
      if hasNonTrivialEffect:
        var effectArray = newJArray()
        for effect in effectGroup:
          effectArray.add %effectToString(effect)
        clipObj["effects"] = effectArray
      trackArray.add(clipObj)
    audioTracks.add(trackArray)

  return %* {
    "version": "3",
    "timebase": $self.tb.num & "/" & $self.tb.den,
    "background": self.bg.toString,
    "resolution": [self.res[0], self.res[1]],
    "samplerate": self.sr,
    "layout": self.layout,
    "v": videoTracks,
    "a": audioTracks,
  }

proc exportJsonTl*(tlV3: v3, `export`: string, output: string) =
  var tlJson: JsonNode

  if `export` == "v1" or `export` == "v2":
    if tlV3.clips2.isNone:
      error "No chunks available for export"

    var source: string = ""
    if tlV3.v.len > 0 and tlV3.v[0].len > 0:
      source = tlV3.v[0].c[0].src[]
    elif tlV3.a.len > 0 and tlV3.a[0].len > 0:
      source = tlV3.a[0].c[0].src[]

    let clips2 = tlV3.clips2.unsafeGet()
    let tb = tlV3.tb
    if `export` == "v2":
      tlJson = %v2(source: source, tb: tb, clips: clips2, effects: tlV3.effects)
    else:
      var chunks: seq[(int64, int64, float64)] = @[]
      for clip2 in clips2:
        var speed = 1.0
        let effectGroup = tlV3.effects[clip2.effect]
        for effect in effectGroup:
          if effect.kind == actCut:
            speed = 99999.0
          elif effect.kind == actSpeed or effect.kind == actVarispeed:
            speed *= effect.val.float64

        chunks.add (clip2.start, clip2.`end`, speed)

      tlJson = %v1(source: source, chunks: chunks)
  else:
    tlJson = %tlV3

  if output == "-":
    echo pretty(tlJson)
  else:
    writeFile(output, pretty(tlJson))
