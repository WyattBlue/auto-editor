## A parsed `--edit` expression: which methods mark frames active, and how
## their results combine. `edit.parseEdit` builds one from the CLI's syntax;
## a program using auto-editor as a library can build one directly.

import ./lib/dnorm16

type
  EditMethodKind* = enum
    ekAudio, ekMotion, ekBlackdetect,
    ekSubtitle ## a regex over subtitle lines (`subtitle`, `regex`)
    ekWord     ## a whole word in subtitle lines
    ekNone     ## every frame active
    ekAll      ## no frame active

  EditMethod* = object
    threshold*: Unorm16 ## audio, motion, blackdetect
    stream*: int        ## -1 is every audio stream (audio only)
    case kind*: EditMethodKind
    of ekAudio:
      channel*: string ## a channel name such as "left", or "all"
    of ekMotion:
      width*, blur*: int
      region*: tuple[x, y, w, h: float32] ## fractions of the frame
    of ekBlackdetect:
      pixelBlack*: float32
    of ekSubtitle, ekWord:
      pattern*: string ## the regex, or the word as written
      ignoreCase*: bool
    of ekNone, ekAll:
      discard

  EditOp* = enum
    eoMethod, eoOr, eoAnd, eoXor, eoNot

  EditExpr* = object
    case op*: EditOp
    of eoMethod:
      m*: EditMethod
    of eoOr, eoAnd, eoXor, eoNot:
      operands*: seq[EditExpr] ## `not` has exactly one

func audioMethod*(threshold = 0.04'f32, stream = -1, channel = "all"): EditMethod =
  EditMethod(kind: ekAudio, threshold: threshold, stream: stream, channel: channel)

func motionMethod*(threshold = 0.02'f32, stream = 0, width = 400, blur = 9,
    region = (x: 0'f32, y: 0'f32, w: 1'f32, h: 1'f32)): EditMethod =
  EditMethod(kind: ekMotion, threshold: threshold, stream: stream, width: width,
    blur: blur, region: region)

func blackdetectMethod*(threshold = 0.98'f32, stream = 0, pixelBlack = 0.10'f32): EditMethod =
  EditMethod(kind: ekBlackdetect, threshold: threshold, stream: stream,
    pixelBlack: pixelBlack)

func subtitleMethod*(pattern: string, stream = 0, ignoreCase = false): EditMethod =
  EditMethod(kind: ekSubtitle, pattern: pattern, stream: stream, ignoreCase: ignoreCase)

func wordMethod*(word: string, stream = 0, ignoreCase = true): EditMethod =
  EditMethod(kind: ekWord, pattern: word, stream: stream, ignoreCase: ignoreCase)

func noneMethod*(): EditMethod = EditMethod(kind: ekNone)
func allMethod*(): EditMethod = EditMethod(kind: ekAll)

func edit*(m: EditMethod): EditExpr = EditExpr(op: eoMethod, m: m)

func combine*(op: EditOp, operands: varargs[EditExpr]): EditExpr =
  ## `or`, `and` or `xor` over one or more operands.
  assert op in {eoOr, eoAnd, eoXor} and operands.len > 0
  result = EditExpr(op: op)
  result.operands = @operands

func invert*(e: EditExpr): EditExpr = EditExpr(op: eoNot, operands: @[e])

func needs*(e: EditExpr): tuple[video, audio: bool] =
  ## Whether evaluating `e` analyzes video and/or audio frames. Subtitle
  ## methods read the subtitle stream, so they need neither.
  case e.op
  of eoMethod:
    result = case e.m.kind
      of ekAudio: (false, true)
      of ekMotion, ekBlackdetect: (true, false)
      else: (false, false)
  of eoOr, eoAnd, eoXor, eoNot:
    for o in e.operands:
      let n = o.needs
      result = (result.video or n.video, result.audio or n.audio)
