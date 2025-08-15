import std/json
import std/options
import std/sequtils

import ../timeline
import ../log
import ../util/color

func `%`*(self: v1): JsonNode =
  var jsonChunks = self.chunks.mapIt(%[%it[0], %it[1], %it[2]])
  return %* {"version": "1", "source": self.source, "chunks": jsonChunks}

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
      clipObj["speed"] = %clip.speed
      clipObj["stream"] = %clip.stream
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
      clipObj["speed"] = %clip.speed
      clipObj["volume"] = %1
      clipObj["stream"] = %clip.stream
      trackArray.add(clipObj)
    audioTracks.add(trackArray)

  return %* {
    "version": "3",
    "timebase": $self.tb.num & "/" & $self.tb.den,
    "background": self.background.toString,
    "resolution": [self.res[0], self.res[1]],
    "samplerate": self.sr,
    "layout": self.layout,
    "v": videoTracks,
    "a": audioTracks,
  }

proc exportJsonTl*(tlV3: v3, `export`: string, output: string) =
  var tlJson: JsonNode

  if `export` == "v1":
    if tlV3.chunks.isNone:
      error "No chunks available for export"

    let chunks = tlV3.chunks.unsafeGet()
    var source: string = ""
    if tlV3.v.len > 0 and tlV3.v[0].len > 0:
      source = tlV3.v[0].c[0].src[]
    elif tlV3.a.len > 0 and tlV3.a[0].len > 0:
      source = tlV3.a[0].c[0].src[]

    tlJson = %v1(chunks: chunks, source: source)
  else:
    tlJson = %tlV3

  if output == "-":
    echo pretty(tlJson)
  else:
    writeFile(output, pretty(tlJson))
