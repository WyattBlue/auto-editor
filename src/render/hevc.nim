import ../ffmpeg
import ./smart

func nalType(data: ptr UncheckedArray[uint8], pos, size: int): int =
  if pos >= size: -1 else: int((data[pos] shr 1) and 0x3f)

proc annexBParameterSets(data: ptr uint8, size: int): seq[uint8] =
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  var pos = 0
  while pos < size:
    let codeLen = startCodeLen(bytes, size, pos)
    if codeLen == 0:
      inc pos
      continue
    let nalStart = pos + codeLen
    var next = nalStart
    while next < size and startCodeLen(bytes, size, next) == 0:
      inc next
    if bytes.nalType(nalStart, size) in 32..34:
      result.appendNal(bytes, nalStart, next)
    pos = next

proc parameterSetsToHvcc*(data: ptr uint8, size: int): seq[uint8] =
  ## Return VPS/SPS/PPS NAL units with four-byte lengths. Encoder extradata is
  ## commonly Annex B, while an MP4/Matroska source normally carries hvcC.
  if data == nil or size <= 0:
    return @[]
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  if bytes[0] != 1:
    return annexBParameterSets(data, size)
  if size < 23:
    return @[]

  var pos = 23
  let arrayCount = int(bytes[22])
  for _ in 0..<arrayCount:
    if pos + 3 > size:
      return @[]
    let typ = int(bytes[pos] and 0x3f)
    let nalCount = int(bytes[pos + 1]) shl 8 or int(bytes[pos + 2])
    pos += 3
    for _ in 0..<nalCount:
      if pos + 2 > size:
        return @[]
      let nalLen = int(bytes[pos]) shl 8 or int(bytes[pos + 1])
      pos += 2
      if nalLen <= 0 or pos + nalLen > size:
        return @[]
      if typ in 32..34:
        result.appendNal(bytes, pos, pos + nalLen)
      pos += nalLen

func hasRequiredParameterSets*(data: openArray[uint8]): bool =
  var found = [false, false, false]
  var pos = 0
  while pos + 4 <= data.len:
    let nalLen = int(data[pos]) shl 24 or int(data[pos + 1]) shl 16 or
      int(data[pos + 2]) shl 8 or int(data[pos + 3])
    pos += 4
    if nalLen <= 0 or pos + nalLen > data.len:
      return false
    let typ = int((data[pos] shr 1) and 0x3f)
    if typ in 32..34:
      found[typ - 32] = true
    pos += nalLen
  pos == data.len and found[0] and found[1] and found[2]

func hevcNalIsCopyBoundary*(typ: int): bool =
  typ in 16..20

func hevcIsCopyBoundary*(data: ptr uint8, size: int): bool =
  ## Only closed HEVC random-access pictures are safe splice boundaries. CRA
  ## (type 21) may be followed in decode order by RASL pictures that display
  ## before it, so treating CRA as a complete-GOP boundary can drop frames.
  if data == nil or size <= 0:
    return false
  let bytes = cast[ptr UncheckedArray[uint8]](data)
  let annexB = size >= 3 and startCodeLen(bytes, size, 0) > 0
  var pos = 0
  while pos < size:
    if annexB:
      let codeLen = startCodeLen(bytes, size, pos)
      if codeLen == 0:
        inc pos
        continue
      let nal = pos + codeLen
      let typ = bytes.nalType(nal, size)
      if typ.hevcNalIsCopyBoundary:
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
      let typ = bytes.nalType(pos, size)
      if typ.hevcNalIsCopyBoundary:
        return true
      pos += nalLen
  return false

func hevcSupportsPartialLossless*(stream: ptr AVStream, encoder: ptr AVCodec): bool =
  if not encoder.encoderSupports(AVPixelFormat(stream.codecpar.format)):
    return false
  # Partial-lossless samples are normalized to four-byte lengths. hvcC stores
  # lengthSizeMinusOne in byte 21; reject sources that declare another size.
  let extra = stream.codecpar.extradata
  if extra == nil or stream.codecpar.extradata_size < 23 or extra[] != 1 or
      (cast[ptr UncheckedArray[uint8]](extra)[21] and 3) != 3:
    return false
  let sourceParameterSets = parameterSetsToHvcc(extra,
    stream.codecpar.extradata_size)
  sourceParameterSets.hasRequiredParameterSets
