import std/[options, strutils]

type
  ActionKind* = enum
    actSpeed, actVarispeed, actVolume, actInvert, actZoom, actHflip, actVflip,
    actOpacity, actBlur, actBrightness, actLuv

  # Represents a full-sized action.
  Action* = object
    case kind*: ActionKind
    of actInvert, actHflip, actVflip:
      discard
    of actSpeed, actVarispeed, actVolume, actZoom, actOpacity, actBlur, actBrightness:
      val*: float32
    of actLuv:
      brighthue*: float32
      contrast*: float32
      saturation*: float32

  Actions* = distinct int # A fat pointer to a list of action in atf-8 format.

  # atf-8: store actions in as small a space as possible, inspirited by utf-8.

  ActionParseError* = object of CatchableError

  ActionDef* = object
    name*: string
    argSpec*: string  # e.g., "val: float"
    range*: string    # e.g., "(0-99999)"
    help*: string

const
  luvBrighthueId*: float32 = 0.0
  luvContrastId*: float32 = 1.0
  luvSaturationId*: float32 = 1.0

const actionDefs*: seq[ActionDef] = @[
  ActionDef(name: "nil",
    help: "Do nothing. Keep the section unchanged at normal speed and pitch."),
  ActionDef(name: "cut",
    help: "Remove the section completely from the output."),
  ActionDef(name: "speed", argSpec: "val: float", range: "(0-99999)",
    help: """
Change the playback speed while preserving pitch using time-stretching.
Implemented with FFmpeg's `atempo` filter."""),
  ActionDef(name: "varispeed", argSpec: "val: float", range: "[0.2-100]",
    help: """
Change the playback speed by varying pitch, like analog tape or vinyl.
Implemented with FFmpeg's `asetrate` + `aresample` filters, which change the sample rate so speed and pitch shift together."""),
  ActionDef(name: "volume", argSpec: "val: float",
    help: """
Adjust the audio volume by a factor of val. 1.0 = normal, 0.5 = half (-6dB), 2.0 = double (+6dB)."""),
  ActionDef(name: "invert",
    help: "Invert all pixels in the video section."),
  ActionDef(name: "hflip",
    help: "Flip the video section horizontally."),
  ActionDef(name: "vflip",
    help: "Flip the video section vertically."),
  ActionDef(name: "zoom", argSpec: "val: float", range: "(0, 100]",
    help: "Zoom in or out by a factor of val. 1.0 = no zoom."),
  ActionDef(name: "opacity", argSpec: "val: float", range: "[0.0, 1.0]",
    help: "Blend the video section against the background. 1.0 = fully opaque, 0.0 = fully transparent."),
  ActionDef(name: "blur", argSpec: "val: float", range: "[0, 1024]",
    help: "Gaussian blur the video section by sigma=val. 0 = no blur; larger values blur more."),
  ActionDef(name: "brightness", argSpec: "val: float", range: "[-1.0, 1.0]",
    help: "Shift video brightness (adds an equal offset to R, G, B). 0.0 = unchanged. Implemented via FFmpeg's `lutrgb` filter."),
  ActionDef(name: "brighthue", argSpec: "val: float", range: "[-1.0, 1.0]",
    help: "Shift video luma (Y channel). 0.0 = unchanged."),
  ActionDef(name: "contrast", argSpec: "val: float", range: "[-2.0, 2.0]",
    help: "Scale video contrast. 1.0 = unchanged. Implemented via FFmpeg's `lutyuv` filter."),
  ActionDef(name: "saturation", argSpec: "val: float", range: "[0.0, 3.0]",
    help: "Scale video saturation. 1.0 = unchanged, 0.0 = grayscale. Implemented via FFmpeg's `lutyuv` filter."),
]

func `==`*(a, b: Action): bool =
  if a.kind != b.kind: return false
  case a.kind
  of actInvert, actHflip, actVflip: true
  of actSpeed, actVarispeed, actVolume, actZoom, actOpacity, actBlur, actBrightness: a.val == b.val
  of actLuv:
    a.brighthue == b.brighthue and a.contrast == b.contrast and
      a.saturation == b.saturation


const aNil* = Actions(0)
const aCut* = Actions(1)

func isCut*(a: Actions): bool = int(a) == 1
func isEmpty*(a: Actions): bool = int(a) == 0

func parseAction*(val: string): Option[Action] =
  if val == "invert":
    return some(Action(kind: actInvert))
  if val == "hflip":
    return some(Action(kind: actHflip))
  if val == "vflip":
    return some(Action(kind: actVflip))

  let parts = val.split(":")
  if parts.len == 2:
    let effectType = parts[0]
    let effectVal = (
      try: parseFloat(parts[1])
      except ValueError: return none(Action)
    )
    case effectType
    of "speed": return some(Action(kind: actSpeed, val: effectVal))
    of "volume": return some(Action(kind: actVolume, val: effectVal))
    of "varispeed": return some(Action(kind: actVarispeed, val: effectVal))
    of "zoom": return some(Action(kind: actZoom, val: effectVal))
    of "opacity": return some(Action(kind: actOpacity, val: effectVal))
    of "blur": return some(Action(kind: actBlur, val: effectVal))
    of "brightness": return some(Action(kind: actBrightness, val: effectVal))
    of "brighthue":
      return some(Action(kind: actLuv, brighthue: effectVal,
        contrast: luvContrastId, saturation: luvSaturationId))
    of "contrast":
      return some(Action(kind: actLuv, brighthue: luvBrighthueId,
        contrast: effectVal, saturation: luvSaturationId))
    of "saturation":
      return some(Action(kind: actLuv, brighthue: luvBrighthueId,
        contrast: luvContrastId, saturation: effectVal))
    else: return none(Action)

  return none(Action)

when not defined(nimscript):
  func `$`*(act: Action): string =
    case act.kind
    of actInvert: "invert"
    of actHflip: "hflip"
    of actVflip: "vflip"
    of actSpeed: "speed:" & $act.val
    of actVarispeed: "varispeed:" & $act.val
    of actVolume: "volume:" & $act.val
    of actZoom: "zoom:" & $act.val
    of actOpacity: "opacity:" & $act.val
    of actBlur: "blur:" & $act.val
    of actBrightness: "brightness:" & $act.val
    of actLuv:
      var parts: seq[string]
      if act.brighthue != luvBrighthueId: parts.add "brighthue:" & $act.brighthue
      if act.contrast != luvContrastId: parts.add "contrast:" & $act.contrast
      if act.saturation != luvSaturationId: parts.add "saturation:" & $act.saturation
      if parts.len == 0: "brighthue:0.0" else: parts.join(",")

  func actionByteSize(kind: ActionKind): int =
    case kind
    of actInvert, actHflip, actVflip: 1
    of actSpeed, actVarispeed, actVolume, actZoom, actOpacity, actBlur, actBrightness: 5
    of actLuv: 13

  func len*(a: Actions): int =  # byte length
    if int(a) <= 1: 0
    else: int(cast[ptr uint16](int(a))[])

  iterator items*(a: Actions): Action =
    if int(a) > 1:
      let n = a.len
      let base = cast[ptr UncheckedArray[uint8]](int(a) + sizeof(uint16))
      var i = 0
      while i < n:
        let kind = cast[ActionKind](base[i])
        case kind
        of actInvert, actHflip, actVflip:
          yield Action(kind: kind)
          i += 1
        of actSpeed, actVarispeed, actVolume, actZoom, actOpacity, actBlur, actBrightness:
          var v: float32
          copyMem(addr v, addr base[i + 1], sizeof(float32))
          yield Action(kind: kind, val: v)
          i += 5
        of actLuv:
          var b, c, s: float32
          copyMem(addr b, addr base[i + 1], sizeof(float32))
          copyMem(addr c, addr base[i + 5], sizeof(float32))
          copyMem(addr s, addr base[i + 9], sizeof(float32))
          yield Action(kind: actLuv, brighthue: b, contrast: c, saturation: s)
          i += 13

  func actionLen*(a: Actions): int =  # O(n)
    for _ in a: inc result

  func `==`*(a, b: Actions): bool =
    let ia = int(a)
    let ib = int(b)
    if ia == ib: return true
    if ia <= 1 or ib <= 1: return false
    let n = a.len
    if n != b.len: return false
    let pa = cast[ptr UncheckedArray[uint8]](ia + sizeof(uint16))
    let pb = cast[ptr UncheckedArray[uint8]](ib + sizeof(uint16))
    for i in 0 ..< n:
      if pa[i] != pb[i]: return false
    true

  proc newActions*(list: openArray[Action]): Actions =
    if list.len == 0: return aNil
    var total = 0
    for a in list: total += actionByteSize(a.kind)
    if total > 65535:
      raise newException(ActionParseError, "atf-8 buffer overflow: too many actions")
    let p = alloc(sizeof(uint16) + total)
    cast[ptr uint16](p)[] = uint16(total)
    let base = cast[ptr UncheckedArray[uint8]](cast[int](p) + sizeof(uint16))
    var i = 0
    for a in list:
      base[i] = uint8(ord(a.kind))
      case a.kind
      of actInvert, actHflip, actVflip:
        i += 1
      of actSpeed, actVarispeed, actVolume, actZoom, actOpacity, actBlur, actBrightness:
        var v = a.val
        copyMem(addr base[i + 1], addr v, sizeof(float32))
        i += 5
      of actLuv:
        var b = a.brighthue
        var c = a.contrast
        var s = a.saturation
        copyMem(addr base[i + 1], addr b, sizeof(float32))
        copyMem(addr base[i + 5], addr c, sizeof(float32))
        copyMem(addr base[i + 9], addr s, sizeof(float32))
        i += 13
    Actions(cast[int](p))

  proc parseActions*(val: string): Actions =
    var list: seq[Action]
    for part in val.strip().split(","):
      let trimmedPart = part.strip()
      if trimmedPart == "nil":
        continue
      if trimmedPart == "cut":
        return aCut
      let a = parseAction(trimmedPart)
      if a.isNone:
        raise newException(ActionParseError, "Invalid action: " & trimmedPart)
      let action = a.unsafeGet
      if action.kind == actZoom and action.val <= 0.0:
        raise newException(ActionParseError, "zoom value must be greater than 0.0")
      if action.kind == actBrightness and
          (action.val < -1.0 or action.val > 1.0):
        raise newException(ActionParseError,
          "brightness must be in [-1.0, 1.0]")
      if action.kind == actLuv:
        if action.brighthue < -1.0 or action.brighthue > 1.0:
          raise newException(ActionParseError,
            "brighthue must be in [-1.0, 1.0]")
        if action.contrast < -2.0 or action.contrast > 2.0:
          raise newException(ActionParseError,
            "contrast must be in [-2.0, 2.0]")
        if action.saturation < 0.0 or action.saturation > 3.0:
          raise newException(ActionParseError,
            "saturation must be in [0.0, 3.0]")

        # Adjacent-fusion: collapse this actLuv into the previous one if it's
        # also actLuv. Per field, the non-identity value wins; later wins on
        # genuine conflicts.
        if list.len > 0 and list[^1].kind == actLuv:
          var prev = list[^1]
          if action.brighthue != luvBrighthueId: prev.brighthue = action.brighthue
          if action.contrast != luvContrastId: prev.contrast = action.contrast
          if action.saturation != luvSaturationId: prev.saturation = action.saturation
          list[^1] = prev
          continue
      list.add action

    # Drop any all-identity actLuv (no-op).
    var pruned: seq[Action]
    for a in list:
      if a.kind == actLuv and a.brighthue == luvBrighthueId and
          a.contrast == luvContrastId and a.saturation == luvSaturationId:
        continue
      pruned.add a
    return newActions(pruned)

  func `$`*(a: Actions): string =
    if a.isCut: return "cut"
    if a.isEmpty: return "nil"
    var parts: seq[string]
    for action in a: parts.add $action
    parts.join(",")
