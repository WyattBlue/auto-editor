## The `burn` action: FFmpeg's subtitles filter (libass) draws a subtitle
## file, on a generator layer's clear canvas (`add:burn:talk.srt`) or over a
## section's picture, styled as the file says (SRT gets libass's defaults) but
## for what the action overrides: font file, size, colors, and alignment. A
## frame goes through the filter stamped with its time in the layer or clip.
## The `text` action is a burn of a script written for it: one event, shown
## throughout.

import std/[hashes, math, os, strformat, strutils, tables, unicode]
import ../[action, av, ffmpeg, graph, log]
import ../util/rational

type
  SubGraph = object
    graph: Graph
    shape: (cint, cint, cint) # the width, height and format it was built for
  SubFile = tuple[index: int, playResY: float]
    ## a file's first text subtitle stream, among its subtitle streams, and
    ## the height its script's coordinates span
  SubBurner* = object
    solids: Table[(cint, cint, uint8), ptr AVFrame]
      ## opaque gray RGBA frames, by size and level, to draw on (burnOver)
    files: Table[string, SubFile] # by subtitle file
    fonts: Table[string, tuple[dir, family: string]] # by font file
    scripts: string # the folder of the scripts written for text, or ""
    graphs: Table[string, SubGraph] # by the burn action

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

proc subtitleFile(path: string): SubFile =
  ## The first text subtitle stream in `path`. Text other than ASS reaches
  ## libass under FFmpeg's default header, 288 tall.
  var container = try: av.open(path)
    except IOError: error &"burn: can't read the subtitles {path}"
  defer: container.close()
  for n, st in container.subtitle:
    let par = st.codecpar
    let d = avcodec_descriptor_get(par.codec_id)
    if d != nil and (d.props and AV_CODEC_PROP_TEXT_SUB) != 0:
      var header = ""
      if $avcodec_get_name(par.codec_id) in ["ass", "ssa"] and par.extradata_size > 0:
        header = newString(par.extradata_size)
        copyMem(addr header[0], par.extradata, par.extradata_size)
      return (n, if header.len > 0: playResY(header) else: 288.0)
  error &"burn: {path} has no text subtitles"

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

proc fontDir(b: var SubBurner, font, name: string): tuple[dir, family: string] =
  ## A folder holding just `font`, for libass to look in, and its family.
  if font notin b.fonts:
    let data = try: readFile(font) except IOError:
      error &"{name}: can't read the font {font}"
    let family = fontFamily(data)
    if family.len == 0: error &"{name}: {font} has no font family name"
    let dir = getTempDir() / &"auto-editor-burn-{getCurrentProcessId()}-{hash(font).uint:x}"
    createDir(dir)
    writeFile(dir / extractFilename(font), data)
    b.fonts[font] = (dir, family)
  b.fonts[font]

func quoted(value: string): string =
  ## A filter option value taken literally: in single quotes, each quote
  ## closed, escaped, and reopened.
  "'" & value.replace("'", "'\\''") & "'"

func assText(text: string): string =
  ## `text` as an ASS event's text says it: libass would read a backslash as
  ## an override, so a word joiner keeps it apart from what follows.
  for c in text:
    case c
    of '\n': result.add "\\N"
    of '\\': result.add "\\\u2060"
    of '{', '}': result.add "\\" & c
    else: result.add c

proc textScript(b: var SubBurner, text: Action, w, h: cint): string =
  ## A script that shows `text` throughout, in a `w`x`h` frame's own pixels.
  if b.scripts.len == 0:
    b.scripts = getTempDir() / &"auto-editor-text-{getCurrentProcessId()}"
    createDir(b.scripts)
  result = b.scripts / &"{hash($text).uint:x}-{w}x{h}.ass"
  let size = h.float * 0.08
  let outline = max(1.0, h.float * 0.002)
  let (mx, my) = (int(w.float * 0.05), int(h.float * 0.05))
  writeFile(result, &"""[Script Info]
ScriptType: v4.00+
PlayResX: {w}
PlayResY: {h}
ScaledBorderAndShadow: yes
WrapStyle: 2

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Default,Arial,{size:.2f},&H00FFFFFF,&H00FFFFFF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,{outline:.2f},0,5,{mx},{mx},{my},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text
Dialogue: 0,0:00:00.00,9:59:59.99,Default,,0,0,0,,{assText(text.burnFile)}
""")

proc close*(b: var SubBurner) =
  for f in b.solids.values:
    var f = f
    av_frame_free(addr f)
  b.solids.clear()
  for g in b.graphs.values: g.graph.cleanup()
  b.graphs.clear()
  for (dir, _) in b.fonts.values:
    try: removeDir(dir) except OSError: discard
  b.fonts.clear()
  if b.scripts.len > 0:
    try: removeDir(b.scripts) except OSError: discard
    b.scripts = ""

proc burn*(b: var SubBurner, frame: ptr AVFrame, burn: Action,
    secs: float): ptr AVFrame =
  ## `frame` with `burn`'s subtitles as they show `secs` into its layer or
  ## clip: a new frame the caller frees along with `frame`.
  let shape = (frame.width, frame.height, frame.format)
  let key = $burn
  if key notin b.graphs or b.graphs[key].shape != shape:
    if key in b.graphs: b.graphs[key].graph.cleanup()
    if avfilter_get_by_name("subtitles") == nil:
      error "burn needs FFmpeg's subtitles filter (FFmpeg built with libass)"
    var path = burn.burnFile
    if burn.kind == actText:
      path = b.textScript(burn, frame.width, frame.height)
      b.files[path] = (0, frame.height.float)
    elif path notin b.files:
      b.files[path] = subtitleFile(path)
    let file = b.files[path]
    var opts = &"filename={quoted(path)}:stream_index={file.index}"
    var style: seq[string]
    if burn.burnFont.len > 0:
      let (dir, family) = b.fontDir(burn.burnFont, if burn.kind == actText: "text" else: "burn")
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
      # libass's own border style: one box behind each subtitle, the outline
      # kept.
      style.add "BorderStyle=4"
      style.add "BackColour=" & assColor(burn.burnColors[bpBg])
    if burn.burnAlign in 1'u8 .. 9'u8:
      # force_style takes SSA's numbering, whatever the script's: the top row
      # is 5-7 and the middle 9-11.
      const ssa: array[1 .. 9, int] = [1, 2, 3, 9, 10, 11, 5, 6, 7]
      style.add &"Alignment={ssa[burn.burnAlign]}"
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
  g.pull()

proc solid(b: var SubBurner, w, h: cint, level: uint8): ptr AVFrame =
  let key = (w, h, level)
  if key notin b.solids:
    let f = av_frame_alloc()
    if f == nil: error "Could not allocate frame"
    f.format = AV_PIX_FMT_RGBA.cint
    f.width = w
    f.height = h
    if av_frame_get_buffer(f, 32) < 0: error "Could not allocate frame"
    for y in 0 ..< h.int:
      let row = cast[ptr UncheckedArray[uint8]](cast[int](f.data[0]) + y * f.linesize[0].int)
      for x in 0 ..< w.int:
        (row[x * 4], row[x * 4 + 1], row[x * 4 + 2], row[x * 4 + 3]) = (level, level, level, 255'u8)
    b.solids[key] = f
  b.solids[key]

proc burnOver*(b: var SubBurner, frame: ptr AVFrame, burn: Action, secs: float) =
  ## burn for a writable RGBA `frame` with transparency, such as a generator's
  ## clear canvas, which the subtitles filter can't write alpha to: drawn on
  ## black and on white, the two give each pixel's coverage and color, which
  ## go over `frame` in place.
  let (w, h) = (frame.width, frame.height)
  var onBlack = b.burn(b.solid(w, h, 0), burn, secs)
  var onWhite = b.burn(b.solid(w, h, 255), burn, secs)
  defer:
    av_frame_free(addr onBlack)
    av_frame_free(addr onWhite)
  for y in 0 ..< h.int:
    template row(f: ptr AVFrame): ptr UncheckedArray[uint8] =
      cast[ptr UncheckedArray[uint8]](cast[int](f.data[0]) + y * f.linesize[0].int)
    let (dst, k, wt) = (row(frame), row(onBlack), row(onWhite))
    for x in 0 ..< w.int:
      let i = x * 4
      # On white the text shows less of the background: what it covers.
      var spread = 0
      for c in 0 .. 2: spread += wt[i + c].int - k[i + c].int
      let a = clamp(255 - spread div 3, 0, 255)
      if a == 0: continue
      let fa = a.float / 255
      let da = dst[i + 3].float / 255
      let oa = fa + da * (1 - fa)
      for c in 0 .. 2:
        let src = min(255.0, k[i + c].float / fa)
        dst[i + c] = uint8(round((src * fa + dst[i + c].float * da * (1 - fa)) / oa))
      dst[i + 3] = uint8(round(oa * 255))

proc textBounds*(text: Action, w, h: cint): tuple[x, y, w, h: int] =
  ## The box `text`'s pixels cover on a clear `w`x`h` canvas, outline and
  ## all; all zero when it draws nothing.
  var b = SubBurner()
  defer: b.close()
  var f = av_frame_alloc()
  if f == nil: error "Could not allocate frame"
  defer: av_frame_free(addr f)
  f.format = AV_PIX_FMT_RGBA.cint
  f.width = w
  f.height = h
  if av_frame_get_buffer(f, 32) < 0: error "Could not allocate frame"
  for y in 0 ..< h.int:
    zeroMem(cast[pointer](cast[int](f.data[0]) + y * f.linesize[0].int), w.int * 4)
  b.burnOver(f, text, 0)
  var (x0, y0, x1, y1) = (w.int, h.int, -1, -1)
  for y in 0 ..< h.int:
    let row = cast[ptr UncheckedArray[uint8]](cast[int](f.data[0]) + y * f.linesize[0].int)
    for x in 0 ..< w.int:
      if row[x * 4 + 3] != 0:
        (x0, y0, x1, y1) = (min(x0, x), min(y0, y), max(x1, x), max(y1, y))
  if x1 >= 0: (x0, y0, x1 - x0 + 1, y1 - y0 + 1) else: (0, 0, 0, 0)
