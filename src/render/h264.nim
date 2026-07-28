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

func h264SupportsPartialLossless*(stream: ptr AVStream): bool =
  if stream.codecpar.format != AV_PIX_FMT_YUV420P.cint:
    return false
  # Smart-rendered samples are normalized to four-byte AVCC. Match that to the
  # source's avcC length-size field rather than silently mixing layouts.
  let extra = stream.codecpar.extradata
  if extra == nil or stream.codecpar.extradata_size < 5 or extra[] != 1 or
      (cast[ptr UncheckedArray[uint8]](extra)[4] and 3) != 3:
    return false
  parameterSetsToAvcc(extra, stream.codecpar.extradata_size).len > 0
