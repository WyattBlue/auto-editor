import std/[macros, strutils]

type CmdDef* = object
  name*: string
  help*: string

const commands*: seq[CmdDef] = @[
  CmdDef(name: "cache", help: ""),
  CmdDef(name: "desc", help: "Display a media file's description metadata"),
  CmdDef(name: "info", help: "Retrieve information and properties about media files"),
  CmdDef(name: "levels", help: "Display loudness over time"),
  CmdDef(name: "subdump", help: "Dump text-based subtitles to stdout with formatting stripped out"),
  CmdDef(name: "whisper", help: "Transcribe audio with ggml models"),
]

type Categories* = enum
  cEdit cTl cUrl cDis cCon cVid cAud cMis

type OptKind* = enum
  Regular   # expecting = $datum
  Flag      # $datum = true
  Special  # args.`export` = "$datum"

type OptDef* = object
  names*: string
  kind*: OptKind = Regular
  c*: Categories
  datum*: string
  metavar*: string  # Shouldn't be set for flags.
  help*: string

const mainOptions*: seq[OptDef] = @[
  OptDef(names: "-e, --edit", c: cEdit, datum: "edit", metavar: "METHOD", help: """
Set an expression which determines how to make auto edits. (default is "audio")"""),
  OptDef(names: "--when-normal", c: cEdit, datum: "when-normal", metavar: "ACTION",
    help: "When the video is not silent (defined by --edit) do an action. The default action being 'nil'"),
  OptDef(names: "--when-silent", c: cEdit, datum: "when-silent", metavar: "ACTION", help: """
When the video is silent (defined by --edit) do an action. The default action being 'cut'

Actions available:
  nil, unchanged/do nothing
  cut, remove completely
  speed, (val: float),
    change the speed while preserving pitch. val: between (0-99999)
  varispeed, (val: float),
    change the speed by varying pitch. val: between [0.2-100]"""),
  OptDef(names: "-m, --margin", c: cEdit, datum: "margin", metavar: "LENGTH", help: """
Set sections near "loud" as "loud" too if section is less than LENGTH away. (default is "0.2s")"""),
  OptDef(names: "-ex, --export", datum: "export",
    metavar: "EXPORT:ATTRS?", help: "Choose the export mode"),
  OptDef(names: "-exp, --export-to-premiere", kind: Special, datum: "premiere"),
  OptDef(names: "-exr, --export-to-resolve", kind: Special, datum: "resolve"),
  OptDef(names: "-exf, --export-to-final-cut-pro", kind: Special, datum: "final-cut-pro"),
  OptDef(names: "-exs, --export-to-shotcut", kind: Special, datum: "shotcut"),
  OptDef(names: "-exk, --export-to-kdenlive", kind: Special, datum: "kdenlive"),
  OptDef(names: "-o, --output", c: cEdit, datum: "output",
    metavar: "FILE", help: "Set the name/path of the new output file"),
  OptDef(names: "--cut-out, --cut", c: cEdit, datum: "cut-out",
    metavar: "[START,STOP ...]", help: "The range that will be cut/removed"),
  OptDef(names: "--add-in, --keep", c: cEdit, datum: "add-in",
    metavar: "[START,STOP ...]", help: "The range that will be leaved \"as is\", overridding other actions"),
  OptDef(names: "--set-speed, --set-speed-for-range", c: cEdit, datum: "set-speed",
    metavar: "[SPEED,START,STOP ...]", help: "Set a SPEED for a given range"),
  OptDef(names: "-s, --silent-speed", c: cEdit, datum: "silent-speed", metavar: "NUM",
    help: "[Deprecated] Set speed of sections marked \"silent\" to NUM. (default is 99999)"),
  OptDef(names: "-v, --video-speed", c: cEdit, datum: "video-speed", metavar: "NUM",
    help: "[Deprecated] Set speed of sections marked \"loud\" to NUM. (default is 1)"),

  OptDef(names: "-tb, --time-base, -r, -fps, --frame-rate", c: cTl, datum: "frame-rate",
    metavar: "NUM", help: "Set timeline frame rate"),
  OptDef(names: "-ar, --sample-rate", c: cTl, datum: "sample-rate", metavar: "NAT",
    help: "Set timeline sample rate"),
  OptDef(names: "-res, --resolution", c: cTl, datum: "resolution",
    metavar: "WIDTH,HEIGHT", help: "Set timeline width and height"),
  OptDef(names: "-b, -bg, --background", c: cTl, datum: "background", metavar: "COLOR",
    help: "Set the background as a solid RGB color"),

  OptDef(names: "--yt-dlp-location", c: cUrl, datum: "yt-dlp-location", metavar: "PATH",
    help: "Set a custom path to yt-dlp"),
  OptDef(names: "--download-format", c: cUrl, datum: "download-format", metavar: "FORMAT",
    help: "Set the yt-dlp download format (--format, -f)"),
  OptDef(names: "--output-format", c: cUrl, datum: "output-format", metavar: "TEMPLATE",
    help: "Set the yt-dlp output file template (--output, -o)"),
  OptDef(names: "--yt-dlp-extras", c: cUrl, datum: "yt-dlp-extras",  metavar: "CMD",
    help: "Add extra options for yt-dlp. Must be in quotes"),

  OptDef(names: "--progress", c: cDis, datum: "progress", metavar: "PROGRESS",
    help: "Set what type of progress bar to use"),
  OptDef(names: "--debug", c: cDis, kind: Flag, datum: "isDebug",
    help: "Show debugging messages and values"),
  OptDef(names: "-q, --quiet", c: cDis, kind: Flag, datum: "quiet",
    help: "Display less output"),
  OptDef(names: "--preview, --stats", c: cDis, kind: Flag, datum: "args.preview",
    help: "Show stats on how the input will be cut and halt"),

  OptDef(names: "-vn", c: cCon, kind: Flag, datum: "args.vn",
    help: "Disable the inclusion of video streams"),
  OptDef(names: "-an", c: cCon, kind: Flag, datum: "args.an",
    help: "Disable the inclusion of audio streams"),
  OptDef(names: "-sn", c: cCon, kind: Flag, datum: "args.sn",
    help: "Disable the inclusion of subtitle streams"),
  OptDef(names: "-dn", c: cCon, kind: Flag, datum: "args.dn",
    help: "Disable the inclusion of data streams"),
  OptDef(names: "--faststart", c: cCon, kind: Flag, datum: "args.faststart",
    help: "Enable movflags +faststart, recommended for web (default)"),
  OptDef(names: "--no-faststart", c: cCon, kind: Flag, datum: "args.noFaststart",
    help: "Disable movflags +faststart, will be faster for large files"),
  OptDef(names: "--fragmented", c: cCon, kind: Flag, datum: "args.fragmented",
    help: "Use fragmented mp4/mov to allow playback before video is complete. See: ffmpeg.org/ffmpeg-formats.html#Fragmentation"),
  OptDef(names: "--no-fragmented", c: cCon, kind: Flag, datum: "args.noFragmented",
    help: "Do not use fragmented mp4/mov for better compatibility (default)"),

  OptDef(names: "-c:v, -vcodec, --video-codec", c: cVid, datum: "vcodec",
    metavar: "ENCODER", help: "Set video codec for output media"),
  OptDef(names: "-b:v, --video-bitrate", c: cVid, datum: "video-bitrate",
    metavar: "BITRATE", help: "Set the number of bits per second for video"),
  OptDef(names: "-profile:v, -vprofile", c: cVid, datum: "vprofile",
    metavar: "PROFILE", help: "Set the video profile. For h264: high, main, or baseline"),
  OptDef(names: "--scale", c: cVid, datum: "scale", metavar: "NUM",
    help: "Scale the output video's resolution by NUM factor"),
  OptDef(names: "--no-seek", c: cVid, kind: Flag, datum: "args.noSeek",
    help: "Disable file seeking when rendering video. Helpful for debugging desync issues"),

  OptDef(names: "-c:a, -acodec, --audio-codec", c: cAud, datum: "acodec",
    metavar: "ENCODER", help: "Set audio codec for output media"),
  OptDef(names: "-layout, --audio-layout", c: cAud, datum: "layout",
    metavar: "LAYOUT", help: "Set the audio layout for the output media/timeline"),
  OptDef(names: "-b:a, --audio-bitrate", c: cAud, datum: "audio-bitrate",
    metavar: "BITRATE", help: "Set the number of bits per second for audio"),
  OptDef(names: "--mix-audio-streams", c: cAud, kind: Flag, datum: "args.mixAudioStreams",
    help: "Mix all audio streams together into one"),
  OptDef(names: "-anorm, --audio-normalize", c: cAud, datum: "audio-normalize",
    metavar: "NORM-TYPE", help: """
Apply audio normalizing (either ebu or peak). Applied right before rendering the output file"""),

  OptDef(names: "--no-open", c: cMis, kind: Flag, datum: "args.noOpen",
    help: "Do not open the output file after editing is done"),
  OptDef(names: "--temp-dir", c: cMis, datum: "tempdir",
    metavar: "PATH", help: "Set where the temporary directory is located"),
  OptDef(names: "-V, --version", c: cMis, kind: Flag, datum: "showVersion",
    help: "Show info about this program or option"),
]

proc zshcomplete*() =
  echo "#compdef auto-editor"
  echo ""
  echo "_auto-editor() {"
  echo "  local -a subcommands options"
  echo "  subcommands=("
  for cmd in commands:
    if cmd.help != "":
      echo "    '" & cmd.name & ":" & cmd.help.replace("'", "'\\''") & "'"
    else:
      echo "    '" & cmd.name & "'"
  echo "  )"
  echo "  options=("
  for opt in mainOptions:
    if opt.kind == Special:
      continue
    # Get first line of help for description
    let desc = if opt.help != "": opt.help.split('\n')[0].replace("'", "'\\''").replace(":", "\\:") else: ""
    for name in opt.names.split(", "):
      let n = name.strip().replace(":", "\\:")
      if desc != "":
        echo "    '" & n & ":" & desc & "'"
      else:
        echo "    '" & n & "'"
  echo "  )"
  echo """
  if (( CURRENT == 2 )); then
    _describe 'command' subcommands
    _describe 'option' options
    _files
  else
    case "$words[2]" in
      cache)
        # No file completion for cache command
        ;;
      *)
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
    let sliceExpr = newNimNode(nnkInfix).add(
      ident(".."),
      newIntLitNode(1),
      newNimNode(nnkPrefix).add(ident("^"), newIntLitNode(1))
    )
    let argsExpr = newNimNode(nnkBracketExpr).add(
      newCall(ident("commandLineParams")),
      sliceExpr
    )
    let handlerCall = newCall(
      newDotExpr(ident(cmd.name), ident("main")),
      argsExpr
    )

    var stmtList = newStmtList()
    if cmd.help != "":
      # if paramCount() < 2: echo help else: handler(args)
      stmtList.add(newNimNode(nnkIfStmt).add(
        newNimNode(nnkElifBranch).add(
          newNimNode(nnkInfix).add(ident("<"), newCall(ident("paramCount")), newIntLitNode(2)),
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


macro genCliMacro*(keyIdent, argsIdent: untyped): untyped =
  ## Generates a case statement for CLI option handling.
  ## - Flag: sets datum to true
  ## - Special: sets args.export to datum string
  ## - Regular: sets expecting to datum string
  result = newNimNode(nnkCaseStmt)
  result.add(keyIdent)

  for opt in mainOptions:
    var branch = newNimNode(nnkOfBranch)

    for name in opt.names.split(", "):
      branch.add(newStrLitNode(name.strip()))

    var stmts = newStmtList()

    case opt.kind
    of Flag:
      # Generate: datum = true
      let parts = opt.datum.split(".")
      var target: NimNode
      if parts.len == 2 and parts[0] == "args":
        target = newDotExpr(argsIdent, ident(parts[1]))
      else:
        target = ident(opt.datum)
      stmts.add(newAssignment(target, ident("true")))
    of Special:
      # Generate: args.`export` = "datum"
      let target = newDotExpr(argsIdent, newNimNode(nnkAccQuoted).add(ident("export")))
      stmts.add(newAssignment(target, newStrLitNode(opt.datum)))
    of Regular:
      # Generate: expecting = "datum"
      stmts.add(newAssignment(ident("expecting"), newStrLitNode(opt.datum)))

    stmts.add(ident("true"))
    branch.add(stmts)
    result.add(branch)

  var elseBranch = newNimNode(nnkElse)
  elseBranch.add(newStmtList(ident("false")))
  result.add(elseBranch)
