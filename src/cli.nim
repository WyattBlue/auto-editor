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

type FlagDef* = object
  flagName*: string  # Comma-separated names like "-q, --quiet"
  datum*: string     # Variable to set true, e.g., "quiet" or "args.preview"
  help*: string

const flags*: seq[FlagDef] = @[
  FlagDef(flagName: "-V, --version", datum: "showVersion", help: "Show info about this program or option"),
  FlagDef(flagName: "-q, --quiet", datum: "quiet", help: "Display less output"),
  FlagDef(flagName: "--debug", datum: "isDebug", help: "Show debugging messages and values"),
  FlagDef(flagName: "--preview, --stats", datum: "args.preview", help: "Show stats on how the input will be cut and halt"),
  FlagDef(flagName: "--no-open", datum: "args.noOpen", help: "Do not open the output file after editing is done"),
  FlagDef(flagName: "--no-seek", datum: "args.noSeek", help: "Disable file seeking when rendering video"),
  FlagDef(flagName: "--faststart", datum: "args.faststart", help: "Enable movflags +faststart"),
  FlagDef(flagName: "--no-faststart", datum: "args.noFaststart", help: "Disable movflags +faststart"),
  FlagDef(flagName: "--fragmented", datum: "args.fragmented", help: "Use fragmented mp4/mov"),
  FlagDef(flagName: "--no-fragmented", datum: "args.noFragmented", help: "Do not use fragmented mp4/mov"),
  FlagDef(flagName: "--mix-audio-streams", datum: "args.mixAudioStreams", help: "Mix all audio streams together into one"),
  FlagDef(flagName: "-vn", datum: "args.vn", help: "Disable the inclusion of video streams"),
  FlagDef(flagName: "-an", datum: "args.an", help: "Disable the inclusion of audio streams"),
  FlagDef(flagName: "-sn", datum: "args.sn", help: "Disable the inclusion of subtitle streams"),
  FlagDef(flagName: "-dn", datum: "args.dn", help: "Disable the inclusion of data streams"),
]

proc zshcomplete*() =
  echo "#compdef auto-editor"
  echo ""
  echo "_auto-editor() {"
  echo "  local -a subcommands"
  echo "  subcommands=("
  for cmd in commands:
    if cmd.help != "":
      echo "    '" & cmd.name & ":" & cmd.help.replace("'", "'\\''") & "'"
    else:
      echo "    '" & cmd.name & "'"
  echo "  )"
  echo """
  if (( CURRENT == 2 )); then
    _describe 'command' subcommands
    _files
  else
    case "$words[2]" in
      cache)
        # No file completion for cache command
        ;;
      *)
        _files
        ;;
    esac
  fi
}

_auto-editor "$@"
"""

macro genFlagCases*(keyIdent, argsIdent: untyped): untyped =
  ## Generates a block that checks if key matches a flag, sets datum to true,
  ## and evaluates to true if handled, false otherwise.
  var caseStmt = newNimNode(nnkCaseStmt)
  caseStmt.add(keyIdent)

  for flag in flags:
    var branch = newNimNode(nnkOfBranch)

    # Parse comma-separated flag names
    for name in flag.flagName.split(", "):
      branch.add(newStrLitNode(name.strip()))

    # Generate: datum = true; true
    let parts = flag.datum.split(".")
    var target: NimNode
    if parts.len == 2 and parts[0] == "args":
      target = newDotExpr(argsIdent, ident(parts[1]))
    else:
      target = ident(flag.datum)

    let assignment = newAssignment(target, ident("true"))
    branch.add(newStmtList(assignment, ident("true")))
    caseStmt.add(branch)

  # else branch returns false
  var elseBranch = newNimNode(nnkElse)
  elseBranch.add(newStmtList(ident("false")))
  caseStmt.add(elseBranch)

  result = caseStmt

macro genCmdCases*(keyIdent: untyped): untyped =
  ## Generates a case statement that dispatches to command handlers.
  ## Returns true if a command was matched and handled, false otherwise.
  var caseStmt = newNimNode(nnkCaseStmt)
  caseStmt.add(keyIdent)

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
    caseStmt.add(branch)

  # else branch - do nothing (no match)
  var elseBranch = newNimNode(nnkElse)
  elseBranch.add(newStmtList(newNimNode(nnkDiscardStmt).add(newEmptyNode())))
  caseStmt.add(elseBranch)

  result = caseStmt
