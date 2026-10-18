## The `burn` action: libass draws a subtitle file, on a generator layer's
## clear canvas (`add:burn:talk.srt`) or over a section's picture, styled as
## the file says (SRT gets FFmpeg's default header) but for what the action
## overrides: font file, size, and colors. A frame gets the subtitles that show
## at its time in the layer or clip.

import std/[strformat, strutils, unicode]
import ../[action, ffmpeg, log]
when defined(libass):
  import std/[math, os, tables]
  import ../[av, libass]
  import ../util/rational

type SubBurner* = object
  when defined(libass):
    lib: ptr ASS_Library
    renderers: Table[(cint, cint), ptr ASS_Renderer] # by frame size
    tracks: Table[string, ptr ASS_Track] # by the burn action
    families: Table[string, string] # by font file

var fallbackFont*: string

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

func assText(text: string): string =
  for c in text:
    case c
    of '\n': result.add "\\N"
    of '\\': result.add "\\\u2060"
    of '{', '}': result.add "\\" & c
    else: result.add c

func vertAlignParts(align: uint8): tuple[h, v: string] =
  if align notin 1'u8 .. 9'u8:
    return ("center", "middle")
  let name = alignNames[align]
  let h = (if "left" in name: "left" elif "right" in name: "right" else: "center")
  let v = (if "top" in name: "top" elif "bottom" in name: "bottom" else: "middle")
  (h, v)

func verticalEvents(text: string, cell, w, h: float, align: uint8): string =
  let lines = text.splitLines()
  var maxChars = 0
  for line in lines: maxChars = max(maxChars, line.runeLen)
  let totalW = lines.len.float * cell
  let totalH = maxChars.float * cell
  let (mx, my) = (w * 0.05, h * 0.05)
  let (ha, va) = vertAlignParts(align)
  let x0 = case ha
    of "left": mx
    of "right": w - mx - totalW
    else: (w - totalW) / 2
  let y0 = case va
    of "top": my
    of "bottom": h - my - totalH
    else: (h - totalH) / 2
  for i, line in lines:
    var j = 0
    for ch in line.runes:
      let cx = x0 + totalW - cell * (i.float + 1) + cell / 2
      let cy = y0 + cell * j.float + cell / 2
      result &= &"Dialogue: 0,0:00:00.00,9:59:59.99,Default,,0,0,0,," &
        &"{{\\an5\\pos({cx:.2f},{cy:.2f})}}{assText($ch)}\n"
      inc j

func textScript(text: Action, w, h: cint): string =
  let size = h.float * 0.08
  let outline = max(1.0, h.float * 0.002)
  let (mx, my) = (int(w.float * 0.05), int(h.float * 0.05))
  let events =
    if text.burnVertical:
      let fontsize = (if text.burnSize > 0: text.burnSize.float * h.float / 100 else: size)
      verticalEvents(text.burnFile, fontsize * 1.15, w.float, h.float, text.burnAlign)
    else:
      &"Dialogue: 0,0:00:00.00,9:59:59.99,Default,,0,0,0,,{assText(text.burnFile)}\n"
  &"""[Script Info]
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
{events}"""

proc canBurn*(format: AVPixelFormat): bool =
  ## Whether `burn` draws on `format` as it is: little-endian RGB, YUV, or
  ## gray of 8 to 16 bits, with alpha only where nothing is subsampled.
  let d = av_pix_fmt_desc_get(format)
  if d == nil or d.nb_components == 0: return false
  const known = AV_PIX_FMT_FLAG_PLANAR or AV_PIX_FMT_FLAG_RGB or AV_PIX_FMT_FLAG_ALPHA
  if (d.flags and not known) != 0: return false
  if (d.flags and AV_PIX_FMT_FLAG_ALPHA) != 0 and
      (d.log2_chroma_w != 0 or d.log2_chroma_h != 0):
    return false
  let bytes = (d.comp[0].depth + 7) div 8
  for c in d.comp[0 ..< d.nb_components.int]:
    if c.depth notin 8 .. 16 or (c.depth + 7) div 8 != bytes or c.offset mod bytes != 0:
      return false
    # In a sample's high or low bits, never between.
    if c.shift != 0 and (c.shift + c.depth) mod 8 != 0: return false
  true

when defined(libass):
  func playResY(track: ptr ASS_Track): float =
    ## The height a script's coordinates (and font sizes) are in, as libass
    ## takes it: PlayResY, else from PlayResX, else 288.
    let (x, y) = (track.PlayResX, track.PlayResY)
    if y > 0: y.float
    elif x == 1280: 1024
    elif x > 0: max(1, x * 3 div 4).float
    else: 288

  proc quiet(level: cint, fmt: ConstCString, args: VaList, data: pointer) {.cdecl.} =
    # FFmpeg's own logging is off, and libass would print to stderr.
    discard

  proc library(b: var SubBurner): ptr ASS_Library =
    if b.lib == nil:
      b.lib = ass_library_init()
      if b.lib == nil: error "Could not initialize libass"
      ass_set_message_cb(b.lib, quiet, nil)
      ass_set_extract_fonts(b.lib, 1)
    b.lib

  proc renderer(b: var SubBurner, w, h: cint): ptr ASS_Renderer =
    # One for each size, since resizing a renderer empties its caches.
    result = b.renderers.getOrDefault((w, h))
    if result == nil:
      result = ass_renderer_init(b.library)
      if result == nil: error "Could not initialize libass's renderer"
      ass_set_frame_size(result, w, h)
      ass_set_storage_size(result, w, h)
      ass_set_fonts(result, nil, nil, ASS_FONTPROVIDER_AUTODETECT, nil, 1)
      b.renderers[(w, h)] = result

  proc family(b: var SubBurner, font, name: string): string =
    ## `font`'s family, which libass finds it by once it holds its data.
    if font notin b.families:
      let data = try: readFile(font) except IOError:
        error &"{name}: can't read the font {font}"
      let family = fontFamily(data)
      if family.len == 0: error &"{name}: {font} has no font family name"
      ass_add_font(b.library, extractFilename(font).cstring, data.cstring, data.len.cint)
      b.families[font] = family
    b.families[font]

  const fontMimes = ["font/ttf", "font/otf", "font/sfnt", "font/woff",
    "font/woff2", "application/font-sfnt", "application/font-woff",
    "application/x-truetype-font", "application/vnd.ms-opentype",
    "application/x-font-ttf"]

  proc fontName(st: ptr AVStream): cstring =
    ## The file name of a font attached to a container, such as a Matroska
    ## file's for its ASS track; nil for any other stream.
    if st.codecpar.codec_type != AVMEDIA_TYPE_ATTACHMENT: return nil
    let mime = av_dict_get(st.metadata, "mimetype", nil, 1)
    if mime == nil or toLowerAscii($mime.value) notin fontMimes: return nil
    let name = av_dict_get(st.metadata, "filename", nil, 1)
    if name != nil: name.value else: nil

  proc fileTrack(b: var SubBurner, path: string): ptr ASS_Track =
    ## The first text subtitle stream in `path`, with the fonts attached to it.
    var container = try: av.open(path)
      except IOError: error &"burn: can't read the subtitles {path}"
    defer: container.close()
    var st: ptr AVStream = nil
    for s in container.subtitle:
      let d = avcodec_descriptor_get(s.codecpar.codec_id)
      if d != nil and (d.props and AV_CODEC_PROP_TEXT_SUB) != 0:
        st = s
        break
    if st == nil: error &"burn: {path} has no text subtitles"
    let fmt = container.formatContext
    for i in 0 ..< fmt.nb_streams.int:
      let a = fmt.streams[i]
      let name = fontName(a)
      if name != nil:
        ass_add_font(b.library, name, cast[cstring](a.codecpar.extradata),
          a.codecpar.extradata_size)

    let codec = avcodec_find_decoder(st.codecpar.codec_id)
    if codec == nil:
      error &"burn: can't decode {avcodec_get_name(st.codecpar.codec_id)} subtitles"
    var dec = avcodec_alloc_context3(codec)
    if dec == nil: error "Could not allocate decoder ctx"
    defer: avcodec_free_context(addr dec)
    if avcodec_parameters_to_context(dec, st.codecpar) < 0:
      error &"burn: can't decode the subtitles in {path}"
    # What the decoder times each subtitle by; it's otherwise left unset.
    dec.pkt_timebase = st.time_base
    if avcodec_open2(dec, codec, nil) < 0:
      error &"burn: can't decode the subtitles in {path}"

    result = ass_new_track(b.library)
    if result == nil: error "Could not create a libass track"
    # Native ASS keeps the line breaking it was written for.
    if st.codecpar.codec_id != ID_ASS:
      discard ass_track_set_feature(result, ASS_FEATURE_WRAP_UNICODE, 1)
    if dec.subtitle_header != nil:
      ass_process_codec_private(result, cast[cstring](dec.subtitle_header),
        dec.subtitle_header_size)
    let packet = container.packet
    while av_read_frame(fmt, packet) >= 0:
      defer: av_packet_unref(packet)
      if packet.stream_index != st.index: continue
      var sub: AVSubtitle
      var got: cint = 0
      if avcodec_decode_subtitle2(dec, addr sub, addr got, packet) >= 0 and got != 0:
        let start = av_rescale_q(sub.pts, AVRational(num: 1, den: AV_TIME_BASE),
          AVRational(num: 1, den: 1000))
        for i in 0 ..< sub.num_rects.int:
          let line = sub.rects[i].ass
          if line == nil: break
          ass_process_chunk(result, line, line.len.cint, start, sub.end_display_time.clonglong)
        avsubtitle_free(addr sub)

  proc track(b: var SubBurner, burn: Action, w, h: cint): ptr ASS_Track =
    # A text's script is written for the frame's size.
    let key = if burn.kind == actText: &"{burn} {w}x{h}" else: $burn
    result = b.tracks.getOrDefault(key)
    if result != nil: return
    if burn.kind == actText:
      let script = textScript(burn, w, h)
      result = ass_read_memory(b.library, script.cstring, script.len.csize_t, nil)
      if result == nil: error "text: libass can't read its script"
    else:
      result = b.fileTrack(burn.burnFile)
    b.tracks[key] = result

    var style: seq[string]
    let font = if burn.burnFont.len > 0: burn.burnFont else: fallbackFont
    if font.len > 0:
      style.add "FontName=" & b.family(font, if burn.kind == actText: "text" else: "burn")
    if burn.burnSize > 0:
      # A percent of the frame, in the script's own coordinates.
      style.add &"Fontsize={burn.burnSize.float * result.playResY / 100:.2f}"
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
      const ssa: array[1 .. 9, int] = [1, 2, 3, 9, 10, 11, 5, 6, 7]
      style.add &"Alignment={ssa[burn.burnAlign]}"
    if style.len > 0:
      let list = allocCStringArray(style)
      defer: deallocCStringArray(list)
      ass_set_style_overrides(b.lib, list)
      ass_process_force_style(result)
      # The library keeps them, and would give them to the next script it reads.
      ass_set_style_overrides(b.lib, nil)

  proc render(b: var SubBurner, burn: Action, w, h: cint,
      secs: float): tuple[track: ptr ASS_Track, images: ptr ASS_Image] =
    result.track = b.track(burn, w, h)
    result.images = ass_render_frame(b.renderer(w, h), result.track,
      clonglong(round(secs * 1000)), nil)

  proc colorIn(frame: ptr AVFrame, d: ptr AVPixFmtDescriptor, track: ptr ASS_Track,
      color: uint32): array[3, float] =
    ## An image's color as `frame`'s components hold it, from 0 to 1.
    let rgb = [float(color shr 24), float((color shr 16) and 0xff),
      float((color shr 8) and 0xff)]
    for i in 0 .. 2: result[i] = rgb[i] / 255
    if (d.flags and AV_PIX_FMT_FLAG_RGB) != 0: return

    # A script's YCbCr Matrix names the YUV its colors were picked against,
    # as FFmpeg's subtitles filter takes it.
    var (csp, range) = (frame.colorspace.int, frame.color_range.int)
    case track.YCbCrMatrix
    of YCBCR_NONE: discard
    of YCBCR_SMPTE240M_TV, YCBCR_SMPTE240M_PC: csp = 7 # AVCOL_SPC_SMPTE240M
    of YCBCR_FCC_TV, YCBCR_FCC_PC: csp = 4 # AVCOL_SPC_FCC
    of YCBCR_BT709_TV, YCBCR_BT709_PC: csp = 1 # AVCOL_SPC_BT709
    else: csp = 6 # AVCOL_SPC_SMPTE170M
    case track.YCbCrMatrix
    of YCBCR_NONE: discard
    of YCBCR_BT601_PC, YCBCR_BT709_PC, YCBCR_SMPTE240M_PC, YCBCR_FCC_PC: range = 2
    else: range = 1
    if range == 0: # AVCOL_RANGE_UNSPECIFIED
      range = (if startsWith($AVPixelFormat(frame.format), "yuvj"): 2 else: 1)
    let luma = av_csp_luma_coeffs_from_avcsp(AVColorSpace(csp))
    let (kr, kb) =
      if luma == nil or luma.cr.den == 0: (0.299, 0.114)
      else: (luma.cr.float, luma.cb.float)
    let (r, g, b) = (result[0], result[1], result[2])
    let y = kr * r + (1 - kr - kb) * g + kb * b
    result = [y, (b - y) / (2 * (1 - kb)), (r - y) / (2 * (1 - kr))]
    if range == 1: # AVCOL_RANGE_MPEG
      result[0] = result[0] * 219 / 255 + 16 / 255
      for i in 1 .. 2: result[i] = result[i] * 224 / 255 + 128 / 255
    else:
      for i in 1 .. 2: result[i] += 0.5

  proc blend(frame: ptr AVFrame, img: ptr ASS_Image, track: ptr ASS_Track) =
    ## Draws one of libass's images, a color through a coverage mask, over
    ## `frame`: on transparency, "over" so the frame's alpha takes its coverage.
    let opacity = 255 - int(img.color and 0xff)
    let (x0, y0) = (max(img.dst_x.int, 0), max(img.dst_y.int, 0))
    let x1 = min(int(img.dst_x + img.w), frame.width.int)
    let y1 = min(int(img.dst_y + img.h), frame.height.int)
    if opacity == 0 or x0 >= x1 or y0 >= y1: return
    let d = av_pix_fmt_desc_get(AVPixelFormat(frame.format))
    let hasAlpha = (d.flags and AV_PIX_FMT_FLAG_ALPHA) != 0
    let colors = d.nb_components.int - ord(hasAlpha)
    let wide = d.comp[0].depth > 8
    let target = colorIn(frame, d, track, img.color)

    proc at(c: AVComponentDescriptor, x, y: int): pointer =
      cast[pointer](cast[int](frame.data[c.plane]) + y * frame.linesize[c.plane].int +
        x * c.step.int + c.offset.int)
    proc get(c: AVComponentDescriptor, x, y: int): float =
      let p = at(c, x, y)
      let v = (if wide: cast[ptr uint16](p)[].int else: cast[ptr uint8](p)[].int)
      v.float / float((1 shl (c.depth + c.shift)) - 1)
    proc put(c: AVComponentDescriptor, x, y: int, v: float) =
      let p = at(c, x, y)
      let n = round(v * float((1 shl (c.depth + c.shift)) - 1))
      if wide: cast[ptr uint16](p)[] = n.uint16 else: cast[ptr uint8](p)[] = n.uint8
    proc coverage(cx, cy, sw, sh: int): float =
      # A subsampled component's share of its block's mask.
      var sum = 0
      for py in max(cy shl sh, y0) ..< min((cy + 1) shl sh, y1):
        let row = (py - img.dst_y) * img.stride - img.dst_x
        for px in max(cx shl sw, x0) ..< min((cx + 1) shl sw, x1):
          sum += img.bitmap[row + px].int
      float(sum * opacity) / float((255 * 255) shl (sw + sh))

    let alpha = d.comp[d.nb_components.int - 1]
    # The colors first, each over the alpha as it was.
    for i in 0 ..< colors:
      let chroma = i > 0 and (d.flags and AV_PIX_FMT_FLAG_RGB) == 0
      let (sw, sh) = (if chroma: (d.log2_chroma_w.int, d.log2_chroma_h.int) else: (0, 0))
      let c = d.comp[i]
      for cy in (y0 shr sh) .. ((y1 - 1) shr sh):
        for cx in (x0 shr sw) .. ((x1 - 1) shr sw):
          let a = coverage(cx, cy, sw, sh)
          if a <= 0: continue
          let da = (if hasAlpha: alpha.get(cx, cy) else: 1.0)
          let oa = a + da * (1 - a)
          c.put(cx, cy, (target[i] * a + c.get(cx, cy) * da * (1 - a)) / oa)
    if hasAlpha:
      for y in y0 ..< y1:
        for x in x0 ..< x1:
          let a = coverage(x, y, 0, 0)
          if a > 0: alpha.put(x, y, a + alpha.get(x, y) * (1 - a))

proc burn*(b: var SubBurner, frame: ptr AVFrame, burn: Action, secs: float) =
  ## Draws `burn`'s subtitles as they show `secs` into its layer or clip onto
  ## `frame`, which must be writable and in a format `canBurn` takes.
  when defined(libass):
    let (track, images) = b.render(burn, frame.width, frame.height, secs)
    var img = images
    while img != nil:
      blend(frame, img, track)
      img = img.next
  else:
    error "burn and text need auto-editor built with libass"

proc close*(b: var SubBurner) =
  when defined(libass):
    for t in b.tracks.values: ass_free_track(t)
    b.tracks.clear()
    for r in b.renderers.values: ass_renderer_done(r)
    b.renderers.clear()
    b.families.clear()
    if b.lib != nil:
      ass_library_done(b.lib)
      b.lib = nil

proc textBounds*(text: Action, w, h: cint): tuple[x, y, w, h: int] =
  ## Where `text` draws on a `w` by `h` frame.
  when defined(libass):
    var b = SubBurner()
    defer: b.close()
    var (x0, y0, x1, y1) = (w.int, h.int, -1, -1)
    var img = b.render(text, w, h, 0).images
    while img != nil:
      if (img.color and 0xff) != 0xff:
        for y in max(img.dst_y.int, 0) ..< min(int(img.dst_y + img.h), h.int):
          let row = (y - img.dst_y) * img.stride - img.dst_x
          for x in max(img.dst_x.int, 0) ..< min(int(img.dst_x + img.w), w.int):
            if img.bitmap[row + x] != 0:
              (x0, y0, x1, y1) = (min(x0, x), min(y0, y), max(x1, x), max(y1, y))
      img = img.next
    if x1 >= 0: (x0, y0, x1 - x0 + 1, y1 - y0 + 1) else: (0, 0, 0, 0)
  else:
    error "text needs auto-editor built with libass"
