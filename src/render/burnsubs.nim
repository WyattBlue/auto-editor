## The `burn` action: FFmpeg's subtitles filter (libass) draws a source's text
## subtitles onto the frames of the sections that have it, styled as the file
## says (SRT gets libass's defaults) but for what the action overrides: its
## font file, size, and colors. Each frame goes through its source's filter
## stamped with the source time it shows, so cues follow cuts and speed
## changes.

import std/[hashes, math, os, strformat, strutils, tables, unicode]
import ../[action, av, ffmpeg, graph, log, timeline]
import ../util/rational

type
  SubGraph = object
    graph: Graph
    shape: (cint, cint, cint) # the width, height and format it was built for
  SubFile = tuple[path: string, index: int, playResY: float]
    ## what the subtitles filter reads, its subtitle stream among the file's
    ## subtitle streams, and the height its script's coordinates span; ""
    ## when the source has none
  SubBurner* = object
    files: Table[string, SubFile] # by source
    fonts: Table[string, tuple[dir, family: string]] # by font file
    graphs: Table[(string, string), SubGraph] # by source and the burn action

func playResY(header: string): float =
  ## The height an ASS script's coordinates (and font sizes) are in, as libass
  ## reads it: PlayResY, else from PlayResX, else 288.
  var x, y = 0.0
  for line in header.splitLines:
    let l = line.strip
    try:
      if l.startsWith("PlayResY:"): y = parseFloat(l[9 .. ^1].strip)
      elif l.startsWith("PlayResX:"): x = parseFloat(l[9 .. ^1].strip)
    except ValueError: discard
    if l.startsWith("[Events]"): break
  if y > 0: y
  elif x == 1280: 1024
  elif x > 0: x * 3 / 4
  else: 288

proc subtitleFile(src: string): SubFile =
  ## The first text subtitle stream in `src`, or else a sibling .srt or .ass,
  ## as the subtitle edit method falls back to; ("", -1, 0) for neither. Text
  ## other than ASS reaches libass under FFmpeg's default header, 288 tall.
  try:
    var container = av.open(src)
    defer: container.close()
    for n, st in container.subtitle:
      let par = st.codecpar
      let d = avcodec_descriptor_get(par.codec_id)
      if d != nil and (d.props and AV_CODEC_PROP_TEXT_SUB) != 0:
        var header = ""
        if $avcodec_get_name(par.codec_id) in ["ass", "ssa"] and par.extradata_size > 0:
          header = newString(par.extradata_size)
          copyMem(addr header[0], par.extradata, par.extradata_size)
        return (src, n, if header.len > 0: playResY(header) else: 288.0)
  except IOError:
    discard
  for ext in ["srt", "ass"]:
    let side = src.changeFileExt(ext)
    if fileExists(side):
      let res = if ext == "ass": playResY(try: readFile(side) except IOError: "")
                else: 288.0
      return (side, 0, res)
  ("", -1, 0.0)

func assColor(c: uint32): string =
  ## 0xRRGGBBAA as ASS writes it: &HAABBGGRR, its alpha counting transparency.
  let (r, g, b, a) = (c shr 24, (c shr 16) and 0xff, (c shr 8) and 0xff, c and 0xff)
  "&H" & toHex(int(((255 - a) shl 24) or (b shl 16) or (g shl 8) or r), 8)

proc fontFamily*(data: string): string =
  ## The family name in a TrueType/OpenType font's `name` table (the first
  ## face of a collection), as libass matches fonts by; "" if it has none.
  proc u16(at: int): int =
    if at < 0 or at + 2 > data.len: raise newException(ValueError, "truncated font")
    (data[at].ord shl 8) or data[at + 1].ord
  proc u32(at: int): int = (u16(at) shl 16) or u16(at + 2)
  try:
    let face = if data.startsWith("ttcf"): u32(12) else: 0
    var table = -1
    for i in 0 ..< u16(face + 4):
      let rec = face + 12 + 16 * i
      if rec + 4 <= data.len and data[rec ..< rec + 4] == "name": table = u32(rec + 8)
    if table < 0: return ""
    let strings = table + u16(table + 4)
    # The family (name 1), in a Unicode encoding before Mac Roman.
    var best = (rank: 99, text: "")
    for i in 0 ..< u16(table + 2):
      let rec = table + 6 + 12 * i
      if u16(rec + 6) != 1: continue
      let rank = case u16(rec)
        of 3: 0
        of 0: 1
        of 1: 2
        else: 99
      let (len, at) = (u16(rec + 8), strings + u16(rec + 10))
      if rank >= best.rank or at + len > data.len: continue
      var text = ""
      if rank == 2:
        text = data[at ..< at + len]
      else:
        var k = at
        while k + 1 < at + len:
          text.add Rune(u16(k)).toUTF8
          k += 2
      best = (rank, text)
    best.text
  except ValueError:
    ""

proc fontDir(b: var SubBurner, font: string): tuple[dir, family: string] =
  ## A folder holding just `font`, for libass to look in, and its family.
  if font notin b.fonts:
    let data = try: readFile(font) except IOError:
      error &"burn: can't read the font {font}"
    let family = fontFamily(data)
    if family.len == 0: error &"burn: {font} has no font family name"
    let dir = getTempDir() / &"auto-editor-burn-{getCurrentProcessId()}-{hash(font).uint:x}"
    createDir(dir)
    writeFile(dir / extractFilename(font), data)
    b.fonts[font] = (dir, family)
  b.fonts[font]

func quoted(value: string): string =
  ## A filter option value taken literally: in single quotes, each quote
  ## closed, escaped, and reopened.
  "'" & value.replace("'", "'\\''") & "'"

proc close*(b: var SubBurner) =
  for g in b.graphs.values: g.graph.cleanup()
  b.graphs.clear()
  for (dir, _) in b.fonts.values:
    try: removeDir(dir) except OSError: discard
  b.fonts.clear()

proc burn*(b: var SubBurner, frame: ptr AVFrame, tl: v3, index: int64): ptr AVFrame =
  ## `frame` (output frame `index`) with the subtitles showing at the source
  ## frame it came from, when its section burns them: a new frame the caller
  ## frees along with `frame`, or `frame` itself.
  result = frame
  # The lowest clip with a source is what the picture's base layer shows.
  for track in tl.v:
    for clip in track:
      if clip.src == nil or index < clip.start or index >= clip.start + clip.dur:
        continue
      var burn: Action
      var burning = false
      var speed = 1.0
      for effect in tl.effects[clip.effects]:
        if effect.kind == actSpeed: speed *= effect.val
        if effect.kind == actBurn:
          burning = true
          burn = effect
      if not burning: return

      let src = clip.src[]
      if src notin b.files: b.files[src] = subtitleFile(src)
      let file = b.files[src]
      if file.path.len == 0: return
      let secs = float64(clip.offset + index - clip.start) * speed *
        tl.tb.den.float64 / tl.tb.num.float64

      let shape = (frame.width, frame.height, frame.format)
      let key = (src, $burn)
      if key notin b.graphs or b.graphs[key].shape != shape:
        if key in b.graphs: b.graphs[key].graph.cleanup()
        if avfilter_get_by_name("subtitles") == nil:
          error "burn needs FFmpeg's subtitles filter (FFmpeg built with libass)"
        var opts = &"filename={quoted(file.path)}:stream_index={file.index}"
        var style: seq[string]
        if burn.burnFont.len > 0:
          let (dir, family) = b.fontDir(burn.burnFont)
          opts &= ":fontsdir=" & quoted(dir)
          style.add "FontName=" & family
        if burn.burnSize > 0:
          # A percent of the frame, in the script's own coordinates.
          style.add &"Fontsize={burn.burnSize.float * file.playResY / 100:.2f}"
        if bpColor in burn.burnSet:
          style.add "PrimaryColour=" & assColor(burn.burnColors[bpColor])
        if bpOutline in burn.burnSet:
          style.add "OutlineColour=" & assColor(burn.burnColors[bpOutline])
        if bpBg in burn.burnSet:
          # libass's own border style: one box behind each subtitle, the
          # outline kept.
          style.add "BorderStyle=4"
          style.add "BackColour=" & assColor(burn.burnColors[bpBg])
        if style.len > 0: opts &= ":force_style=" & quoted(style.join(","))
        let g = newGraph()
        let nodes = @[
          g.add("buffer", &"video_size={frame.width}x{frame.height}:" &
            &"pix_fmt={frame.format}:time_base=1/1000:pixel_aspect=1/1:" &
            &"colorspace={frame.colorspace}:range={frame.color_range}"),
          g.add("subtitles", opts), g.add("buffersink")]
        g.linkNodes(nodes).configure()
        b.graphs[key] = SubGraph(graph: g, shape: shape)

      frame.pts = int64(round(secs * 1000))
      frame.time_base = AVRational(num: 1, den: 1000)
      let g = b.graphs[key].graph
      g.push(frame)
      return g.pull()
