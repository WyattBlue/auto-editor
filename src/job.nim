## Running auto-editor's work from another program: where a job's progress
## and messages go, and how to cancel it. The CLI runs one job per process
## and leaves these unset.

import std/atomics

import ./[av, log]
import ./util/bar

export ProgressHook, LogHook, AutoEditorError

type JobHooks* = object
  progress*: ProgressHook
  log*: LogHook
  cancel*: ptr Atomic[bool] ## set to true to make the job raise "Cancelled"

template withJob*(hooks: JobHooks, body: untyped) =
  ## Run `body` with `hooks` on this thread. Every call may raise
  ## AutoEditorError, and blocks, so run it on a worker thread.
  progressHook = hooks.progress
  logHook = hooks.log
  cancelFlag = hooks.cancel
  # Global and cumulative in the CLI, where each process runs one job.
  decodeErrors = 0
  try:
    body
  finally:
    progressHook = nil
    logHook = nil
    cancelFlag = nil
