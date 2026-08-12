import std/[macros, strformat, strutils]
import ./util/suggest

type Categories* = enum
  cNone cEdit cTl cUrl cDis cCon cVid cAud cMis

func categoryName*(c: Categories): string =
  case c
  of cNone: ""
  of cEdit: "Editing Options"
  of cTl: "Timeline Options"
  of cUrl: "URL Download Options"
  of cDis: "Display Options"
  of cCon: "Container Settings"
  of cVid: "Video Rendering"
  of cAud: "Audio Rendering"
  of cMis: "Miscellaneous"

type Link = object
  href*: string
  a*: string

func `$`(link: Link): string =
  when defined(nimscript): &"<a href=\"{link.href}\">{link.a}</a>"
  else: &"\e]8;;{link.href}\e\\{link.a}\e]8;;\e\\"

const fragmented = Link(href: "https://ffmpeg.org/ffmpeg-formats.html#Fragmentation",
    a: "fragmented")
const ytDlp = Link(href: "https://github.com/yt-dlp/yt-dlp", a: "yt-dlp")
const actionsRef = Link(href: "https://auto-editor.com/ref/actions",
    a: "actions reference")

type OptKind* = enum
  Regular # expecting = $datum
  Flag    # $datum = true
  Special # args.`export` = parseExportString("$datum")

type CliOption* = enum
  coNone, coIsDebug, coSplitWords, coLanguage, coFormat, coOutput, coTranslate, coQueue,
    coPrompt, coThreads, coThreshold, coIsJson, coEncoders, coDecoders, coCodecs, coEdit,
    coTimebase, coDisplay, coNoCache, coAsJson, coStream, coChannel, coSamplesPerBucket,
    coStartSample, coLengthSamples, coShell, coWhenActive, coWhenInactive, coMargin,
    coSmooth, coTransition, coCutOut, coAddIn, coSetSpeed, coSetAction, coSilentSpeed,
    coVideoSpeed, coPremiere, coResolve, coFinalCutPro, coShotcut, coKdenlive, coExport,
    coFrameRate, coSampleRate, coResolution, coBackground, coYtDlpLocation,
    coOutputFormat, coYtDlpExtras, coProgress, coQuiet, coPreview, coVn, coAn, coSn,
    coDn, coFaststart, coNoFaststart, coFragmented, coNoFragmented, coVcodec,
    coVideoBitrate, coCrf, coGop, coVprofile, coPreset, coPixFmt, coScale, coNoSeek,
    coNoPartialLossless, coAcodec, coLayout, coAudioBitrate, coMixAudioStreams,
    coAudioNormalize, coOpen, coNoOpen, coKey, coShowVersion, coWebCodecs, coWhen

type OptDef* = object
  names*: string
  kind*: OptKind = Regular
  c*: Categories = cNone
  datum*: CliOption
  metavar*: string # Shouldn't be set for flags.
  help*: string
  hidden*: bool

func argumentOptions(options: seq[OptDef]): set[CliOption] {.compileTime.} =
  for opt in options:
    if opt.kind == Regular:
      result.incl opt.datum

template assertArgumentOptions*(options, expected: untyped) =
  static:
    doAssert argumentOptions(options) == expected

template assertArgumentOptions*(options, expected, extra: untyped) =
  static:
    doAssert argumentOptions(options) + extra == expected

func cliOptionName(opt: CliOption): string {.compileTime.} =
  let name = system.`$`(opt)
  doAssert name.startsWith("co"), "Invalid CLI option name: " & name
  name[2 .. ^1]

func cliOptionLabel(opt: CliOption): string {.compileTime.} =
  if opt == coPixFmt:
    return "pix_fmt"
  let name = cliOptionName(opt)
  for i, c in name:
    if c.isUpperAscii:
      if i > 0:
        result.add '-'
      result.add c.toLowerAscii
    else:
      result.add c

macro genCliOptionToString(options: static seq[OptDef]): untyped =
  var flags: set[CliOption]
  for option in options:
    if option.kind == Flag:
      flags.incl option.datum

  var caseStmt = newTree(nnkCaseStmt, ident("opt"))
  for opt in CliOption:
    let label = if opt == coNone or opt in flags: "" else: cliOptionLabel(opt)
    caseStmt.add newTree(nnkOfBranch, ident(system.`$`(opt)),
      newStmtList(newLit(label)))

  result = caseStmt

const whisperOptions*: seq[OptDef] = @[
  OptDef(names: "--debug", kind: Flag, datum: coIsDebug,
    help: "Show debugging messages and values"),
  OptDef(names: "-sw, --split-word, --split-words", kind: Flag, datum: coSplitWords,
    help: "Output one word per cue instead of full segments"),
  OptDef(names: "-l, --language", datum: coLanguage, metavar: "LANG",
    help: "Set the language instead of using \"auto\". Examples: en, ja"),
  OptDef(names: "-f, --format", datum: coFormat, metavar: "FORMAT",
    help: "Output in a specific format {text|srt|json} (default text)"),
  OptDef(names: "-o, --output", datum: coOutput, metavar: "FILE",
    help: "Choose where to output (defaults to stdout)"),
  OptDef(names: "-tr, --translate", kind: Flag, datum: coTranslate,
    help: "Translate from source language to english"),
  OptDef(names: "--queue", datum: coQueue, metavar: "SECS",
    help: "The maximum size in seconds of a single transcribed segment (default 30)"),
  OptDef(names: "--prompt", datum: coPrompt, metavar: "TEXT",
    help: "Bias transcription toward given vocabulary/spelling (e.g. names, jargon)"),
  OptDef(names: "--threads", datum: coThreads, metavar: "N",
    help: "Number of CPU threads for whisper processing (default 4)"),
  OptDef(names: "-t, --threshold", datum: coThreshold, metavar: "THRES",
    help: "The loudness (0-1) below which audio is treated as silence and " &
          "skipped, like the audio edit method (default 0.04)"),
]

const infoOptions*: seq[OptDef] = @[
  OptDef(names: "--json", kind: Flag, datum: coIsJson,
    help: "Print the information as JSON"),
  OptDef(names: "-encoders", datum: coEncoders, metavar: "EXT",
    help: "Show all usable encoders for a given container extension"),
  OptDef(names: "-decoders", datum: coDecoders, metavar: "EXT",
    help: "Show all usable decoders for a given container extension"),
  OptDef(names: "-codecs", datum: coCodecs, metavar: "EXT",
    help: "Show all usable codecs for a given container extension"),
]

const descOptions*: seq[OptDef] = @[]

const cacheOptions*: seq[OptDef] = @[]

const levelsOptions*: seq[OptDef] = @[
  OptDef(names: "--edit", datum: coEdit, metavar: "METHOD",
    help: "Set the kind of detection to analyze with (default audio)"),
  OptDef(names: "-tb, --timebase", datum: coTimebase, metavar: "NUM",
    help: "Set the timebase/chunk rate to analyze at (default 30)"),
  OptDef(names: "--display", datum: coDisplay, metavar: "FORMAT",
    help: "Set the output format {float|d16} (default float)"),
  OptDef(names: "--no-cache", kind: Flag, datum: coNoCache,
    help: "Disable reading and writing cache files"),
]

const subdumpOptions*: seq[OptDef] = @[
  OptDef(names: "--json", kind: Flag, datum: coAsJson,
    help: "Print the subtitles as JSON"),
]

const waveformOptions*: seq[OptDef] = @[
  OptDef(names: "--stream", datum: coStream, metavar: "NAT",
    help: "Set which audio stream to analyze (default 0)"),
  OptDef(names: "--channel", datum: coChannel, metavar: "NAME",
    help: "Set one or more comma-separated audio channels to draw"),
  OptDef(names: "--samples-per-bucket", datum: coSamplesPerBucket, metavar: "NAT",
    help: "Number of audio samples per drawn bucket (default 256)"),
  OptDef(names: "--start-sample", datum: coStartSample, metavar: "NAT",
    help: "First audio sample to analyze from (default 0)"),
  OptDef(names: "--length-samples", datum: coLengthSamples, metavar: "INT",
    help: "Number of samples to analyze, -1 for all (default -1)"),
  OptDef(names: "--display", datum: coDisplay, metavar: "FORMAT",
    help: "Set the output format {float|d16} (default float)"),
  OptDef(names: "--no-cache", kind: Flag, datum: coNoCache,
    help: "Disable reading and writing cache files"),
]

const completionOptions*: seq[OptDef] = @[
  OptDef(names: "-s, --shell", datum: coShell, metavar: "SHELL",
    help: "Shell type: {zsh}"),
]

const mainOptions*: seq[OptDef] = @[
  OptDef(names: "-e, --edit", c: cEdit, datum: coEdit, metavar: "METHOD",
      help: """
Set an expression which determines how to make auto edits. (default is "audio")"""),
  OptDef(names: "-w:1, --when-normal, --when-active", c: cEdit, datum: coWhenActive,
    metavar: "ACTION",
    help: "When a segment is active (defined by --edit) do an action. The default action being 'nil'"),
  OptDef(names: "-w:0, --when-silent, --when-inactive", c: cEdit, datum: coWhenInactive,
      metavar: "ACTION", help: &"""
When a segment is inactive (defined by --edit) do an action. The default action being 'cut'. See the {actionsRef} for all available actions."""),
  OptDef(names: "-m, --margin", c: cEdit, datum: coMargin, metavar: "LENGTH[,LENGTH?]",
      help: """
Set sections near "loud" as "loud" too if section is less than LENGTH away. (default is "0.2s")"""),
  OptDef(names: "-s, --smooth", c: cEdit, datum: coSmooth, metavar: "MINCUT[,MINCLIP?]",
      help: """
Make sections 'smoother' by applying minimum cut and minimum clip rules. (default is 0.2s,0.1s)
Examples:
  --smooth 0.2s,0.1s  # Set mincut to 0.2 seconds, minclip to 0.1 seconds.
  --smooth 0  # Turn off smoothing"""),
  OptDef(names: "--transition", c: cEdit, datum: coTransition,
    metavar: "dissolve:DURATION[:MIN-CUT]", help: """
Add linked video/audio cross-dissolves at cuts and fades at the timeline ends.
Skip cuts whose removed source interval is shorter than MIN-CUT (default 1sec)."""),
  OptDef(names: "-o, --output", c: cEdit, datum: coOutput,
    metavar: "FILE", help: "Set the name/path of the new output file"),
  OptDef(names: "--cut-out, --cut", c: cEdit, datum: coCutOut,
    metavar: "[START,STOP ...]", help: "Set segment(s) that will be cut/removed"),
  OptDef(names: "--add-in, --keep", c: cEdit, datum: coAddIn,
    metavar: "[START,STOP ...]", help: "Set segment(s) that are leaved \"as is\", overriding other actions"),
  OptDef(names: "--set-speed, --set-speed-for-range", c: cEdit, datum: coSetSpeed,
    metavar: "[SPEED,START,STOP ...]", help: "Set segment(s) to a SPEED, overriding other actions"),
  OptDef(names: "--set-action", c: cEdit, datum: coSetAction,
    metavar: "ACTION,start,end",
    help: """Set a time segment to an ACTION, overriding other actions
Examples:
  --set-action nil,0,5sec
  --set-action speed:1.5,varispeed:1.5,30sec,end"""),
  OptDef(names: "--silent-speed", c: cEdit, datum: coSilentSpeed, metavar: "NUM",
    hidden: true,
    help: "[Deprecated] Set speed of inactive segments to NUM. (default is 99999)"),
  OptDef(names: "--video-speed", c: cEdit, datum: coVideoSpeed, metavar: "NUM",
    hidden: true,
    help: "[Deprecated] Set speed of active segments to NUM. (default is 1)"),

  OptDef(names: "-exp, --export-to-premiere", kind: Special, datum: coPremiere,
      hidden: true),
  OptDef(names: "-exr, --export-to-resolve", kind: Special, datum: coResolve,
      hidden: true),
  OptDef(names: "-exf, --export-to-final-cut-pro", kind: Special, datum: coFinalCutPro,
      hidden: true),
  OptDef(names: "-exs, --export-to-shotcut", kind: Special, datum: coShotcut,
      hidden: true),
  OptDef(names: "-exk, --export-to-kdenlive", kind: Special, datum: coKdenlive,
      hidden: true),

  OptDef(names: "-ex, --export", c: cTl, datum: coExport,
    metavar: "EXPORT:ATTRS?", help: "Choose the export mode"),
  OptDef(names: "-tb, --time-base, -r, -fps, --frame-rate", c: cTl, datum: coFrameRate,
    metavar: "NUM", help: "Set timeline frame rate"),
  OptDef(names: "-ar, --sample-rate", c: cTl, datum: coSampleRate, metavar: "NAT",
    help: "Set timeline sample rate"),
  OptDef(names: "-res, --resolution", c: cTl, datum: coResolution,
    metavar: "WIDTH,HEIGHT", help: "Set timeline width and height"),
  OptDef(names: "-b, -bg, --background", c: cTl, datum: coBackground, metavar: "COLOR",
    help: "Set the background as a solid RGB color"),

  OptDef(names: "--yt-dlp-location", c: cUrl, datum: coYtDlpLocation, metavar: "PATH",
    help: &"Set a custom path to {ytDlp}"),
  OptDef(names: "--output-format", c: cUrl, datum: coOutputFormat, metavar: "TEMPLATE",
    help: "Set the yt-dlp output file template (--output, -o)"),
  OptDef(names: "--yt-dlp-extras", c: cUrl, datum: coYtDlpExtras, metavar: "CMD",
    help: "Add extra options for yt-dlp. Must be in quotes"),

  OptDef(names: "--progress", c: cDis, datum: coProgress, metavar: "PROGRESS",
    help: "Set what type of progress bar to use"),
  OptDef(names: "--debug", c: cDis, kind: Flag, datum: coIsDebug,
    help: "Show debugging messages and values"),
  OptDef(names: "-q, --quiet", c: cDis, kind: Flag, datum: coQuiet,
    help: "Display less output"),
  OptDef(names: "--preview, --stats", c: cDis, kind: Flag, datum: coPreview,
    help: "Show stats on how the input will be cut and halt"),

  OptDef(names: "-vn", c: cCon, kind: Flag, datum: coVn,
    help: "Disable the inclusion of video streams"),
  OptDef(names: "-an", c: cCon, kind: Flag, datum: coAn,
    help: "Disable the inclusion of audio streams"),
  OptDef(names: "-sn", c: cCon, kind: Flag, datum: coSn,
    help: "Disable the inclusion of subtitle streams"),
  OptDef(names: "-dn", c: cCon, kind: Flag, datum: coDn,
    help: "Disable the inclusion of data streams"),
  OptDef(names: "--faststart", c: cCon, kind: Flag, datum: coFaststart,
    help: "Enable movflags +faststart, recommended for web (default)"),
  OptDef(names: "--no-faststart", c: cCon, kind: Flag, datum: coNoFaststart,
    help: "Disable movflags +faststart, will be faster for large files"),
  OptDef(names: "--fragmented", c: cCon, kind: Flag, datum: coFragmented,
    help: &"Use {fragmented} mp4/mov to allow playback before video is complete."),
  OptDef(names: "--no-fragmented", c: cCon, kind: Flag, datum: coNoFragmented,
    help: "Do not use fragmented mp4/mov for better compatibility (default)"),

  OptDef(names: "-c:v, -vcodec, --video-codec", c: cVid, datum: coVcodec,
    metavar: "ENCODER", help: "Set video codec for output media"),
  OptDef(names: "-b:v, --video-bitrate", c: cVid, datum: coVideoBitrate,
    metavar: "BITRATE", help: "Set the number of bits per second for video"),
  OptDef(names: "-crf", c: cVid, datum: coCrf, metavar: "NUM",
    help: "Set the Constant Rate Factor for quality-based encoding. Lower = better quality. [0-63]"),
  OptDef(names: "-g, --gop", c: cVid, datum: coGop, metavar: "NUM",
    help: "Set the maximum number of frames between keyframes. Shorter = lower latency and larger files"),
  OptDef(names: "-profile:v, -vprofile", c: cVid, datum: coVprofile,
    metavar: "PROFILE", help: "Set the video profile. For h264: high, main, or baseline"),
  OptDef(names: "-preset, --preset", c: cVid, datum: coPreset, metavar: "PRESET",
    help: "Set the video encoder's preset (e.g. ultrafast, medium, slow)"),
  OptDef(names: "-pix_fmt, --pix-fmt", c: cVid, datum: coPixFmt, metavar: "FMT",
    help: "Set the output pixel format (e.g. yuv420p, yuv420p10le)"),
  OptDef(names: "--scale", c: cVid, datum: coScale, metavar: "NUM",
    help: "Scale the output video's resolution by NUM factor"),
  OptDef(names: "--no-seek", c: cVid, kind: Flag, datum: coNoSeek,
    help: "Disable file seeking when rendering video. Helpful for debugging desync issues"),
  OptDef(names: "--no-partial-lossless", c: cVid, kind: Flag,
    datum: coNoPartialLossless,
    help: "Disable copying complete GOPs and re-encode the entire video"),

  OptDef(names: "-c:a, -acodec, --audio-codec", c: cAud, datum: coAcodec,
    metavar: "ENCODER", help: "Set audio codec for output media"),
  OptDef(names: "-layout, --audio-layout", c: cAud, datum: coLayout,
    metavar: "LAYOUT", help: "Set the audio layout for the output media/timeline"),
  OptDef(names: "-b:a, --audio-bitrate", c: cAud, datum: coAudioBitrate,
    metavar: "BITRATE", help: "Set the number of bits per second for audio"),
  OptDef(names: "--mix-audio-streams", c: cAud, kind: Flag, datum: coMixAudioStreams,
    help: "Mix all audio streams together into one"),
  OptDef(names: "-anorm, --audio-normalize", c: cAud, datum: coAudioNormalize,
    metavar: "NORM-TYPE", help: """
Apply audio normalizing (either ebu or peak). Applied right before rendering the output file"""),

  OptDef(names: "--no-cache", c: cMis, kind: Flag, datum: coNoCache,
    help: "Disable reading and writing cache files"),
] & (
  when defined(emscripten): @[
    OptDef(names: "--webcodecs", c: cMis, kind: Flag, datum: coWebCodecs,
      help: "Use browser WebCodecs decoders"),
  ] else: @[]
) & @[
  OptDef(names: "--open", c: cMis, kind: Flag, datum: coOpen,
    help: "Open the output file after editing is done"),
  OptDef(names: "--no-open", c: cMis, kind: Flag, datum: coNoOpen,
    help: "Do not open the output file after editing is done (default)"),
  OptDef(names: "-k, --license-key", c: cMis, datum: coKey,
    help: "Provide a license key, which activates certain features"),
  OptDef(names: "-V, -v, --version", c: cMis, kind: Flag, datum: coShowVersion,
    help: "Show info about this program or option"),
]

const cliOptions =
  whisperOptions & infoOptions & levelsOptions & subdumpOptions &
    waveformOptions & completionOptions & mainOptions

func `$`*(opt: CliOption): string {.raises: [].} =
  genCliOptionToString(cliOptions)

type CmdDef* = object
  name*: string
  handler*: string
  help*: string
  opts*: seq[OptDef]
  files*: bool = true # Whether shell completion should offer filenames.
  requiresArgs*: bool = true
  shellCompletion*: bool = true

const commands*: seq[CmdDef] = @[
  CmdDef(name: "cache", help: "", opts: cacheOptions, files: false),
  CmdDef(name: "desc", help: "Display a media file's description metadata",
      opts: descOptions),
  CmdDef(name: "info", help: "Retrieve information and properties about media files\nUsage: <file> [options] | -encoders <ext> | -decoders <ext>",
      opts: infoOptions),
  CmdDef(name: "levels", help: "Display loudness over time", opts: levelsOptions),
  CmdDef(name: "subdump", help: "Dump text-based subtitles to stdout with formatting stripped out",
      opts: subdumpOptions),
  CmdDef(name: "waveform", help: "Draw waveforms for GUI. Unstable interface",
      opts: waveformOptions, shellCompletion: false),
  CmdDef(name: "whisper", help: "Transcribe audio with ggml models\nUsage: <file> <model> [options]",
      opts: whisperOptions),
] & (
  when defined(emscripten): @[] else: @[
    CmdDef(name: "completion", help: "Generate completions for shells",
        opts: completionOptions, files: false),
    CmdDef(name: "preview-worker", handler: "preview_worker",
      help: "Run the resident preview rendering worker", opts: @[], files: false,
      requiresArgs: false, shellCompletion: false),
  ]
)

func optionNames*(opts: seq[OptDef]): seq[string] =
  for opt in opts:
    for name in opt.names.split(", "):
      result.add name.strip()

func optionDidYouMean*(key: string, opts: seq[OptDef]): string =
  didYouMean(key, optionNames(opts))

proc writeZshOptions(name: string, opts: seq[OptDef]) =
  echo "  " & name & "=("
  for opt in opts:
    if opt.hidden:
      continue
    let desc =
      if opt.help != "":
        opt.help.split('\n')[0].replace("'", "'\\''").replace(":", "\\:")
      else: ""
    for name in opt.names.split(", "):
      let n = name.strip().replace(":", "\\:")
      if desc != "":
        echo "    '" & n & ":" & desc & "'"
      else:
        echo "    '" & n & "'"
  echo "  )"

proc zshcomplete*() =
  var locals = @["subcommands", "options"]
  for cmd in commands:
    if not cmd.shellCompletion:
      continue
    locals.add cmd.name & "_options"

  echo "#compdef auto-editor"
  echo ""
  echo "_auto-editor() {"
  echo "  local -a " & locals.join(" ")
  echo "  subcommands=("
  for cmd in commands:
    if not cmd.shellCompletion:
      continue
    if cmd.help != "":
      echo "    '" & cmd.name & ":" & cmd.help.replace("'", "'\\''") & "'"
    else:
      echo "    '" & cmd.name & "'"
  echo "  )"
  writeZshOptions("options", mainOptions)
  for cmd in commands:
    if not cmd.shellCompletion:
      continue
    writeZshOptions(cmd.name & "_options", cmd.opts)
  echo """
  if (( CURRENT == 2 )); then
    _describe 'command' subcommands
    _describe 'option' options
    _files
  else
    case "$words[2]" in"""
  for cmd in commands:
    if not cmd.shellCompletion:
      continue
    echo "      " & cmd.name & ")"
    echo "        _describe 'option' " & cmd.name & "_options"
    if cmd.files:
      echo "        _files"
    echo "        ;;"
  echo """      *)
        _describe 'option' options
        _files
        ;;
    esac
  fi
}

_auto-editor "$@"
"""

macro genCmdCases*(keyIdent: untyped): untyped =
  ## Generates a case statement that dispatches to command handlers.
  ## Returns true if a command was matched and handled, false otherwise.
  result = newNimNode(nnkCaseStmt)
  result.add(keyIdent)

  for cmd in commands:
    var branch = newNimNode(nnkOfBranch)
    branch.add(newStrLitNode(cmd.name))

    # Build: commandLineParams()[1..^1]
    let sliceExpr = newNimNode(nnkInfix).add(ident(".."), newIntLitNode(1), newNimNode(
        nnkPrefix).add(ident("^"), newIntLitNode(1)))
    let argsExpr = newNimNode(nnkBracketExpr).add(newCall(ident("commandLineParams")), sliceExpr)
    let handlerName = if cmd.handler == "": cmd.name else: cmd.handler
    let handlerCall = newCall(newDotExpr(ident(handlerName), ident("main")), argsExpr)

    var stmtList = newStmtList()
    if cmd.help != "" and cmd.requiresArgs:
      # if paramCount() < 2: echo help else: handler(args)
      stmtList.add(newNimNode(nnkIfStmt).add(
        newNimNode(nnkElifBranch).add(
          newNimNode(nnkInfix).add(ident("<"), newCall(ident("paramCount")),
              newIntLitNode(2)),
          newStmtList(newCall(ident("echo"), newStrLitNode(cmd.help)))
        ),
        newNimNode(nnkElse).add(newStmtList(handlerCall))
      ))
    else:
      stmtList.add(handlerCall)
    stmtList.add(newCall(ident("quit"), newIntLitNode(0)))

    branch.add(stmtList)
    result.add(branch)

  # else branch - do nothing (no match)
  var elseBranch = newNimNode(nnkElse)
  elseBranch.add(newStmtList(newNimNode(nnkDiscardStmt).add(newEmptyNode())))
  result.add(elseBranch)


const argsFlagOptions = {
  coPreview, coVn, coAn, coSn, coDn, coFaststart, coNoFaststart, coFragmented,
  coNoFragmented, coNoSeek, coNoPartialLossless, coMixAudioStreams, coOpen,
  coNoOpen, coWebCodecs,
}

func flagTarget(opt: CliOption): string {.compileTime.} =
  for option in cliOptions:
    if option.kind == Flag and option.datum == opt:
      result = cliOptionName(opt)
      result[0] = result[0].toLowerAscii
      return
  raiseAssert "CLI option is not a flag: " & system.`$`(opt)

func argsFlags(): seq[CliOption] {.compileTime.} =
  for opt in mainOptions:
    if opt.kind == Flag and opt.datum in argsFlagOptions:
      result.add(opt.datum)

macro genFlagInterface*(argsType: untyped): untyped =
  ## Generates getter/setter procs for each args.* flag using bitpacking on flags: uint32.
  result = newStmtList()
  let flags = argsFlags()
  for i, opt in flags:
    let name = flagTarget(opt)
    let maskVal = 1'u32 shl uint32(i)
    let mask = newLit(maskVal)
    let notMask = newLit(not maskVal)
    let argsParam = ident("args")
    let valParam = ident("val")

    # func name*(args: ArgsType): bool = (args.flags and mask) != 0
    let getter = newProc(
      newNimNode(nnkPostfix).add(ident("*"), ident(name)),
      [ident("bool"), newIdentDefs(argsParam, argsType)],
      newNimNode(nnkInfix).add(ident("!="),
        newNimNode(nnkInfix).add(ident("and"),
          newDotExpr(argsParam, ident("flags")), mask),
        newLit(0'u32)),
      nnkFuncDef)
    result.add(getter)

    # func `name=`*(args: var ArgsType, val: bool)
    let setterBody = newNimNode(nnkIfStmt).add(
      newNimNode(nnkElifBranch).add(valParam,
        newStmtList(newAssignment(
          newDotExpr(argsParam, ident("flags")),
          newNimNode(nnkInfix).add(ident("or"),
            newDotExpr(argsParam, ident("flags")), mask)))),
      newNimNode(nnkElse).add(newStmtList(newAssignment(
        newDotExpr(argsParam, ident("flags")),
        newNimNode(nnkInfix).add(ident("and"),
          newDotExpr(argsParam, ident("flags")), notMask)))))
    let setter = newProc(
      newNimNode(nnkPostfix).add(ident("*"),
        newNimNode(nnkAccQuoted).add(ident(name & "="))),
      [newEmptyNode(),
       newIdentDefs(argsParam, newNimNode(nnkVarTy).add(argsType)),
       newIdentDefs(valParam, ident("bool"))],
      setterBody,
      nnkFuncDef)
    result.add(setter)

macro genCliMacro*(keyIdent, argsIdent: untyped, myOpts: static seq[OptDef]): untyped =
  ## Generates a case statement for CLI option handling.
  ## - Flag: sets datum to true (or bitpacks into args.flags if datum starts with "args.")
  ## - Special: parses datum as an export specification
  ## - Regular: sets expecting to datum string
  result = newNimNode(nnkCaseStmt)
  result.add(keyIdent)

  for opt in myOpts:
    var branch = newNimNode(nnkOfBranch)

    for name in opt.names.split(", "):
      branch.add(newStrLitNode(name.strip()))

    var stmts = newStmtList()

    case opt.kind
    of Flag:
      # Generate: datum = true  (for args.X, this calls the generated setter)
      let target =
        if opt.datum in argsFlagOptions:
          newDotExpr(argsIdent, ident(flagTarget(opt.datum)))
        else:
          ident(flagTarget(opt.datum))
      stmts.add(newAssignment(target, ident("true")))
    of Special:
      # Generate: args.`export` = parseExportString("datum")
      let target = newDotExpr(argsIdent, newNimNode(nnkAccQuoted).add(ident("export")))
      stmts.add(newAssignment(target, newCall(
        ident("parseExportString"), newStrLitNode($opt.datum))))
    of Regular:
      # Generate: expecting = datum
      stmts.add(newAssignment(ident("expecting"), newLit(opt.datum)))

    stmts.add(ident("true"))
    branch.add(stmts)
    result.add(branch)

  var elseBranch = newNimNode(nnkElse)
  elseBranch.add(newStmtList(ident("false")))
  result.add(elseBranch)
