import std/[os, strformat, typedthreads]
import ./[av, ffmpeg, log]
import ./util/rational

when defined(macosx):

  type AudioObjectPropertyAddress {.importc, header: "<CoreAudio/CoreAudio.h>",
      bycopy.} = object
    mSelector: uint32
    mScope: uint32
    mElement: uint32

  const
    kAudioObjectSystemObject = 1'u32
    kAudioHardwarePropertyDevices = 0x64657623'u32            # 'dev#'
    kAudioHardwarePropertyDefaultInputDevice = 0x64496E20'u32 # 'dIn '
    kAudioObjectPropertyName = 0x6C6E616D'u32                 # 'lnam'
    kAudioObjectPropertyScopeGlobal = 0x676C6F62'u32          # 'glob'
    kAudioObjectPropertyScopeInput = 0x696E7074'u32           # 'inpt'
    kAudioDevicePropertyStreams = 0x73746D23'u32              # 'stm#'
    kAudioDevicePropertyTransportType = 0x7472616E'u32        # 'tran'
    kAudioDeviceTransportTypeUSB = 0x75736220'u32             # 'usb '
    kAudioDeviceTransportTypeVirtual = 0x76697274'u32         # 'virt'
    kCFStringEncodingUTF8 = 0x08000100'u32

  proc AudioObjectGetPropertyData(inObjectID: uint32,
    inAddress: ptr AudioObjectPropertyAddress, inQualifierDataSize: uint32,
    inQualifierData: pointer, ioDataSize: ptr uint32,
    outData: pointer): int32 {.importc, header: "<CoreAudio/CoreAudio.h>".}
  proc AudioObjectGetPropertyDataSize(inObjectID: uint32,
    inAddress: ptr AudioObjectPropertyAddress, inQualifierDataSize: uint32,
    inQualifierData: pointer, outDataSize: ptr uint32): int32 {.importc,
        header: "<CoreAudio/CoreAudio.h>".}
  proc CFStringGetCString(theString: pointer, buffer: cstring, bufferSize: int,
    encoding: uint32): uint8 {.importc, header: "<CoreFoundation/CoreFoundation.h>".}
  proc CFRelease(cf: pointer) {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

  proc propAddr(selector, scope: uint32): AudioObjectPropertyAddress =
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: 0)

  proc deviceName(devId: uint32): string =
    var name: pointer = nil # CFStringRef
    var size = uint32(sizeof(name))
    var a = propAddr(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
    if AudioObjectGetPropertyData(devId, addr a, 0, nil, addr size, addr name) != 0 or
        name == nil:
      return ""
    var buf: array[256, char]
    if CFStringGetCString(name, cast[cstring](addr buf[0]), buf.len,
        kCFStringEncodingUTF8) != 0:
      result = $cast[cstring](addr buf[0])
    CFRelease(name)

  proc deviceTransport(devId: uint32): uint32 =
    var size = uint32(sizeof(result))
    var a = propAddr(kAudioDevicePropertyTransportType, kAudioObjectPropertyScopeGlobal)
    discard AudioObjectGetPropertyData(devId, addr a, 0, nil, addr size, addr result)

  proc hasInput(devId: uint32): bool =
    var size: uint32 = 0
    var a = propAddr(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
    AudioObjectGetPropertyDataSize(devId, addr a, 0, nil, addr size) == 0 and size > 0

  proc defaultInputId(): uint32 =
    var size = uint32(sizeof(result))
    var a = propAddr(kAudioHardwarePropertyDefaultInputDevice,
      kAudioObjectPropertyScopeGlobal)
    discard AudioObjectGetPropertyData(kAudioObjectSystemObject, addr a, 0, nil,
        addr size, addr result)

  proc inputDevices(): seq[uint32] =
    var size: uint32 = 0
    var a = propAddr(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
    if AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, addr a, 0, nil,
        addr size) != 0 or size == 0:
      return
    var ids = newSeq[uint32](int(size) div sizeof(uint32))
    if AudioObjectGetPropertyData(kAudioObjectSystemObject, addr a, 0, nil, addr size,
        addr ids[0]) != 0:
      return
    for id in ids:
      if hasInput(id):
        result.add id

  proc chooseMicDevice*(): tuple[name: string, warning: string] =
    ## Picks an input device: a USB mic if present, else the system default (with
    ## a warning). Virtual devices (e.g. "Microsoft Teams Audio") are never
    ## auto-selected. `name` is "" when no usable device exists.
    var candidates: seq[uint32]
    for id in inputDevices():
      if deviceTransport(id) != kAudioDeviceTransportTypeVirtual:
        candidates.add id # never auto-select virtual devices
    if candidates.len == 0:
      return ("", "")

    for id in candidates:
      if deviceTransport(id) == kAudioDeviceTransportTypeUSB:
        return (deviceName(id), "")

    # No USB mic: fall back to the system default input if it's a candidate.
    let def = defaultInputId()
    let fallback = if def != 0 and def in candidates: def else: candidates[0]
    let name = deviceName(fallback)
    return (name, &"No USB microphone found, using \"{name}\"")

elif defined(windows):
  import std/strutils

  proc chooseMicDevice*(inputFormat: pointer): tuple[name, description,
      warning: string] =
    ## DirectShow has no special name for the default capture device, so ask
    ## libavdevice for its audio sources. Prefer a USB microphone when one is
    ## identifiable, then fall back to the first audio capture device.
    var devices: ptr AVDeviceInfoList
    if avdevice_list_input_sources(inputFormat, nil, nil, addr devices) < 0 or
        devices == nil:
      return
    defer: avdevice_free_list_devices(addr devices)

    var fallback: ptr AVDeviceInfo
    for i in 0 ..< devices.nb_devices.int:
      let device = devices.devices[i]
      var hasAudio = false
      for j in 0 ..< device.nb_media_types.int:
        if device.media_types[j] == AVMEDIA_TYPE_AUDIO:
          hasAudio = true
          break
      if not hasAudio:
        continue
      if fallback == nil:
        fallback = device
      let description = $device.device_description
      if description.toLowerAscii.contains("usb"):
        return ($device.device_name, description, "")

    if fallback != nil:
      let description = $fallback.device_description
      return ($fallback.device_name, description,
              "No USB microphone found, using \"" & description & "\"")

type MicInput* = object
  formatContext*: ptr AVFormatContext
  audioStream*: ptr AVStream
  name*: string

proc openMic*(): MicInput =
  var formatName, deviceName, sourceName: string
  when defined(macosx):
    let (devName, warnMsg) = chooseMicDevice()
    formatName = "avfoundation"
    deviceName = devName
    sourceName = ":" & devName
  elif defined(windows):
    formatName = "dshow"
  elif defined(linux) and not defined(emscripten):
    formatName = "alsa"
    deviceName = "default"
    sourceName = "default"
  else:
    error "Microphone capture (:mic) is not supported on this platform"

  avdevice_register_all()
  let inputFormat = av_find_input_format(formatName.cstring)
  if inputFormat == nil:
    error &"Could not find {formatName} input device"

  when defined(windows):
    let (devName, description, warnMsg) = chooseMicDevice(inputFormat)
    deviceName = devName
    result.name = description
    sourceName = "audio=" & devName
  else:
    result.name = deviceName

  when defined(macosx) or defined(windows):
    if deviceName == "":
      error "No microphone found"
    if warnMsg != "":
      warning warnMsg

  if avformat_open_input(addr result.formatContext, sourceName.cstring,
      inputFormat, nil) < 0:
    error &"Could not open microphone \"{result.name}\""
  if avformat_find_stream_info(result.formatContext, nil) < 0:
    avformat_close_input(addr result.formatContext)
    error "Could not read microphone stream info"
  for i in 0 ..< result.formatContext.nb_streams.int:
    if result.formatContext.streams[i].codecpar.codec_type == AVMEDIA_TYPE_AUDIO:
      result.audioStream = result.formatContext.streams[i]
      break
  if result.audioStream == nil:
    avformat_close_input(addr result.formatContext)
    error "Microphone has no audio stream"

proc close*(input: var MicInput) =
  avformat_close_input(addr input.formatContext)

# Gap detection: the device stamps packets from its own clock, so a pts jump
# larger than the audio a packet carries means buffers were lost in between.
# A microphone can't resend, so the hole is filled with silence to keep the
# stream at wall-clock length.
type GapFiller* = object
  timeBase: AVRational
  sampleRate: cint
  bytesPerFrame: int # 0 = not PCM, packet durations unknown, no detection
  nextPts: int64 # where the next packet should start; AV_NOPTS_VALUE at first
  firstPts: int64 # capture start, to say where in the recording a gap is
  pending: ptr AVPacket # the real packet, held back while silence goes first
  missing: int64 # samples of silence still owed before `pending`

proc initGapFiller*(timeBase: AVRational, sampleRate: cint,
    bytesPerFrame: int): GapFiller =
  GapFiller(timeBase: timeBase, sampleRate: sampleRate,
    bytesPerFrame: bytesPerFrame, nextPts: AV_NOPTS_VALUE,
    firstPts: AV_NOPTS_VALUE)

proc initGapFiller*(stream: ptr AVStream): GapFiller =
  let par = stream.codecpar
  let bits = av_get_bits_per_sample(par.codec_id)
  var bytesPerFrame = 0
  if bits > 0 and par.ch_layout.nb_channels > 0 and par.sample_rate > 0:
    bytesPerFrame = (bits div 8) * par.ch_layout.nb_channels
  initGapFiller(stream.time_base, par.sample_rate, bytesPerFrame)

proc hasPending*(g: GapFiller): bool = g.pending != nil

proc feed*(g: var GapFiller, src: ptr AVPacket) =
  ## Take ownership of the next captured packet; `emit` hands it back, after
  ## any silence it is owed.
  assert g.pending == nil
  g.pending = src
  g.missing = 0
  if g.bytesPerFrame == 0 or src.pts == AV_NOPTS_VALUE:
    return
  if g.firstPts == AV_NOPTS_VALUE:
    g.firstPts = src.pts
  if g.nextPts == AV_NOPTS_VALUE:
    return
  let sampleTb = AVRational(num: 1, den: g.sampleRate)
  let missing = av_rescale_q(src.pts - g.nextPts, g.timeBase, sampleTb)
  # Below 5ms is clock jitter (alsa stamps from a filtered wall clock), and
  # the smallest device buffer is larger than that.
  if missing >= g.sampleRate div 200:
    g.missing = missing
    let at = av_rescale_q(g.nextPts - g.firstPts, g.timeBase,
      AVRational(num: 1, den: 1000))
    warning &"Microphone dropped {missing * 1000 div g.sampleRate} ms of audio " &
      &"at {at div 1000}.{at mod 1000:03} s"

proc emit*(g: var GapFiller, pkt: ptr AVPacket) =
  ## Move the next packet into `pkt`: up to 1s of silence while any is owed
  ## (a laptop waking from sleep owes hours; keep allocations bounded), else
  ## the fed packet itself.
  assert g.pending != nil
  let sampleTb = AVRational(num: 1, den: g.sampleRate)
  if g.missing > 0:
    let samples = min(g.missing, g.sampleRate.int64)
    if av_new_packet(pkt, cint(samples * g.bytesPerFrame)) < 0:
      error "out of memory"
    zeroMem(pkt.data, pkt.size)
    pkt.pts = g.nextPts
    pkt.dts = g.nextPts
    pkt.duration = av_rescale_q(samples, sampleTb, g.timeBase)
    pkt.stream_index = g.pending.stream_index
    pkt.flags = AV_PKT_FLAG_KEY
    g.nextPts += pkt.duration
    g.missing -= samples
    return
  if g.bytesPerFrame > 0 and g.pending.pts != AV_NOPTS_VALUE:
    # Resync to the device clock, so sub-threshold jitter never accumulates.
    g.nextPts = g.pending.pts + av_rescale_q(g.pending.size div g.bytesPerFrame,
      sampleTb, g.timeBase)
  av_packet_move_ref(pkt, g.pending)
  av_packet_free(addr g.pending)

proc close*(g: var GapFiller) =
  if g.pending != nil:
    av_packet_free(addr g.pending)

# The capture devices hold little: dshow drops once its rtbufsize fills and
# alsa overruns, so a consumer stall longer than that silently loses audio
# (avfoundation queues on its own, see patches/ffmpeg.patch). So a thread does
# nothing but av_read_frame into an unbounded queue; decoding, gating, muxing
# and the whisper model load all happen behind that queue, where a stall only
# adds latency. A microphone can't retransmit, so buffering is the only option.
type
  MicReaderArgs = object
    fmtCtx: ptr AVFormatContext
    stop: ptr bool # the caller's Ctrl-C flag
    packets: Channel[ptr AVPacket]
    streamIndex: cint
    err: cint # why reading ended; 0 = asked to stop
    quit: bool # set by close()

  MicReader* = ref object
    args: MicReaderArgs
    thread: Thread[ptr MicReaderArgs]
    gaps: GapFiller
    finished: bool # the end sentinel has been received
    closed: bool

proc readerLoop(a: ptr MicReaderArgs) {.thread.} =
  var pkt = av_packet_alloc()
  while pkt != nil and not (a.stop[] or a.quit):
    let ret = av_read_frame(a.fmtCtx, pkt)
    if ret == AVERROR_EAGAIN:
      # avfoundation never blocks; it just says nothing is ready yet.
      sleep(2)
      continue
    if ret < 0:
      if not (a.stop[] or a.quit):
        a.err = ret
      break
    if pkt.stream_index != a.streamIndex:
      av_packet_unref(pkt)
      continue
    a.packets.send(pkt) # the consumer frees it
    pkt = av_packet_alloc()
  if pkt == nil:
    a.err = AVERROR(ENOMEM)
  else:
    av_packet_free(addr pkt)
  a.packets.send(nil) # end sentinel

proc newMicReader*(input: MicInput, stop: ptr bool): MicReader =
  ## Start capturing from `input` right away; packets queue up until `next` is
  ## called. Reading ends when `stop[]` is set, `close` is called, or the
  ## device fails.
  result = MicReader(gaps: initGapFiller(input.audioStream))
  result.args = MicReaderArgs(fmtCtx: input.formatContext,
    streamIndex: input.audioStream.index, stop: stop)
  result.args.packets.open()
  createThread(result.thread, readerLoop, addr result.args)

proc next*(r: MicReader, pkt: ptr AVPacket): cint =
  ## Move the next captured packet into `pkt`. Returns 0, or a negative AVERROR
  ## once capture has ended: AVERROR_EOF when it was stopped on request, the
  ## device's error otherwise. Everything captured before the end is still
  ## delivered first, with silence filling any hole the device left.
  if r.finished:
    return AVERROR_EOF
  if not r.gaps.hasPending:
    let src = r.args.packets.recv()
    if src == nil:
      r.finished = true
      return (if r.args.err != 0: r.args.err else: AVERROR_EOF)
    r.gaps.feed(src)
  r.gaps.emit(pkt)
  return 0

proc close*(r: MicReader) =
  ## Stop reading and join the thread. Must happen before the format context
  ## is closed. Queued packets that were never consumed are freed.
  if r.closed:
    return
  r.closed = true
  r.args.quit = true
  joinThread(r.thread)
  r.gaps.close()
  while true:
    let (ok, p) = r.args.packets.tryRecv()
    if not ok: break
    if p != nil:
      var pkt = p
      av_packet_free(addr pkt)
  r.args.packets.close()
  r.finished = true

proc recordMic*(outputPath: string, shouldStop: ptr bool) =
  var input = openMic()
  defer: input.close()
  let reader = newMicReader(input, shouldStop)
  defer: reader.close()

  var output = av.openWrite(outputPath)
  let outputStream = output.addStreamFromTemplate(input.audioStream)
  outputStream.time_base = input.audioStream.time_base
  output.startEncoding()
  defer: output.close()

  let packet = av_packet_alloc()
  if packet == nil:
    error "Could not allocate microphone packet"
  defer: av_packet_free(addr packet)

  var firstTs = AV_NOPTS_VALUE
  var packetsWritten = 0
  stderr.writeLine(&"Listening on \"{input.name}\"... (press Ctrl-C to stop)")
  while true:
    let ret = reader.next(packet)
    if ret == AVERROR_EOF:
      break
    if ret < 0:
      error &"Could not read microphone: {av_err2str(ret)}"
    let ts = if packet.dts != AV_NOPTS_VALUE: packet.dts else: packet.pts
    if firstTs == AV_NOPTS_VALUE and ts != AV_NOPTS_VALUE:
      firstTs = ts
    if firstTs != AV_NOPTS_VALUE:
      if packet.pts != AV_NOPTS_VALUE: packet.pts -= firstTs
      if packet.dts != AV_NOPTS_VALUE: packet.dts -= firstTs
    packet.stream_index = 0
    packet.time_base = input.audioStream.time_base
    output.mux(packet[])
    inc packetsWritten
    av_packet_unref(packet)

  stderr.writeLine("")
  if packetsWritten == 0:
    error "No microphone audio was captured"
