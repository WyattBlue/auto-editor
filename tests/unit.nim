import unittest
import std/[os, tempfiles]

import ../src/[av, conductor, edit, ffmpeg, media, timeline, wavutil]
import ../src/util/[color, fun, lang, rational]
import ../src/exports/[kdenlive, fcp11]
import ../src/vendor/tinyre/tinyre

test "avrational":
  let a = AVRational(num: 3, den: 4)
  let b = AVRational(num: 3, den: 4)
  check a + b == AVRational(num: 3, den: 2)
  check a + a == a * 2

  let intThree: int64 = 3
  check intThree / AVRational(3) == AVRational(1)
  check intThree * AVRational(3) == AVRational(9)

  check AVRational(num: 9, den: 3).int64 == intThree
  check AVRational(num: 10, den: 3).int64 == intThree
  check AVRational(num: 11, den: 3).int64 == intThree
  check AVRational(num: 10, den: 5) != AVRational(num: 2, den: 1) # use compare

  check AVRational("42") == AVRational(42)
  check AVRational("-2/3") == AVRational(num: -2, den: 3)
  check AVRational("6/8") == AVRational(num: 3, den: 4)
  check AVRational("1.5") == AVRational(num: 3, den: 2)

test "color":
  check RGBColor(red: 0, green: 0, blue: 0).toString == "#000000"
  check RGBColor(red: 255, green: 255, blue: 255).toString == "#ffffff"

  check parseColor("#000") == RGBColor(red: 0, green: 0, blue: 0)
  check parseColor("#000000") == RGBColor(red: 0, green: 0, blue: 0)
  check parseColor("#FFF") == RGBColor(red: 255, green: 255, blue: 255)
  check parseColor("#fff") == RGBColor(red: 255, green: 255, blue: 255)
  check parseColor("#FFFFFF") == RGBColor(red: 255, green: 255, blue: 255)

  check parseColor("black") == RGBColor(red: 0, green: 0, blue: 0)
  check parseColor("darkgreen") == RGBColor(red: 0, green: 100, blue: 0)

test "dialogue":
  check "0,0,Default,,0,0,0,,oop".dialogue == "oop"
  check "0,0,Default,,0,0,0,,boop".dialogue == "boop"

  # Override blocks are stripped.
  check "0,0,Default,,0,0,0,,{\\b1}bold{\\b0}".dialogue == "bold"
  check "0,0,Default,,0,0,0,,{\\an8}top".dialogue == "top"

  # Text escapes: \N -> newline, \n and \h -> space.
  check "0,0,Default,,0,0,0,,a\\Nb".dialogue == "a\nb"
  check "0,0,Default,,0,0,0,,a\\nb".dialogue == "a b"
  check "0,0,Default,,0,0,0,,a\\hb".dialogue == "a b"

  # A stray '{' with no closing '}' is literal text.
  check "0,0,Default,,0,0,0,,cost is {5".dialogue == "cost is {5"

  # Escapes inside an override block are not interpreted.
  check "0,0,Default,,0,0,0,,{\\fnArial}hi".dialogue == "hi"

test "encoder":
  let (_, encoderCtx) = initEncoder("pcm_s16le")
  check encoderCtx.codec_type == AVMEDIA_TYPE_AUDIO
  check encoderCtx.bit_rate != 0

  let (_, encoderCtx2) = initEncoder(ID_PCM_S16LE)
  check encoderCtx2.codec_type == AVMEDIA_TYPE_AUDIO
  check encoderCtx2.bit_rate != 0

test "exports":
  check(parseExportString("premiere:name=a,version=3") == ("premiere", "a", "3"))
  check(parseExportString("premiere:name=a") == ("premiere", "a", "11"))
  check(parseExportString("premiere:name=\"Hello \\\" World") == ("premiere",
      "Hello \" World", "11"))
  check(parseExportString("premiere:name=\"Hello \\\\ World") == ("premiere",
      "Hello \\ World", "11"))

test "editNeeds":
  check editNeeds("audio") == (false, true)
  check editNeeds("motion") == (true, false)
  check editNeeds("none") == (false, false)
  check editNeeds("all") == (false, false)
  check editNeeds("audio:threshold=4%") == (false, true)
  check editNeeds("motion:width=200") == (true, false)
  check editNeeds("(or audio motion)") == (true, true)
  check editNeeds("(and audio (not motion))") == (true, true)
  check editNeeds("(or (not audio:threshold=4%) audio:stream=1)") == (false, true)
  check editNeeds("subtitle:pattern=foo") == (true, false)
  check editNeeds("word:value=audio") == (true, false)

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

test "mp3towav":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out2.wav"
  transcodeAudio("resources/mono.mp3", outFile, 0)

  let container = av.open(outFile)
  defer: container.close()
  check container.audio.len == 1
  check $container.audio[0].name == "pcm_s16le"
  check $container.audio[0].codecpar.ch_layout in ["mono", "1 channels"]

test "mp4towav":
  let tempDir = createTempDir("tmp", "")
  defer: removeDir(tempDir)
  let outFile = tempDir / "out.wav"
  transcodeAudio("example.mp4", outFile, 0)

  let container = av.open(outFile)
  defer: container.close()
  check container.audio.len == 1
  check $container.audio[0].name == "pcm_s16le"

test "size-of-objects":
  check sizeof(seq) == 16
  check sizeof(ref seq) == 8
  check sizeof(string) == 16
  check sizeof(ref string) == 8
  check sizeof(AVCodecID) == 4
  check sizeof(AVPixelFormat) == 4
  check sizeof(AVRational) == 8
  check sizeof(VideoStream) == 96
  check sizeof(AudioStream) == 48
  check sizeof(SubtitleStream) == 16
  check sizeof(MediaInfo) == 112
  check sizeof(Clip) == 40
  check sizeof(AVChannelLayout) == 24

  check sizeof(RGBColor) == 3
  check sizeof(v3) == 128

test "lang-to-string":
  check sizeof(Lang) == 4
  var a: Lang = ['a', 's', 'd', 'f']
  check $a == "asdf"
  a  = ['e', 'n', 'g', '\0']
  check $a == "eng"

test "re":
  check match("abc123", re"\d+") == @["123"]
  check match("abc123", re(".", {reGlobal})) == @["a", "b", "c", "1", "2", "3"]
  check match("abc123", re("ABC", {reIgnoreCase})) == @["abc"]
  check match("abc123", re"ABC") != @["abc"]
  check match("中文", re("..", {reUtf8})) == @["中文"]
  check match("中文", re"..") != @["中文"]

test "smpte":
  check parseSMPTE("13:44:05:21", AVRational(num: 24000, den: 1001)) == 1186701

test "agSplitFile":
  check agSplitFile("/").ext == ""
  check agSplitFile("/.").ext == ""
  check agSplitFile("/.foo").ext == ""
  check agSplitFile("./foo").ext == ""
  check agSplitFile("/foo").ext == ""
  check agSplitFile("/foo.txt").ext == ".txt"
  check agSplitFile("/foo.txt/bar").ext == ""
  check agSplitFile("C:\\").ext == ""
  check agSplitFile("C:\\.").ext == ""
  check agSplitFile("C:\\foo.txt").ext == ".txt"
  check agSplitFile("C:\\foo.txt\\bar").ext == ""
  check agSplitFile("./foo..").ext == ""

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

test "aspectRatio":
  # Clean reductions are kept as-is.
  check aspectRatio(1920, 1080) == (16, 9)
  check aspectRatio(1280, 720) == (16, 9)
  check aspectRatio(640, 480) == (4, 3)
  check aspectRatio(1600, 1000) == (8, 5)
  check aspectRatio(1080, 1920) == (9, 16)

  # Codec-rounding artifacts snap to the intended display aspect ratio.
  check aspectRatio(854, 480) == (16, 9)   # not 427:240
  check aspectRatio(1366, 768) == (16, 9)  # not 683:384
  check aspectRatio(2560, 1080) == (64, 27)

  # Genuinely unusual ratios are left exact, not force-snapped.
  check aspectRatio(1920, 800) == (12, 5)  # 2.40:1 stays as-is

  # SAR is folded in, so anamorphic video reports its true display ratio.
  check aspectRatio(720, 480, 32, 27) == (16, 9)  # NTSC anamorphic 16:9
  check aspectRatio(720, 480, 8, 9) == (4, 3)     # NTSC 4:3
  check aspectRatio(720, 576, 16, 15) == (4, 3)   # PAL 4:3
  check aspectRatio(1440, 1080, 4, 3) == (16, 9)  # HDV anamorphic

  # Degenerate input.
  check aspectRatio(100, 0) == (0, 0)
