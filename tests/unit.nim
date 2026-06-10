import unittest
import std/[os, tempfiles, json]

import ../src/[action, av, conductor, edit, ffmpeg, log, media, timeline, wavutil]
import ../src/util/[color, fun, lang, rational]
import ../src/exports/[kdenlive, fcp11]
import ../src/imports/json as jsonImport
import ../src/exports/json as jsonExport
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
  check parseColor("DarkGreen") == RGBColor(red: 0, green: 100, blue: 0)
  check parseColor("WHITE") == RGBColor(red: 255, green: 255, blue: 255)

  # The named path is strict: only real color names, no hex/random/alpha forms.
  expect ValueError: discard parseColor("0xFF0000")
  expect ValueError: discard parseColor("FF0000")
  expect ValueError: discard parseColor("random")
  expect ValueError: discard parseColor("black@0.5")

  # toString round-trips through parseColor.
  check RGBColor(red: 18, green: 52, blue: 86).toString == "#123456"
  check parseColor(RGBColor(red: 1, green: 2, blue: 3).toString) ==
    RGBColor(red: 1, green: 2, blue: 3)

  # Malformed input is rejected, not silently coerced.
  expect ValueError: discard parseColor("#12")
  expect ValueError: discard parseColor("#12345")
  expect ValueError: discard parseColor("#xyzxyz")
  expect ValueError: discard parseColor("#xyz")

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

test "v3-overlay-roundtrip":
  # Overlay placement is a `pos` action carried in a clip's effects, so it
  # round-trips through the normal effects array of the v3 JSON.
  var interner: StringInterner
  let tlStr = """{"version":"3","timebase":"30/1","background":"#000000",
    "resolution":[1280,720],"samplerate":48000,"layout":"stereo","langs":["eng"],
    "v":[[{"name":"video","src":"a.mp4","start":0,"dur":60,"offset":0,"stream":0}],
    [{"name":"video","src":"a.mp4","start":0,"dur":60,"offset":0,"stream":0,
    "effects":["pos:900:60:0.25"]}]],"a":[]}"""
  let tl = jsonImport.readJson(tlStr, interner)
  check tl.v.len == 2
  block:
    let p = tl.effects[tl.v[1][0].effects]
    var found: Action
    for a in p:
      if a.kind == actPos: found = a
    check found.kind == actPos
    check (found.px, found.py) == (900'i32, 60'i32)
    check abs(found.pscale - 0.25'f32) < 0.001'f32
  let node = jsonExport.`%`(tl)
  check node["v"][1][0]["effects"][0].getStr == "pos:900:60:0.25"
  check not node["v"][0][0].hasKey("effects")   # base clip has no effects
  interner.cleanup()

test "actions":
  proc acts(s: string): seq[Action] =
    for a in parseActions(s): result.add a

  # Static actions round-trip through `$` (rotate is circular-quantized).
  check $parseActions("zoom:2") == "zoom:2.0"
  check $parseActions("opacity:0.5") == "opacity:0.5"
  check $parseActions("brightness:-0.5") == "brightness:-0.5"

  # Ramps and multi-keyframe ramps interpolate across the section.
  check $parseActions("zoom:1..2") == "zoom:1.0..2.0"
  check $parseActions("opacity:0..1") == "opacity:0.0..1.0"
  check $parseActions("zoom:1..0.5..1") == "zoom:1.0..0.5..1.0"
  check $parseActions("opacity:0..1..0") == "opacity:0.0..1.0..0.0"

  # rotate: a fixed angle (static, expands the canvas).
  check $parseActions("rotate:90") == "rotate:90.0"
  block:
    let s = acts("rotate:30")[0]
    check s.kind == actRotate
    check abs(rotDeg(s.rStart) - 30.0'f32) < 0.01'f32
  # rotate no longer accepts a spin rate; use spin for that.
  expect ActionParseError: discard parseActions("rotate:0/120")

  # spin: "start/rate" for a constant-speed spin (deg/sec).
  check $parseActions("spin:0/120") == "spin:0.0/120.0"
  check $parseActions("spin:90/-45") == "spin:90.0/-45.0"
  block:
    let r = acts("spin:0/120")[0]
    check r.kind == actSpin
    check abs(r.sRate - 120.0'f32) < 0.001'f32
    check abs(rotDeg(r.sStart)) < 0.01'f32                  # starts at 0 deg
  expect ActionParseError: discard parseActions("spin:45")   # needs deg/rate

  # drawbox: x:y:w:h:color, round-tripping through `$` with a hex color.
  check $parseActions("drawbox:100:100:400:200:red") ==
    "drawbox:100:100:400:200:#ff0000"
  check $parseActions("drawbox:0:0:1920:1080:#123456") ==
    "drawbox:0:0:1920:1080:#123456"
  block:
    let d = acts("drawbox:10:20:30:40:#00ff00")[0]
    check d.kind == actDrawbox
    check (d.dbX, d.dbY, d.dbW, d.dbH) == (10'i32, 20'i32, 30'i32, 40'i32)
    check d.dbColor == RGBColor(red: 0, green: 255, blue: 0)
  expect ActionParseError: discard parseActions("drawbox:1:2:3:4")
  expect ActionParseError: discard parseActions("drawbox:1:2:0:4:red")
  expect ActionParseError: discard parseActions("drawbox:1:2:3:4:notacolor")

  # pos: overlay placement, scale optional and defaulting to 1.0.
  check $parseActions("pos:600:300:0.5") == "pos:600:300:0.5"
  check $parseActions("pos:10:20") == "pos:10:20:1.0"
  block:
    let p = acts("pos:600:300:0.5")[0]
    check p.kind == actPos
    check (p.px, p.py) == (600'i32, 300'i32)
    check abs(p.pscale - 0.5'f32) < 0.001'f32
  expect ActionParseError: discard parseActions("pos:600")
  expect ActionParseError: discard parseActions("pos:1:2:0")

  # Easing packs into the action itself (no separate ease entry).
  block:
    let z = acts("zoom:1..2:ease=inout")
    check z.len == 1
    check z[0].kind == actZoom
    check z[0].hasEase
    check z[0].easeCurve == easeInOut
    check z[0].easeDurUnit == duClip
    check z[0].kf == @[1.0'f32, 2.0'f32]

  # `ease:` is an envelope: it stamps the following animated actions.
  block:
    let g = acts("ease:in:2sec,zoom:1..2,brightness:0..0.3")
    check g.len == 2
    for a in g:
      check a.hasEase
      check a.easeCurve == easeIn
      check a.easeDurUnit == duSec
      check abs(a.easeDur - 2.0'f32) < 0.001'f32
  # Attached easing overrides the envelope.
  check acts("ease:in,zoom:1..2:ease=out")[0].easeCurve == easeOut

  # Keyframe interpolation (sampleKf) at the endpoints and midpoint.
  let kf = acts("zoom:1..0.5..1")[0].kf
  check abs(sampleKf(kf, 0.0'f32) - 1.0'f32) < 0.001'f32
  check abs(sampleKf(kf, 0.5'f32) - 0.5'f32) < 0.001'f32
  check abs(sampleKf(kf, 1.0'f32) - 1.0'f32) < 0.001'f32
  check abs(sampleKf(kf, 0.25'f32) - 0.75'f32) < 0.001'f32  # halfway into seg 0

  # Parameterless video filters round-trip through `$`.
  check $parseActions("erosion") == "erosion"
  check acts("erosion")[0].kind == actErosion

  # choke: matte erosion, count defaults to 1 and round-trips through `$`.
  check $parseActions("choke") == "choke:1"
  check $parseActions("choke:2") == "choke:2"
  block:
    let c = acts("choke:3")[0]
    check c.kind == actChoke
    check c.chokeN == 3'u8
  expect ActionParseError: discard parseActions("choke:0")
  expect ActionParseError: discard parseActions("choke:17")
  expect ActionParseError: discard parseActions("choke:x")

  # loop is a per-clip flag: collapse to a single token at the front.
  check $parseActions("zoom:1..2,loop,loop") == "loop,zoom:1.0..2.0"
  check $parseActions("loop,speed:1.5,loop") == "loop,speed:1.5"
  check $parseActions("loop") == "loop"
  # firstIsLoop is the O(1) check the renderer uses each frame.
  check firstIsLoop(parseActions("zoom:1..2,loop"))
  check firstIsLoop(parseActions("loop"))
  check not firstIsLoop(parseActions("zoom:1..2"))
  check not firstIsLoop(parseActions("nil"))

  # Easing curves.
  check applyEase(easeLinear, 0.5'f32) == 0.5'f32
  check applyEase(easeIn, 0.5'f32) < 0.5'f32
  check applyEase(easeOut, 0.5'f32) > 0.5'f32
  check abs(applyEase(easeInOut, 0.5'f32) - 0.5'f32) < 0.001'f32

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
  a = ['e', 'n', 'g', '\0']
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
  check aspectRatio(854, 480) == (16, 9) # not 427:240
  check aspectRatio(1366, 768) == (16, 9) # not 683:384
  check aspectRatio(2560, 1080) == (64, 27)

  # Genuinely unusual ratios are left exact, not force-snapped.
  check aspectRatio(1920, 800) == (12, 5) # 2.40:1 stays as-is

  # SAR is folded in, so anamorphic video reports its true display ratio.
  check aspectRatio(720, 480, 32, 27) == (16, 9) # NTSC anamorphic 16:9
  check aspectRatio(720, 480, 8, 9) == (4, 3) # NTSC 4:3
  check aspectRatio(720, 576, 16, 15) == (4, 3) # PAL 4:3
  check aspectRatio(1440, 1080, 4, 3) == (16, 9) # HDV anamorphic

  # Degenerate input.
  check aspectRatio(100, 0) == (0, 0)

test "parseBitrate":
  check parseBitrate("auto") == -1
  check parseBitrate("500") == 500
  check parseBitrate("128k") == 128000
  check parseBitrate("128K") == 128000
  check parseBitrate("5M") == 5_000_000

test "toTimecode":
  check toTimecode(3723.5, standard) == "01:02:03.500"
  check toTimecode(0.0, standard) == "00:00:00.000"
  check toTimecode(-1.5, standard) == "-00:00:01.500"
  check toTimecode(3723.5, ass) == "1:02:03.50"
  check toTimecode(3661.4, display) == "1:01:01"

test "smoothing":
  # A TRUE run shorter than minclip is dropped.
  var island = @[false, false, true, false, false]
  smoothing(island, 0, 2)
  check island == @[false, false, false, false, false]

  # A FALSE gap shorter than mincut is filled in.
  var gap = @[true, true, false, true, true]
  smoothing(gap, 2, 0)
  check gap == @[true, true, true, true, true]

  # A gap at/above mincut is left alone.
  var bigGap = @[true, false, false, false, true]
  smoothing(bigGap, 2, 0)
  check bigGap == @[true, false, false, false, true]
