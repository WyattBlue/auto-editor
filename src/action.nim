import std/[options, strutils]

type
  ActionKind* = enum
    actSpeed, actVarispeed, actVolume, actInvert, actZoom, actHflip, actVflip,
    actOpacity

  # Represents a full-sized action.
  Action* = object
    case kind*: ActionKind
    of actInvert, actHflip, actVflip:
      discard
    of actSpeed, actVarispeed, actVolume, actZoom, actOpacity:
      val*: float32

  Actions* = distinct int # A fat pointer to a list of action in atf-8 format.

  # atf-8: store actions in as small a space as possible, inspirited by utf-8.

  ActionParseError* = object of CatchableError

  ActionDef* = object
    name*: string
    argSpec*: string  # e.g., "val: float"
    range*: string    # e.g., "(0-99999)"
    help*: string

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
  ActionDef(name: "zoom", argSpec: "val: float", range: "(0-100]",
    help: "Zoom in or out by a factor of val. 1.0 = no zoom."),
  ActionDef(name: "opacity", argSpec: "val: float", range: "[0.0-1.0]",
    help: "Blend the video section against the background. 1.0 = fully opaque, 0.0 = fully transparent."),
]

func `==`*(a, b: Action): bool =
  if a.kind != b.kind: return false
  case a.kind
  of actInvert, actHflip, actVflip: true
  of actSpeed, actVarispeed, actVolume, actZoom, actOpacity: a.val == b.val


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

  func actionByteSize(kind: ActionKind): int =
    case kind
    of actInvert, actHflip, actVflip: 1
    of actSpeed, actVarispeed, actVolume, actZoom, actOpacity: 5

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
        of actSpeed, actVarispeed, actVolume, actZoom, actOpacity:
          var v: float32
          copyMem(addr v, addr base[i + 1], sizeof(float32))
          yield Action(kind: kind, val: v)
          i += 5

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
      of actSpeed, actVarispeed, actVolume, actZoom, actOpacity:
        var v = a.val
        copyMem(addr base[i + 1], addr v, sizeof(float32))
        i += 5
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
      list.add action
    return newActions(list)

  func `$`*(a: Actions): string =
    if a.isCut: return "cut"
    if a.isEmpty: return "nil"
    var parts: seq[string]
    for action in a: parts.add $action
    parts.join(",")
