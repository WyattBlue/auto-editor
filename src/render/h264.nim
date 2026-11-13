import ../ffmpeg
import ./smart

proc parameterSetsToAvcc*(data: ptr uint8, size: int): seq[uint8] =
  ## Return SPS/PPS NAL units with four-byte lengths. Encoder extradata is
  ## commonly Annex B, while an MP4/Matroska source normally carries avcC.
  if data == nil or size <= 0:
    return @[]
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  if bytes[0] != 1:
    return annexBToLengthPrefixed(data, size)
  if size < 7:
    return @[]

  var pos = 6
  let spsCount = int(bytes[5] and 0x1f)
  for _ in 0..<spsCount:
    if pos + 2 > size: return @[]
    let nalLen = int(bytes[pos]) shl 8 or int(bytes[pos + 1])
    pos += 2
    if pos + nalLen > size: return @[]
    result.appendNal(bytes, pos, pos + nalLen)
    pos += nalLen
  if pos >= size:
    return
  let ppsCount = int(bytes[pos])
  inc pos
  for _ in 0..<ppsCount:
    if pos + 2 > size: return @[]
    let nalLen = int(bytes[pos]) shl 8 or int(bytes[pos + 1])
    pos += 2
    if pos + nalLen > size: return @[]
    result.appendNal(bytes, pos, pos + nalLen)
    pos += nalLen

func h264IsCopyBoundary*(data: ptr uint8, size: int): bool =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  var pos = 0
  let annexB = size >= 3 and startCodeLen(bytes, size, 0) > 0
  while pos < size:
    if annexB:
      let codeLen = startCodeLen(bytes, size, pos)
      if codeLen == 0:
        inc pos
        continue
      let nal = pos + codeLen
      if nal < size and (bytes[nal] and 0x1f) == 5:
        return true
      pos = nal + 1
    else:
      if pos + 4 > size:
        break
      let nalLen = int(bytes[pos]) shl 24 or int(bytes[pos + 1]) shl 16 or
        int(bytes[pos + 2]) shl 8 or int(bytes[pos + 3])
      pos += 4
      if nalLen <= 0 or pos + nalLen > size:
        return false
      if (bytes[pos] and 0x1f) == 5:
        return true
      pos += nalLen
  return false

func isAnnexB*(data: ptr uint8, size: int): bool =
  ## Whether extradata is Annex B (start codes, as in MPEG-TS) rather than avcC.
  size >= 4 and startCodeLen(cast[ptr UncheckedArray[uint8]](data), size, 0) > 0

proc annexBToAvcC*(data: ptr uint8, size: int): seq[uint8] =
  ## An avcC record with four-byte lengths for Annex B parameter sets, or
  ## nothing without both an SPS and a PPS. Only 8-bit 4:2:0 streams reach
  ## partial-lossless, so the High profiles' chroma fields are fixed.
  let nals = annexBToLengthPrefixed(data, size)
  var sps, pps: seq[seq[uint8]]
  var pos = 0
  while pos + 4 <= nals.len:
    let n = int(nals[pos]) shl 24 or int(nals[pos + 1]) shl 16 or
      int(nals[pos + 2]) shl 8 or int(nals[pos + 3])
    pos += 4
    if n <= 0 or pos + n > nals.len: return @[]
    case nals[pos] and 0x1f
    of 7: sps.add nals[pos ..< pos + n]
    of 8: pps.add nals[pos ..< pos + n]
    else: discard
    pos += n
  if sps.len == 0 or pps.len == 0 or sps[0].len < 4:
    return @[]
  result = @[1'u8, sps[0][1], sps[0][2], sps[0][3], 0xff'u8,
    0xe0'u8 or uint8(sps.len)]
  for s in sps:
    result.add [uint8(s.len shr 8), uint8(s.len and 0xff)]
    result.add s
  result.add uint8(pps.len)
  for p in pps:
    result.add [uint8(p.len shr 8), uint8(p.len and 0xff)]
    result.add p
  if sps[0][1] in [100'u8, 110, 122, 144]:
    # chroma_format_idc 1, 8-bit luma and chroma, no SPS extensions
    result.add [0xfd'u8, 0xf8, 0xf8, 0x00]

proc annexBParameterSets*(data: ptr uint8, size: int): seq[uint8] =
  ## The SPS and PPS NAL units of an Annex B packet, still Annex B, or
  ## nothing unless it has both.
  let nals = annexBToLengthPrefixed(data, size)
  var sawSps, sawPps = false
  var pos = 0
  while pos + 4 <= nals.len:
    let n = int(nals[pos]) shl 24 or int(nals[pos + 1]) shl 16 or
      int(nals[pos + 2]) shl 8 or int(nals[pos + 3])
    pos += 4
    if n <= 0 or pos + n > nals.len: return @[]
    let kind = nals[pos] and 0x1f
    if kind in [7'u8, 8]:
      result.add [0'u8, 0, 0, 1]
      result.add nals[pos ..< pos + n]
      if kind == 7: sawSps = true else: sawPps = true
    pos += n
  if not (sawSps and sawPps):
    result.setLen(0)

proc h264SupportsPartialLossless*(format: cint, header: seq[uint8]): bool =
  ## `header` is the stream's extradata, or its in-band parameter sets when
  ## it has none (MPEG-TS).
  if format != AV_PIX_FMT_YUV420P.cint or header.len == 0:
    return false
  let extra = unsafeAddr header[0]
  # Annex B sources get their samples and an avcC rewritten as they copy.
  if isAnnexB(extra, header.len):
    return annexBToAvcC(extra, header.len).len > 0
  # Smart-rendered samples are normalized to four-byte AVCC. Match that to the
  # source's avcC length-size field rather than silently mixing layouts.
  if header.len < 5 or header[0] != 1 or (header[4] and 3) != 3:
    return false
  parameterSetsToAvcc(extra, header.len).len > 0
