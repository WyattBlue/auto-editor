import std/sequtils

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

proc hevcInBandParameterSets*(data: ptr uint8, size: int): seq[uint8] =
  ## The VPS, SPS and PPS NAL units of an Annex B packet, still Annex B, or
  ## nothing unless it has all three.
  let sets = annexBParameterSets(data, size)
  if not sets.hasRequiredParameterSets:
    return
  var pos = 0
  while pos + 4 <= sets.len:
    let n = int(sets[pos]) shl 24 or int(sets[pos + 1]) shl 16 or
      int(sets[pos + 2]) shl 8 or int(sets[pos + 3])
    result.add [0'u8, 0, 0, 1]
    result.add sets[pos + 4 ..< pos + 4 + n]
    pos += 4 + n

type BitReader = object
  data: seq[uint8]
  pos: int

proc bit(r: var BitReader): int =
  if r.pos >= r.data.len * 8:
    raise newException(ValueError, "SPS ends early")
  result = int((r.data[r.pos shr 3] shr (7 - (r.pos and 7))) and 1)
  inc r.pos

proc bits(r: var BitReader, n: int): int =
  for _ in 0..<n:
    result = result shl 1 or r.bit

proc ue(r: var BitReader): int =
  var zeros = 0
  while r.bit == 0:
    inc zeros
    if zeros > 31:
      raise newException(ValueError, "bad Exp-Golomb code")
  (1 shl zeros) - 1 + r.bits(zeros)

proc annexBToHvcC*(data: ptr uint8, size: int): seq[uint8] =
  ## An hvcC record with four-byte lengths for Annex B parameter sets, or
  ## nothing without a VPS, SPS and PPS. Its header fields come from the SPS.
  let sets = annexBParameterSets(data, size)
  if not sets.hasRequiredParameterSets:
    return
  var nals: array[3, seq[seq[uint8]]]
  var pos = 0
  while pos + 4 <= sets.len:
    let n = int(sets[pos]) shl 24 or int(sets[pos + 1]) shl 16 or
      int(sets[pos + 2]) shl 8 or int(sets[pos + 3])
    pos += 4
    nals[((sets[pos] shr 1) and 0x3f).int - 32].add sets[pos ..< pos + n]
    pos += n
  let sps = nals[1][0]
  if sps.len < 15:
    return
  # hvcC stores NAL lengths and counts in sixteen bits.
  for list in nals:
    if list.len > 0xffff or list.anyIt(it.len > 0xffff):
      return

  var r = BitReader()
  var zeros = 0
  for b in sps[2 .. ^1]: # drop emulation prevention bytes
    if zeros >= 2 and b == 3:
      zeros = 0
      continue
    zeros = (if b == 0: zeros + 1 else: 0)
    r.data.add b
  if r.data.len < 13:
    return
  try:
    discard r.bits(4) # sps_video_parameter_set_id
    let maxSubLayers = r.bits(3)
    let nesting = r.bit
    let ptl = r.data[1 .. 12] # general profile, tier, flags and level
    r.pos += 96
    var profilePresent, levelPresent: array[8, bool]
    for i in 0..<maxSubLayers:
      profilePresent[i] = r.bit == 1
      levelPresent[i] = r.bit == 1
    if maxSubLayers > 0:
      r.pos += 2 * (8 - maxSubLayers)
    for i in 0..<maxSubLayers:
      if profilePresent[i]: r.pos += 88
      if levelPresent[i]: r.pos += 8
    discard r.ue # sps_seq_parameter_set_id
    let chroma = r.ue
    if chroma == 3: discard r.bit
    discard r.ue
    discard r.ue
    if r.bit == 1:
      for _ in 0..3: discard r.ue
    let lumaDepth = r.ue
    let chromaDepth = r.ue
    if chroma > 3 or lumaDepth > 7 or chromaDepth > 7:
      return
    result = @[1'u8]
    result.add ptl
    result.add [0xf0'u8, 0, 0xfc, 0xfc or uint8(chroma),
      0xf8 or uint8(lumaDepth), 0xf8 or uint8(chromaDepth), 0, 0,
      uint8((maxSubLayers + 1) shl 3 or nesting shl 2 or 3), 3]
  except ValueError:
    return
  for i, list in nals:
    result.add [uint8(32 + i), uint8(list.len shr 8), uint8(list.len and 0xff)]
    for nal in list:
      result.add [uint8(nal.len shr 8), uint8(nal.len and 0xff)]
      result.add nal

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

proc hevcSupportsPartialLossless*(format: cint, encoder: ptr AVCodec,
    header: seq[uint8]): bool =
  ## `header` is the stream's extradata, or its in-band parameter sets when
  ## it has none (MPEG-TS).
  if not encoder.encoderSupports(AVPixelFormat(format)) or header.len == 0:
    return false
  let extra = unsafeAddr header[0]
  # Annex B sources get their samples and an hvcC rewritten as they copy.
  if startCodeLen(cast[ptr UncheckedArray[uint8]](extra), header.len, 0) > 0:
    return annexBToHvcC(extra, header.len).len > 0
  # Partial-lossless samples are normalized to four-byte lengths. hvcC stores
  # lengthSizeMinusOne in byte 21; reject sources that declare another size.
  if header.len < 23 or header[0] != 1 or (header[21] and 3) != 3:
    return false
  parameterSetsToHvcc(extra, header.len).hasRequiredParameterSets
