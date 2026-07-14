when defined(macosx):
  import std/strformat

  type AudioObjectPropertyAddress {.importc, header: "<CoreAudio/CoreAudio.h>", bycopy.} = object
    mSelector: uint32
    mScope: uint32
    mElement: uint32

  const
    kAudioObjectSystemObject = 1'u32
    kAudioHardwarePropertyDevices = 0x64657623'u32             # 'dev#'
    kAudioHardwarePropertyDefaultInputDevice = 0x64496E20'u32  # 'dIn '
    kAudioObjectPropertyName = 0x6C6E616D'u32                  # 'lnam'
    kAudioObjectPropertyScopeGlobal = 0x676C6F62'u32           # 'glob'
    kAudioObjectPropertyScopeInput = 0x696E7074'u32            # 'inpt'
    kAudioDevicePropertyStreams = 0x73746D23'u32               # 'stm#'
    kAudioDevicePropertyTransportType = 0x7472616E'u32         # 'tran'
    kAudioDeviceTransportTypeUSB = 0x75736220'u32              # 'usb '
    kAudioDeviceTransportTypeVirtual = 0x76697274'u32          # 'virt'
    kCFStringEncodingUTF8 = 0x08000100'u32

  proc AudioObjectGetPropertyData(inObjectID: uint32,
    inAddress: ptr AudioObjectPropertyAddress, inQualifierDataSize: uint32,
    inQualifierData: pointer, ioDataSize: ptr uint32,
    outData: pointer): int32 {.importc, header: "<CoreAudio/CoreAudio.h>".}
  proc AudioObjectGetPropertyDataSize(inObjectID: uint32,
    inAddress: ptr AudioObjectPropertyAddress, inQualifierDataSize: uint32,
    inQualifierData: pointer, outDataSize: ptr uint32): int32 {.importc, header: "<CoreAudio/CoreAudio.h>".}
  proc CFStringGetCString(theString: pointer, buffer: cstring, bufferSize: int,
    encoding: uint32): uint8 {.importc, header: "<CoreFoundation/CoreFoundation.h>".}
  proc CFRelease(cf: pointer) {.importc, header: "<CoreFoundation/CoreFoundation.h>".}

  proc propAddr(selector, scope: uint32): AudioObjectPropertyAddress =
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: 0)

  proc deviceName(devId: uint32): string =
    var name: pointer = nil  # CFStringRef
    var size = uint32(sizeof(name))
    var a = propAddr(kAudioObjectPropertyName, kAudioObjectPropertyScopeGlobal)
    if AudioObjectGetPropertyData(devId, addr a, 0, nil, addr size, addr name) != 0 or name == nil:
      return ""
    var buf: array[256, char]
    if CFStringGetCString(name, cast[cstring](addr buf[0]), buf.len, kCFStringEncodingUTF8) != 0:
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
    var a = propAddr(kAudioHardwarePropertyDefaultInputDevice, kAudioObjectPropertyScopeGlobal)
    discard AudioObjectGetPropertyData(kAudioObjectSystemObject, addr a, 0, nil, addr size, addr result)

  proc inputDevices(): seq[uint32] =
    var size: uint32 = 0
    var a = propAddr(kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal)
    if AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, addr a, 0, nil, addr size) != 0 or size == 0:
      return
    var ids = newSeq[uint32](int(size) div sizeof(uint32))
    if AudioObjectGetPropertyData(kAudioObjectSystemObject, addr a, 0, nil, addr size, addr ids[0]) != 0:
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
        candidates.add id  # never auto-select virtual devices
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
  import ./ffmpeg

  proc chooseMicDevice*(inputFormat: pointer): tuple[name, description, warning: string] =
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
