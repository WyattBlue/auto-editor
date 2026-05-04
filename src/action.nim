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

func `$`*(act: Action): string =
  case act.kind
  of actInvert: "invert"
  of actHflip: "hflip"
  of actVflip: "vflip"
  of actSpeed: "speed:" & $act.val
  of actVarispeed: "varispeed:" & $act.val
  of actVolume: "volume:" & $act.val
  of actZoom: "zoom:" & $act.val

func `==`*(a, b: Action): bool =
  if a.kind != b.kind: return false
  case a.kind
  of actInvert, actHflip, actVflip: true
  of actSpeed, actVarispeed, actVolume, actZoom: a.val == b.val


const aNil* = Actions(0)
const aCut* = Actions(1)

func isCut*(a: Actions): bool = int(a) == 1
func isEmpty*(a: Actions): bool = int(a) == 0

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
