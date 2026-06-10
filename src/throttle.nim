## Cooperative pause point for the proxy/preview render. The host app keeps the
## encoder from running more than a fixed lead ahead of the playhead by handing
## us a "permit": the maximum output-time (in milliseconds) we're allowed to
## reach. `checkpoint` is called once per written video frame and blocks while
## the frame's output time is past the permit, resuming when the host raises it.
##
## Transport differs by build, but the protocol (a monotonically-rising int
## watermark) is the same:
##   - native:     the host writes the permit to the file named by AE_THROTTLE_FILE
##                 (via tmp-file + atomic rename); we poll it.
##   - emscripten: the host exposes AE_CTRL, an Int32Array over a SharedArrayBuffer
##                 (index 0 = permit ms). We Atomics.wait on it — legal because the
##                 binary runs on a Worker thread, and it parks the thread with no
##                 busy loop. Inert if AE_CTRL was never set up.

when defined(emscripten):
  {.emit: "#include <emscripten.h>".}

  proc wasmThrottleActive(): cint =
    var r: cint = 0
    {.emit: """`r` = EM_ASM_INT({ return (typeof AE_CTRL !== 'undefined' && AE_CTRL) ? 1 : 0; });""".}
    r

  proc wasmThrottleWait(needMs: cint) =
    # The 250ms timeout makes us re-check periodically, so a missed notify can't
    # park us forever; the host's setPermit() does Atomics.notify to wake promptly.
    {.emit: """EM_ASM({
      if (typeof AE_CTRL === 'undefined' || !AE_CTRL) return;
      while (Atomics.load(AE_CTRL, 0) < $0) {
        if (Atomics.load(AE_CTRL, 1) === 1) break;   // host abort flag
        Atomics.wait(AE_CTRL, 0, Atomics.load(AE_CTRL, 0), 250);
      }
    }, `needMs`);""".}
else:
  import std/[os, strutils]

type Throttle* = object
  enabled: bool
  when not defined(emscripten):
    path: string
    cachedMs: int   # last permit we read; skip the file read while still under it

proc initThrottle*(): Throttle =
  when defined(emscripten):
    result.enabled = wasmThrottleActive() != 0
  else:
    result.path = getEnv("AE_THROTTLE_FILE")
    result.enabled = result.path.len > 0

proc checkpoint*(t: var Throttle, outputSec: float) =
  ## Block until the host permits output up to `outputSec`. No-op when throttling
  ## wasn't set up (the common case: real exports, or a host that doesn't drive it).
  if not t.enabled or outputSec < 0:
    return
  let needMs = int(outputSec * 1000.0)
  when defined(emscripten):
    wasmThrottleWait(cint(needMs))
  else:
    if t.cachedMs >= needMs:
      return
    while true:
      t.cachedMs =
        try: parseInt(strip(readFile(t.path)))
        except CatchableError: high(int)   # unreadable -> don't block (no deadlock)
      if t.cachedMs >= needMs:
        break
      sleep(50)
