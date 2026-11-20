## An encoder that runs on its own thread. FFmpeg's audio encoders are
## single-threaded and, called inline, the video waits on them: AAC takes about
## as long as H.264 with its own threads does, so a render spent half its time
## on sound. Here the caller hands frames over and collects packets as they
## come, so the two encode side by side.
##
## Frames and packets are FFmpeg's (C) memory and the codec context is the
## worker's alone until `close`, so nothing of Nim's crosses the thread.

import std/typedthreads

import ../[ffmpeg, log]

type
  EncoderJob = object
    ctx: ptr AVCodecContext
    frames: Channel[pointer] ## an AVFrame; nil asks for a flush. (A typed
      ## channel would need type info for FFmpeg's opaque structs.)
    packets: Channel[ptr AVPacket] ## nil: no more are coming
    err: cint ## why encoding stopped early; 0 if it didn't
    sending: bool ## whether `err` came from sending a frame

  AsyncEncoder* = ref object
    job: EncoderJob
    thread: Thread[ptr EncoderJob]
    depth: int
    flushed: bool ## the flush has been asked for
    finished: bool ## the worker's closing nil has been received
    closed: bool

proc encodeLoop(j: ptr EncoderJob) {.thread.} =
  var pkt: ptr AVPacket = nil
  var failed = false
  while true:
    var frame = cast[ptr AVFrame](j.frames.recv())
    let flush = frame == nil
    if not failed:
      let ret = avcodec_send_frame(j.ctx, frame)
      if ret < 0:
        (j.err, j.sending, failed) = (ret, true, true)
      while not failed:
        if pkt == nil:
          pkt = av_packet_alloc()
          if pkt == nil:
            (j.err, failed) = (AVERROR(ENOMEM), true)
            break
        let r = avcodec_receive_packet(j.ctx, pkt)
        if r == AVERROR_EAGAIN or r == AVERROR_EOF:
          break
        if r < 0:
          # As the inline encode does: a failing flush just ends the stream.
          if not flush:
            (j.err, failed) = (r, true)
          break
        j.packets.send(pkt) # the consumer frees it
        pkt = nil
      if failed:
        j.packets.send(nil) # stop the consumer now; keep taking frames
    if frame != nil:
      av_frame_free(addr frame)
    if flush:
      break
  if pkt != nil:
    av_packet_free(addr pkt)
  if not failed:
    j.packets.send(nil)

proc newAsyncEncoder*(ctx: ptr AVCodecContext, depth = 32): AsyncEncoder =
  ## Encode with the opened `ctx` on a new thread, `depth` frames queued at
  ## most. Until `close`, only the worker may touch `ctx`.
  result = AsyncEncoder(depth: depth)
  result.job.ctx = ctx
  result.job.frames.open(depth)
  result.job.packets.open()
  createThread(result.thread, encodeLoop, addr result.job)

proc fail(e: AsyncEncoder) {.noreturn.} =
  if e.job.sending:
    error "Error sending frame to encoder: " & $e.job.err
  error "Error receiving packet from encoder: " & av_err2str(e.job.err)

proc take(e: AsyncEncoder, wait: bool): ptr AVPacket =
  if e.finished:
    return nil
  if wait:
    result = e.job.packets.recv()
  else:
    let (ok, p) = e.job.packets.tryRecv()
    if not ok:
      return nil
    result = p
  if result == nil:
    e.finished = true
    if e.job.err != 0:
      e.fail()

proc hasRoom*(e: AsyncEncoder): bool =
  ## Whether `send` would take a frame without waiting.
  e.job.frames.peek() < e.depth

func flushed*(e: AsyncEncoder): bool = e.flushed

proc send*(e: AsyncEncoder, frame: ptr AVFrame) =
  ## Queue `frame`, which the encoder now owns, waiting while the queue is full.
  if e.finished and e.job.err != 0:
    av_frame_free(addr frame)
    e.fail()
  e.job.frames.send(cast[pointer](frame))

iterator ready*(e: AsyncEncoder): ptr AVPacket =
  ## The packets encoded so far, without waiting. Each is the caller's to free.
  while true:
    let p = e.take(wait = false)
    if p == nil:
      break
    yield p

iterator flush*(e: AsyncEncoder): ptr AVPacket =
  ## Every packet still to come, the encoder's delayed ones included, waiting
  ## for each. Each is the caller's to free.
  if not e.flushed:
    e.flushed = true
    e.job.frames.send(nil)
  while true:
    let p = e.take(wait = true)
    if p == nil:
      break
    yield p

proc close*(e: AsyncEncoder) =
  ## Stop the worker and join it, freeing whatever it didn't hand over. Safe
  ## to call more than once, and after an error.
  if e == nil or e.closed:
    return
  e.closed = true
  if not e.flushed:
    e.flushed = true
    e.job.frames.send(nil)
  while not e.finished:
    var p = e.job.packets.recv()
    if p == nil:
      e.finished = true
    else:
      av_packet_free(addr p)
  joinThread(e.thread)
  e.job.frames.close()
  e.job.packets.close()
