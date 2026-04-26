import std/strformat

import ../[ffmpeg, log]


type Rules* = object
  vcodecs*: seq[ptr AVCodec]
  acodecs*: seq[ptr AVCodec]
  scodecs*: seq[ptr AVCodec]
  defaultVid*: AVCodecID
  defaultAud*: AVCodecID
  defaultSub*: AVCodecID
  # maxVideos*: int = -1
  # maxAudios*: int = -1
  # maxSubtitles*: int = -1
  allowImage*: bool

proc initRules*(ext: string): Rules =
  let format = av_guess_format(nil, cstring(ext), nil)
  if format == nil:
    error &"Extension: {ext} has no known formats"

  result.defaultVid = format.video_codec
  result.defaultAud = format.audio_codec
  result.defaultSub = format.subtitle_codec
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
