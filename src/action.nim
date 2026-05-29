import std/strutils
import ./util/dnorm16

type
  ActionKind* = enum
    actSpeed, actVarispeed, actVolume, actDeesser, actInvert, actZoom, actHflip,
    actVflip, actOpacity, actBlur, actBrightness, actLuv, actLens

  # Represents a full-sized action.
  Action* = object
    case kind*: ActionKind
    of actInvert, actHflip, actVflip:
      discard
    of actOpacity:
      nval*: Unorm16
    of actBrightness:
      sval*: Snorm16
    of actLens:
      k1*, k2*: Snorm16
    of actSpeed, actVarispeed, actVolume, actZoom, actBlur:
      val*: float32
    of actDeesser:
      intensity*, maxd*, freq*: Unorm16
    of actLuv:
      contrast*: float32
      saturation*: float32
      brighthue*: Snorm16

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
  ActionDef(name: "deesser", argSpec: "intensity[:max[:freq]]", range: "each [0.0, 1.0]",
    help: """
Reduce harsh "s" and "sh" sibilance in the audio section. Implemented via FFmpeg's `deesser` filter.
Positional args: `intensity` controls how much to de-ess (0.0 = none, 1.0 = maximum), `max` caps the maximum reduction (default 0.5), and `freq` sets the split frequency (default 0.5). `max` and `freq` are optional."""),
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
  ActionDef(name: "lens", argSpec: "k1[:k2]", range: "each [-1.0, 1.0]",
    help: """
Apply lens distortion correction. Implemented via FFmpeg's `lenscorrection` filter.
Positional args: `k1` is the quadratic correction factor and `k2` is the double quadratic factor. Negative values bulge the image outward (fisheye); positive values pinch it inward (pincushion). With no arguments, a fun fisheye lens is applied."""),
]

const aNil* = Actions(0)
const aCut* = Actions(1)

func isCut*(a: Actions): bool = int(a) == 1
func isEmpty*(a: Actions): bool = int(a) == 0

const
  luvBrighthueId* = toSnorm16(0.0'f32)
  luvContrastId* = 1.0'f32
  luvSaturationId* = 1.0'f32

func parseAction*(val: string): Action {.raises: [ActionParseError].} =
  if val == "invert":
    return Action(kind: actInvert)
  if val == "hflip":
    return Action(kind: actHflip)
  if val == "vflip":
    return Action(kind: actVflip)

  let parts = val.split(":")

  # deesser takes positional args: intensity[:max[:freq]]
  if parts.len >= 2 and parts.len <= 4 and parts[0] == "deesser":
    var vals = [toUnorm16(0.0), halfUnorm16, halfUnorm16]
    for idx in 1 ..< parts.len:
      vals[idx - 1] = (
        try:
          toUnorm16(parseFloat(parts[idx]).float32)
        except ValueError:
          raise newException(ActionParseError, "Invalid float value")
      )
    return Action(kind: actDeesser,
      intensity: vals[0], maxd: vals[1], freq: vals[2]
    )

  # lens takes positional args: [k1[:k2]]
  if parts[0] == "lens" and parts.len <= 3:
    if parts.len == 1:
      # A fun fisheye bulge, used when `lens` is given with no arguments.
      return Action(kind: actLens, k1: toSnorm16(-0.5'f32), k2: toSnorm16(0.0'f32))
    var k = [0.0'f32, 0.0'f32]
    for idx in 1 ..< parts.len:
      k[idx - 1] = (
        try:
          parseFloat(parts[idx]).float32
        except ValueError:
          raise newException(ActionParseError, "Invalid float value")
      )
    for v in k:
      if v < -1.0 or v > 1.0:
        raise newException(ActionParseError, "lens factors must be in [-1.0, 1.0]")
    return Action(kind: actLens, k1: toSnorm16(k[0]), k2: toSnorm16(k[1]))

  if parts.len == 2:
    let effectType = parts[0]
    let effectVal = (
      try:
        parseFloat(parts[1]).float32
      except ValueError:
        raise newException(ActionParseError, "Invalid float value")
    )
    case effectType
    of "speed": return Action(kind: actSpeed, val: effectVal)
    of "volume": return Action(kind: actVolume, val: effectVal)
    of "varispeed": return Action(kind: actVarispeed, val: effectVal)
    of "zoom":
      if effectVal <= 0.0:
        raise newException(ActionParseError, "zoom value must be greater than 0.0")
      return Action(kind: actZoom, val: effectVal)
    of "opacity":
      if effectVal > 1.0 or effectVal < 0.0:
        raise newException(ActionParseError, "opacity must be in [0.0, 1.0]")
      return Action(kind: actOpacity, nval: toUnorm16(effectVal))
    of "blur": return Action(kind: actBlur, val: effectVal)
    of "brightness":
      if effectVal > 1.0 or effectVal < -1.0:
        raise newException(ActionParseError, "brightness must be in [-1.0, 1.0]")
      return Action(kind: actBrightness, sval: toSnorm16(effectVal))
    of "brighthue":
      return Action(kind: actLuv, brighthue: effectVal,
        contrast: luvContrastId, saturation: luvSaturationId)
    of "contrast":
      if effectVal < -2.0 or effectVal > 2.0:
        raise newException(ActionParseError, "contrast must be in [-2.0, 2.0]")
      return Action(kind: actLuv, brighthue: luvBrighthueId,
        contrast: effectVal, saturation: luvSaturationId)
    of "saturation":
      if effectVal < 0.0 or effectVal > 3.0:
        raise newException(ActionParseError, "saturation must be in [0.0, 3.0]")
      return Action(kind: actLuv, brighthue: luvBrighthueId,
        contrast: luvContrastId, saturation: effectVal)
    else: discard

  raise newException(ActionParseError, "Unknown action: " & val)

when not defined(nimscript):
  func `$`*(act: Action): string =
    case act.kind
    of actInvert: "invert"
    of actHflip: "hflip"
    of actVflip: "vflip"
    of actSpeed: "speed:" & $act.val
    of actVarispeed: "varispeed:" & $act.val
    of actVolume: "volume:" & $act.val
    of actDeesser:
      let i = act.intensity
      let m = act.maxd
      let f = act.freq
      "deesser:" & $i & ":" & $m & ":" & $f
    of actZoom: "zoom:" & $act.val
    of actOpacity: "opacity:" & $act.nval
    of actBlur: "blur:" & $act.val
    of actBrightness: "brightness:" & $act.sval
    of actLuv:
      var parts: seq[string]
      if act.brighthue != luvBrighthueId: parts.add "brighthue:" & $act.brighthue
      if act.contrast != luvContrastId: parts.add "contrast:" & $act.contrast
      if act.saturation != luvSaturationId: parts.add "saturation:" & $act.saturation
      if parts.len == 0: "brighthue:0.0" else: parts.join(",")
    of actLens: "lens:" & $act.k1 & ":" & $act.k2

  func actionByteSize(kind: ActionKind): int =
    case kind
    of actInvert, actHflip, actVflip: 1
    of actOpacity, actBrightness: 3
    of actSpeed, actVarispeed, actVolume, actZoom, actBlur, actLens: 5
    of actDeesser: 7
    of actLuv: 11

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
        of actSpeed, actVarispeed, actVolume, actZoom, actBlur:
          var v: float32
          copyMem(addr v, addr base[i + 1], sizeof(float32))
          yield Action(kind: kind, val: v)
          i += 5
        of actOpacity:
          var u: Unorm16
          copyMem(addr u, addr base[i + 1], sizeof(Unorm16))
          yield Action(kind: actOpacity, nval: u)
          i += 3
        of actBrightness:
          var sv: Snorm16
          copyMem(addr sv, addr base[i + 1], sizeof(Snorm16))
          yield Action(kind: actBrightness, sval: sv)
          i += 3
        of actDeesser:
          var iu, mu, fu: Unorm16
          copyMem(addr iu, addr base[i + 1], sizeof(Unorm16))
          copyMem(addr mu, addr base[i + 3], sizeof(Unorm16))
          copyMem(addr fu, addr base[i + 5], sizeof(Unorm16))
          yield Action(kind: actDeesser, intensity: iu, maxd: mu, freq: fu)
          i += 7
        of actLuv:
          var bh: Snorm16
          var c, s: float32
          copyMem(addr bh, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr c, addr base[i + 3], sizeof(float32))
          copyMem(addr s, addr base[i + 7], sizeof(float32))
          yield Action(kind: actLuv, brighthue: bh, contrast: c, saturation: s)
          i += 11
        of actLens:
          var k1v, k2v: Snorm16
          copyMem(addr k1v, addr base[i + 1], sizeof(Snorm16))
          copyMem(addr k2v, addr base[i + 3], sizeof(Snorm16))
          yield Action(kind: actLens, k1: k1v, k2: k2v)
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
      of actSpeed, actVarispeed, actVolume, actZoom, actBlur:
        var v = a.val
        copyMem(addr base[i + 1], addr v, sizeof(float32))
        i += 5
      of actOpacity:
        var u = a.nval
        copyMem(addr base[i + 1], addr u, sizeof(Unorm16))
        i += 3
      of actBrightness:
        var sv = a.sval
        copyMem(addr base[i + 1], addr sv, sizeof(Snorm16))
        i += 3
      of actDeesser:
        var iu = a.intensity
        var mu = a.maxd
        var fu = a.freq
        copyMem(addr base[i + 1], addr iu, sizeof(Unorm16))
        copyMem(addr base[i + 3], addr mu, sizeof(Unorm16))
        copyMem(addr base[i + 5], addr fu, sizeof(Unorm16))
        i += 7
      of actLuv:
        var bh = toSnorm16(a.brighthue)
        var c = a.contrast
        var s = a.saturation
        copyMem(addr base[i + 1], addr bh, sizeof(Snorm16))
        copyMem(addr base[i + 3], addr c, sizeof(float32))
        copyMem(addr base[i + 7], addr s, sizeof(float32))
        i += 11
      of actLens:
        var k1v = a.k1
        var k2v = a.k2
        copyMem(addr base[i + 1], addr k1v, sizeof(Snorm16))
        copyMem(addr base[i + 3], addr k2v, sizeof(Snorm16))
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
      let action = parseAction(trimmedPart)
      if action.kind == actLuv:
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
