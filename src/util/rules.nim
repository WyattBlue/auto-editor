import std/strformat

import ../ffmpeg
import ../log

proc defaultVideoCodec*(self: ptr AVOutputFormat): string =
  let codecId = self.video_codec
  if codecId != AV_CODEC_ID_NONE:
    let codecName = avcodec_get_name(codecId)
    if codecName != nil:
      return $codecName
  return "none"

proc defaultAudioCodec*(self: ptr AVOutputFormat): string =
  let codecId = self.audio_codec
  if codecId != AV_CODEC_ID_NONE:
    let codecName = avcodec_get_name(codecId)
    if codecName != nil:
      return $codecName
  return "none"

proc defaultSubtitleCodec*(self: ptr AVOutputFormat): string =
  let codecId = self.subtitle_codec
  if codecId != AV_CODEC_ID_NONE:
    let codecName = avcodec_get_name(codecId)
    if codecName != nil:
      return $codecName
  return "none"


type Rules* = object
  vcodecs*: seq[ptr AVCodec]
  acodecs*: seq[ptr AVCodec]
  scodecs*: seq[ptr AVCodec]
  defaultVid*: string
  defaultAud*: string
  defaultSub*: string
  maxVideos*: int = -1
  maxAudios*: int = -1
  maxSubtitles*: int = -1
  allowImage*: bool

proc initRules*(ext: string): Rules =
  let format = av_guess_format(nil, cstring(ext), nil)
  if format == nil:
    error &"Extension: {ext} has no known formats"

  result.defaultVid = format.defaultVideoCodec()
  result.defaultAud = format.defaultAudioCodec()
  result.defaultSub = format.defaultSubtitleCodec()
  result.allowImage = ext in ["mp4", "mkv"]

  var codec: ptr AVCodec
  let opaque: pointer = nil

  while true:
    codec = av_codec_iterate(addr opaque)
    if codec == nil:
      break
    if avformat_query_codec(format, codec.id, FF_COMPLIANCE_NORMAL) == 1:
      if codec.`type` == AVMEDIA_TYPE_VIDEO:
        result.vcodecs.add codec
      elif codec.`type` == AVMEDIA_TYPE_AUDIO:
        result.acodecs.add codec
      elif codec.`type` == AVMEDIA_TYPE_SUBTITLE:
        result.scodecs.add codec
