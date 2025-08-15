import unittest
import std/os
import std/tempfiles

import ../src/[av, ffmpeg]
import ../src/util/[fun, color]
import ../src/edit
import ../src/wavutil
import ../src/cmds/info
import ../src/media
import ../src/timeline
import ../src/exports/fcp11
import ../src/exports/kdenlive

test "struct-sizes":
  check(sizeof(AVRational) == 8)
  check(sizeof(seq) == 16)
  check(sizeof(string) == 16)
  check(sizeof(ref string) == 8)
  check(sizeof(ref seq) == 8)
  check(sizeof(VideoStream) == 128)
  check(sizeof(AudioStream) == 72)
  check(sizeof(Clip) == 56)

test "smpte":
  check(parseSMPTE("13:44:05:21", AVRational(num: 24000, den: 1001)) == 1186701)

test "maths":
  let a = AVRational(num: 3, den: 4)
  let b = AVRational(num: 3, den: 4)
  check(a + b == AVRational(num: 3, den: 2))
  check(a + a == a * 2)

  let intThree: int64 = 3
  check(intThree / AVRational(3) == AVRational(1))
  check(intThree * AVRational(3) == AVRational(9))

  check(AVRational(num: 9, den: 3).int64 == intThree)
  check(AVRational(num: 10, den: 3).int64 == intThree)
  check(AVRational(num: 11, den: 3).int64 == intThree)
  check(AVRational(num: 10, den: 5) != AVRational(num: 2, den: 1)) # use compare

test "strings":
  check(AVRational("42") == AVRational(42))
  check(AVRational("-2/3") == AVRational(num: -2, den: 3))
  check(AVRational("6/8") == AVRational(num: 3, den: 4))
  check(AVRational("1.5") == AVRational(num: 3, den: 2))

test "color":
  check(RGBColor(red: 0, green: 0, blue: 0).toString == "#000000")
  check(RGBColor(red: 255, green: 255, blue: 255).toString == "#ffffff")

  check(parseColor("#000") == RGBColor(red: 0, green: 0, blue: 0))
  check(parseColor("#000000") == RGBColor(red: 0, green: 0, blue: 0))
  check(parseColor("#FFF") == RGBColor(red: 255, green: 255, blue: 255))
  check(parseColor("#fff") == RGBColor(red: 255, green: 255, blue: 255))
  check(parseColor("#FFFFFF") == RGBColor(red: 255, green: 255, blue: 255))

  check(parseColor("black") == RGBColor(red: 0, green: 0, blue: 0))
  check(parseColor("darkgreen") == RGBColor(red: 0, green: 100, blue: 0))

test "encoder":
  let (_, encoderCtx) = initEncoder("pcm_s16le")
  check(encoderCtx.codec_type == AVMEDIA_TYPE_AUDIO)
  check(encoderCtx.bit_rate != 0)

  let (_, encoderCtx2) = initEncoder(AV_CODEC_ID_PCM_S16LE)
  check(encoderCtx2.codec_type == AVMEDIA_TYPE_AUDIO)
  check(encoderCtx2.bit_rate != 0)

test "exports":
  check(parseExportString("premiere:name=a,version=3") == ("premiere", "a", "3"))
  check(parseExportString("premiere:name=a") == ("premiere", "a", "11"))
  check(parseExportString("premiere:name=\"Hello \\\" World") == ("premiere",
      "Hello \" World", "11"))
  check(parseExportString("premiere:name=\"Hello \\\\ World") == ("premiere",
      "Hello \\ World", "11"))

test "info":
  main(@["example.mp4"])

test "margin":
  var levels: seq[bool]
  levels = @[false, false, true, false, false]
  mutMargin(levels, 0, 1)
  check(levels == @[false, false, true, true, false])

  levels = @[false, false, true, false, false]
  mutMargin(levels, 1, 0)
  check(levels == @[false, true, true, false, false])

  levels = @[false, false, true, false, false]
  mutMargin(levels, 1, 1)
  check(levels == @[false, true, true, true, false])

  levels = @[false, false, true, false, false]
  mutMargin(levels, 2, 2)
  check(levels == @[true, true, true, true, true])

  levels = @[false, true, true, true, false]
  mutMargin(levels, -1, -1)
  check(levels == @[false, false, true, false, false])

  levels = @[false, true, true, true, true, true, true, true, false]
  mutMargin(levels, 3, -4)
  check(levels == @[true, true, true, true, false, false, false, false, false])

test "aac-mux":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out.aac"
  muxAudio("example.mp4", outFile, 0)

  let container = av.open(outFile)
  defer: container.close()
  check(container.audio.len == 1)
  check($container.audio[0].name == "aac")

test "wav-mux":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out.wav"
  muxAudio("resources/multi-track.mov", outFile, 1)

  let container = av.open(outFile)
  defer: container.close()
  check(container.audio.len == 1)
  check($container.audio[0].name == "pcm_s16le")

test "mp4towav":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out.wav"
  transcodeAudio("example.mp4", outFile, 0)

  let container = av.open(outFile)
  defer: container.close()
  check(container.audio.len == 1)
  check($container.audio[0].name == "pcm_s16le")

proc `$`*(layout: AVChannelLayout): string =
  const bufSize = 256
  var buffer = newString(bufSize)
  let ret = av_channel_layout_describe(layout.unsafeAddr, buffer.cstring,
      bufSize.csize_t)

  if ret > 0:
    let actualLen = buffer.find('\0')
    if actualLen >= 0:
      result = buffer[0..<actualLen]
    else:
      result = buffer
  else:
    result = "unknown"

test "mp3towav":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out2.wav"
  transcodeAudio("resources/mono.mp3", outFile, 0)

  let container = av.open(outFile)
  defer: container.close()
  check(container.audio.len == 1)
  check($container.audio[0].name == "pcm_s16le")
  check($container.audio[0].codecpar.ch_layout in ["mono", "1 channels"])

test "dialogue":
  check("0,0,Default,,0,0,0,,oop".dialogue == "oop")
  check("0,0,Default,,0,0,0,,boop".dialogue == "boop")

test "uuid":
  # Test that genUuid generates valid RFC 4122 version 4 UUIDs
  for i in 1..3:
    let uuid = genUuid()

    # Check format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
    check(uuid.len == 36)
    check(uuid[8] == '-')
    check(uuid[13] == '-')
    check(uuid[18] == '-')
    check(uuid[23] == '-')

    # Check version (should be 4)
    check(uuid[14] == '4')

    # Check variant bits (should be 8, 9, a, or b)
    check(uuid[19] in ['8', '9', 'a', 'b'])

    # Check all other characters are valid hex
    for j, c in uuid:
      if j notin [8, 13, 18, 23]: # Skip dashes
        check(c in "0123456789abcdef")
