import std/strutils

type
  ActionKind* = enum
    actSpeed, actVarispeed, actVolume, actInvert, actZoom, actHflip, actVflip

  Action* = object
    case kind*: ActionKind
    of actInvert, actHflip, actVflip:
      discard
    of actSpeed, actVarispeed, actVolume, actZoom:
      val*: float32

  Actions* = distinct int # A fat pointer to a list of Action(s).

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
]

func `==`*(a, b: Action): bool =
  if a.kind != b.kind: return false
  case a.kind
  of actInvert, actHflip, actVflip: true
  of actSpeed, actVarispeed, actVolume, actZoom: a.val == b.val


const aNil* = Actions(0)
const aCut* = Actions(1)

func isCut*(a: Actions): bool = int(a) == 1
func isEmpty*(a: Actions): bool = int(a) == 0

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

  func len*(a: Actions): int =
    if int(a) <= 1: 0
    else: int(cast[ptr int32](int(a))[])

  func `[]`*(a: Actions, i: int): Action =
    let base = cast[ptr UncheckedArray[Action]](int(a) + sizeof(int32))
    base[i]

  iterator items*(a: Actions): Action =
    if int(a) > 1:
      let n = a.len
      let base = cast[ptr UncheckedArray[Action]](int(a) + sizeof(int32))
      for i in 0 ..< n:
        yield base[i]

  func `==`*(a, b: Actions): bool =
    let ia = int(a)
    let ib = int(b)
    if ia == ib: return true
    if ia <= 1 or ib <= 1: return false
    let n = a.len
    if n != b.len: return false
    let pa = cast[ptr UncheckedArray[Action]](ia + sizeof(int32))
    let pb = cast[ptr UncheckedArray[Action]](ib + sizeof(int32))
    for i in 0 ..< n:
      if pa[i] != pb[i]: return false
    true

  proc newActions*(list: openArray[Action]): Actions =
    if list.len == 0: return aNil
    let p = alloc(sizeof(int32) + list.len * sizeof(Action))
    cast[ptr int32](p)[] = int32(list.len)
    let base = cast[ptr UncheckedArray[Action]](cast[int](p) + sizeof(int32))
    for i, a in list: base[i] = a
    Actions(cast[int](p))

  func `$`*(a: Actions): string =
    if a.isCut: return "cut"
    if a.isEmpty: return "nil"
    var parts: seq[string]
    for action in a: parts.add $action
    parts.join(",")
