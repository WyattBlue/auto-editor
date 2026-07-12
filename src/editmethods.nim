## Single source of truth for `--edit` methods and operators.
##
## `src/edit.nim` derives each method's positional argument order and which
## stream it analyzes from these defs; `docs/components/gen_edit.nims`
## renders the Edit Reference page from them. Keep this module dependency-light
## (std-only) so the docs generator can import it without pulling in ffmpeg.

type
  EditMedia* = enum
    emVideo, emAudio, emSubtitle

  EditParam* = object
    name*: string     ## positional argument name, e.g. "threshold"
    typ*: string      ## doc type, e.g. "(U Natural 'all)"
    default*: string  ## doc default; "" means the argument is required

  EditMethodDef* = object
    names*: seq[string]      ## canonical name first, then aliases (share parsing)
    media*: EditMedia        ## which stream the method analyzes
    params*: seq[EditParam]
    help*: string

  EditOperatorDef* = object
    name*: string
    variadic*: bool          ## true => `operand ...`
    help*: string

func p(name, typ: string, default = ""): EditParam =
  EditParam(name: name, typ: typ, default: default)

const editMethodDefs*: seq[EditMethodDef] = @[
  EditMethodDef(names: @["audio"], media: emAudio,
    params: @[p("threshold", "Unorm16", "0.04"),
              p("stream", "(U Natural 'all)", "all"),
              p("channel", "Symbol", "all")],
    help: "Do a one-pass audio filter based on the loudest sample in a " &
          "timebase section, divided by the max value a sample can be. " &
          "`channel` selects a named channel such as `left`, `right`, or " &
          "`center`; `all` analyzes every channel."),
  EditMethodDef(names: @["motion"], media: emVideo,
    params: @[p("threshold", "Unorm16", "0.02"),
              p("stream", "Natural", "0"),
              p("width", "Natural", "400"),
              p("blur", "Natural", "9"),
              p("x", "Float", "0"),
              p("y", "Float", "0"),
              p("w", "Float", "1"),
              p("h", "Float", "1")],
    help: "Scale the video to `width` pixels, convert to grayscale, apply a " &
          "Gaussian blur of `blur` amount, then compare the difference with " &
          "the previous frame. `x`, `y`, `w`, `h` restrict the analysis to a " &
          "region of the frame, as fractions [0-1] of its size."),
  EditMethodDef(names: @["blackdetect"], media: emVideo,
    params: @[p("threshold", "Unorm16", "0.98"),
              p("stream", "Natural", "0"),
              p("pixel-black", "Float", "0.10")],
    help: "Mark a frame as loud when at least `threshold` of its pixels are " &
          "black, where a pixel counts as black when its grayscale luma is at " &
          "or below `pixel-black`. Wrap in `not` to instead cut black frames."),
  EditMethodDef(names: @["subtitle", "regex"], media: emSubtitle,
    params: @[p("pattern", "String"),
              p("stream", "Natural", "0"),
              p("ignore-case", "Bool", "#f")],
    help: "When `pattern`, a RegEx expression, matches a subtitle line, " &
          "consider the time that line occupies as loud."),
  EditMethodDef(names: @["word"], media: emSubtitle,
    params: @[p("value", "String"),
              p("stream", "Natural", "0"),
              p("ignore-case", "Bool", "#t")],
    help: "When `value`, matched as a whole word, appears in a subtitle line, " &
          "consider the time that line occupies as loud. Case-insensitive by " &
          "default."),
]

const editOperatorDefs*: seq[EditOperatorDef] = @[
  EditOperatorDef(name: "or", variadic: true,
    help: "\"Logical Or\" two or more boolean arrays. If they are different " &
          "lengths, use the biggest one."),
  EditOperatorDef(name: "and", variadic: true,
    help: "\"Logical And\" two or more boolean arrays. If they are different " &
          "lengths, use the smallest one."),
  EditOperatorDef(name: "xor", variadic: true,
    help: "\"Logical Xor\" two or more boolean arrays."),
  EditOperatorDef(name: "not", variadic: false,
    help: "Invert a boolean array."),
]

func argOrderOf*(name: string): seq[string] =
  ## Positional argument names for the method whose canonical name or alias is
  ## `name`. Empty if no such method.
  for d in editMethodDefs:
    if name in d.names:
      for prm in d.params:
        result.add prm.name
      return

func editMediaOf*(name: string): set[EditMedia] =
  ## The stream(s) an edit method analyzes; empty for unknown names/operators.
  for d in editMethodDefs:
    if name in d.names:
      return {d.media}

func isEditOperator*(name: string): bool =
  for o in editOperatorDefs:
    if o.name == name:
      return true
