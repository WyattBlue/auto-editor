## Resident controller for interactive preview renders.
##
## The protocol is newline-delimited JSON over stdin/stdout. The worker owns a
## single render subprocess and its throttle channel; a new render supersedes
## the previous one. Keeping this controller alive gives GUI hosts a stable
## process and protocol while render jobs remain independently cancellable.

import std/[json, os, osproc, streams, strtabs, strutils]

type
  OutputMessage = object
    id: int
    data: string
  OutputThreadData = object
    id: int
    process: Process

type ActiveRender = ref object
  id: int
  process: Process
  outputThread: Thread[OutputThreadData]
  timelinePath: string
  controlPath: string

var inputChannel: Channel[string]
var outputChannel: Channel[OutputMessage]

proc inputWorker() {.thread.} =
  try:
    var line: string
    while stdin.readLine(line):
      inputChannel.send(line)
  except IOError:
    discard
  inputChannel.send("{\"type\":\"shutdown\"}")

proc outputWorker(data: OutputThreadData) {.thread.} =
  let stream = data.process.outputStream
  var buffer = ""
  try:
    while true:
      let c = stream.readChar()
      if c == '\0' and stream.atEnd():
        break
      if c in {'\r', '\n'}:
        if buffer != "":
          outputChannel.send(OutputMessage(id: data.id, data: buffer))
          buffer.setLen(0)
      else:
        buffer.add(c)
  except IOError:
    discard
  if buffer != "":
    outputChannel.send(OutputMessage(id: data.id, data: buffer))

proc emit(node: JsonNode) =
  stdout.write($node & "\n")
  stdout.flushFile()

proc cleanupFile(path: string) =
  if path == "":
    return
  try:
    removeFile(path)
  except OSError:
    discard

proc writePermit(path: string, permitMs: int) =
  let tempPath = path & ".tmp"
  writeFile(tempPath, $permitMs)
  when defined(windows):
    cleanupFile(path)
  moveFile(tempPath, path)

proc emitOutput(id: int, data: string) =
  if data == "":
    return
  let parts = data.split('~')
  if parts.len == 4:
    emit(%*{"type": "stdout", "id": id, "data": data})
  else:
    emit(%*{"type": "stderr", "id": id, "data": data})

proc drainOutput() =
  while true:
    let received = outputChannel.tryRecv()
    if not received.dataAvailable:
      break
    emitOutput(received.msg.id, received.msg.data)

proc cleanup(render: ActiveRender) =
  cleanupFile(render.timelinePath)
  cleanupFile(render.controlPath)
  cleanupFile(render.controlPath & ".tmp")

proc stop(render: var ActiveRender, notify: bool, immediate: bool = false) =
  if render == nil:
    return
  let stopped = render
  try:
    if immediate:
      stopped.process.kill()
    else:
      stopped.process.terminate()
  except OSError:
    discard
  var code = -1
  try:
    code = stopped.process.waitForExit(2000)
    if code == -1:
      stopped.process.kill()
      code = stopped.process.waitForExit(2000)
  except OSError:
    discard
  joinThread(stopped.outputThread)
  drainOutput()
  stopped.process.close()
  cleanup(stopped)
  if notify:
    emit(%*{"type": "done", "id": stopped.id, "code": code})
  render = nil

proc childEnvironment(message: JsonNode, controlPath: string): StringTableRef =
  result = newStringTable(modeCaseSensitive)
  for key, value in envPairs():
    result[key] = value
  if message.hasKey("env") and message["env"].kind == JObject:
    for key, value in message["env"]:
      result[key] = value.getStr()
  if controlPath != "":
    result["AE_THROTTLE_FILE"] = controlPath

proc startRender(message: JsonNode, active: var ActiveRender) =
  let id = message["id"].getInt()
  stop(active, true)

  let outputPath = message["outputPath"].getStr()
  let timelinePath = outputPath & ".preview-worker-" & $id & ".v3"
  let throttled = message.hasKey("permitMs")
  let controlPath = if throttled:
    outputPath & ".preview-worker-" & $id & ".ctrl"
  else:
    ""

  writeFile(timelinePath, message["timeline"].getStr())
  if throttled:
    writePermit(controlPath, message["permitMs"].getInt())

  var args = @[timelinePath]
  for arg in message["args"]:
    args.add(arg.getStr())

  try:
    let process = startProcess(
      getAppFilename(),
      args = args,
      env = childEnvironment(message, controlPath),
      options = {poStdErrToStdOut},
    )
    active = ActiveRender(
      id: id,
      process: process,
      timelinePath: timelinePath,
      controlPath: controlPath,
    )
    createThread(active.outputThread, outputWorker,
      OutputThreadData(id: id, process: process))
    emit(%*{"type": "started", "id": id})
  except CatchableError as error:
    cleanupFile(timelinePath)
    cleanupFile(controlPath)
    emit(%*{"type": "error", "id": id, "message": error.msg})

proc handle(message: JsonNode, active: var ActiveRender): bool =
  let kind = message["type"].getStr()
  case kind
  of "render":
    startRender(message, active)
  of "playhead":
    if active != nil and message["id"].getInt() == active.id and
        active.controlPath != "":
      try:
        writePermit(active.controlPath, message["permitMs"].getInt())
      except CatchableError as error:
        emit(%*{"type": "error", "id": active.id, "message": error.msg})
  of "cancel":
    if active != nil and message["id"].getInt() == active.id:
      stop(active, true, message{"immediate"}.getBool(false))
  of "ping":
    emit(%*{"type": "pong"})
  of "shutdown":
    stop(active, true)
    return false
  else:
    let id = if message.hasKey("id"): message["id"].getInt() else: -1
    emit(%*{"type": "error", "id": id,
      "message": "Unknown preview-worker command: " & kind})
  true

proc main*(args: seq[string]) =
  if args.len > 0:
    emit(%*{"type": "error", "id": -1,
      "message": "preview-worker does not accept command-line arguments"})
    quit(2)

  inputChannel.open()
  outputChannel.open()
  var inputThread: Thread[void]
  createThread(inputThread, inputWorker)
  var active: ActiveRender
  var running = true
  emit(%*{"type": "ready", "protocol": 1})

  while running:
    drainOutput()
    let received = inputChannel.tryRecv()
    if received.dataAvailable:
      try:
        running = handle(parseJson(received.msg), active)
      except CatchableError as error:
        emit(%*{"type": "error", "id": -1, "message": error.msg})

    if active != nil:
      var code = -1
      try:
        code = active.process.peekExitCode()
      except OSError as error:
        emit(%*{"type": "error", "id": active.id, "message": error.msg})
      if code != -1:
        let finished = active
        joinThread(finished.outputThread)
        drainOutput()
        finished.process.close()
        cleanup(finished)
        active = nil
        emit(%*{"type": "done", "id": finished.id, "code": code})

    if running:
      sleep(5)

  inputChannel.close()
  outputChannel.close()
