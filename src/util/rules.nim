import std/strformat

import ./fun
import ../[ffmpeg, log]


type Rules* = object
  ofmt: ptr AVOutputFormat

func allowsCodec*(self: Rules, codecId: AVCodecID): bool =
  var tag: cuint = 0
  return av_codec_get_tag2(self.ofmt.codec_tag, codecId, addr tag) > 0

func defaultVid*(self: Rules): AVCodecID =
  self.ofmt.video_codec

func defaultAud*(self: Rules): AVCodecID =
  self.ofmt.audio_codec

func defaultSub*(self: Rules): AVCodecID =
  if self.ofmt.name == "mp4": ID_MOV_TEXT else: self.ofmt.subtitle_codec

proc initRules*(name: string): Rules =
  let format = av_guess_format(nil, cstring(name), nil)
  if format == nil:
    error &"Extension: {agSplitFile(name)[2]} has no known formats"

  result.ofmt = format
