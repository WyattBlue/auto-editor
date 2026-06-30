import std/[os, json, strformat, strutils, typedthreads]
import ./[av, ffmpeg, log]

type
  WhisperCtx = pointer
  WhisperSegmentCb = proc(user: pointer, text: cstring, t0ms, t1ms: int64) {.cdecl.}

when defined(whisper):
  {.compile: "whisper_stream.c".}

  proc ae_whisper_init(modelPath: cstring, useGpu, verbose: cint): WhisperCtx {.importc, cdecl.}
  proc ae_whisper_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    language: cstring, translate: cint, nThreads: cint, initialPrompt: cstring,
    maxLen: cint, onSegment: WhisperSegmentCb, user: pointer): cint {.importc, cdecl.}
  proc ae_whisper_free(ctx: WhisperCtx) {.importc, cdecl.}
else:
  proc ae_whisper_init(modelPath: cstring, useGpu, verbose: cint): WhisperCtx = nil
  proc ae_whisper_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    language: cstring, translate: cint, nThreads: cint, initialPrompt: cstring,
    maxLen: cint, onSegment: WhisperSegmentCb, user: pointer): cint = -1
  proc ae_whisper_free(ctx: WhisperCtx) = discard

const
  Rate = 16000               # whisper's sample rate; the graph resamples to it
  WinSize = 480              # 30ms analysis window, matching auto-editor's chunking
  SilenceGap = Rate div 2    # 0.5s of trailing silence ends an utterance
  PrerollMax = Rate div 5    # keep 0.2s of pre-speech audio so onsets aren't clipped
  MinSpeech = Rate div 5     # ignore <0.2s blips (clicks, coughs)

type OutCtx = object
  f: File
  format: string
  splitWords: bool
  index: int
  segStartMs: int64

func srtTime(ms: int64): string =
  &"{ms div 3600000:02}:{(ms div 60000) mod 60:02}:{(ms div 1000) mod 60:02},{ms mod 1000:03}"

# Called by whisper_stream.c per text segment, on this (main) thread, so Nim GC
# and File writes are safe.
proc segCb(user: pointer, text: cstring, t0ms, t1ms: int64) {.cdecl.} =
  let oc = cast[ptr OutCtx](user)
  var s = ($text).strip(leading = true, trailing = true)
  s = s.replace("[BLANK_AUDIO]", "").strip()
  if s.len == 0: return
  if oc.splitWords and s in ["[", "]", "BLANK", "_", "AUDIO"]: return

  let startMs = oc.segStartMs + t0ms
  let endMs = oc.segStartMs + t1ms
  case oc.format
  of "srt":
    oc.index += 1
    oc.f.write(&"{oc.index}\n{srtTime(startMs)} --> {srtTime(endMs)}\n{s}\n\n")
  of "json":
    oc.f.write($(%*{"start": startMs, "end": endMs, "text": s}) & "\n")
  else:
    oc.f.write(s & "\n")
  oc.f.flushFile()

type
  Job = object
    samples: seq[float32]    # mono f32 @16k; len 0 is the end-of-stream sentinel
    startMs: int64
  WorkerArgs = object
    wctx: WhisperCtx
    oc: ptr OutCtx
    jobs: ptr Channel[Job]
    language: string
    translate: cint
    threads: cint
    prompt: string
    maxLen: cint
    debug: bool

const MaxPending = 16  # queued utterances before capture has to wait (back-pressure)

# Whisper runs here, off the capture thread, so a (multi-second) transcription
# never stalls av_read_frame and live mic audio isn't dropped. This thread alone
# drives the run-call sequence — preserving whisper's cross-call prompt context —
# and owns every output write (via segCb); the capture thread only feeds it jobs.
proc whisperWorker(a: ptr WorkerArgs) {.thread.} =
  while true:
    var job = a.jobs[].recv()
    if job.samples.len == 0: break
    a.oc.segStartMs = job.startMs
    if a.debug:
      stderr.writeLine(&"transcribing {job.samples.len} samples at {job.startMs} ms")
    discard ae_whisper_run(a.wctx, addr job.samples[0], job.samples.len.cint,
      a.language.cstring, a.translate, a.threads, a.prompt.cstring,
      a.maxLen, segCb, a.oc)

proc run*(fmtCtx: ptr AVFormatContext, audioStream: ptr AVStream,
    model, language: string, translate: bool, format, output: string,
    queue: int, threshold: float32, prompt: string, threads: cint,
    splitWords, debug: bool, stop: ptr bool) =
  ## Read `audioStream` from the open `fmtCtx` (a file or the live mic) until it
  ## ends or `stop[]` is set, transcribing each detected speech segment. Output
  ## goes to `output` ("-" = stdout).
  let wctx = ae_whisper_init(model.cstring, 1, (if debug: 1.cint else: 0.cint))
  if wctx == nil:
    when defined(whisper):
      error &"Could not load whisper model: {model}"
    else:
      error "This build of auto-editor has no whisper support"
  defer: ae_whisper_free(wctx)

  let outFile = if output == "-": stdout
    else: (try: open(output, fmWrite) except IOError: error &"Could not open output: {output}")
  defer: (if output != "-": outFile.close())

  # Resample whatever the device gives us to mono f32 @16k for whisper.
  let sr = audioStream.codecpar.sample_rate
  let fmt = cast[AVSampleFormat](audioStream.codecpar.format)
  let fmtName = av_get_sample_fmt_name(fmt.cint)
  let chl = $audioStream.codecpar.ch_layout
  let tb = audioStream.time_base
  let bufferArgs = &"sample_rate={sr}:sample_fmt={fmtName}:channel_layout={chl}:time_base={tb.num}/{tb.den}"

  let graph = avfilter_graph_alloc()
  if graph == nil: error "out of memory"
  defer: avfilter_graph_free(addr graph)

  var srcCtx, resCtx, afmtCtx, sinkCtx: ptr AVFilterContext
  var ret = avfilter_graph_create_filter(addr srcCtx, avfilter_get_by_name("abuffer"), nil, bufferArgs.cstring, nil, graph)
  if ret >= 0: ret = avfilter_graph_create_filter(addr resCtx, avfilter_get_by_name("aresample"), nil, "16000", nil, graph)
  if ret >= 0: ret = avfilter_graph_create_filter(addr afmtCtx, avfilter_get_by_name("aformat"), nil,
    "sample_fmts=flt:channel_layouts=mono:sample_rates=16000", nil, graph)
  if ret >= 0: ret = avfilter_graph_create_filter(addr sinkCtx, avfilter_get_by_name("abuffersink"), nil, nil, nil, graph)
  if ret < 0: error "Failed to create audio filters"
  if avfilter_link(srcCtx, 0, resCtx, 0) < 0 or avfilter_link(resCtx, 0, afmtCtx, 0) < 0 or
      avfilter_link(afmtCtx, 0, sinkCtx, 0) < 0:
    error "Failed to connect filters"
  graph.nb_threads = threads
  if avfilter_graph_config(graph, nil) < 0:
    error "Failed to configure filter graph"

  var oc = OutCtx(f: outFile, format: format, splitWords: splitWords)
  let maxSeg = queue * Rate

  var jobs: Channel[Job]
  jobs.open(MaxPending)

  var seg = newSeqOfCap[float32](maxSeg + Rate)
  var preroll = newSeqOfCap[float32](PrerollMax)
  var inSpeech = false
  var silenceRun = 0
  var speechSamples = 0
  var elapsed: int64 = 0        # total samples seen (real-time clock)
  var segStartSample: int64 = 0

  proc flushSeg() =
    # Hand the utterance to the worker and keep capturing; blocks only if the
    # queue is full (whisper falling behind real-time) — never silently drops.
    if seg.len > 0 and speechSamples >= MinSpeech:
      jobs.send(Job(samples: move seg, startMs: (segStartSample * 1000) div Rate))
    seg = newSeqOfCap[float32](maxSeg + Rate)
    inSpeech = false
    silenceRun = 0
    speechSamples = 0

  proc gateWindow(w: ptr UncheckedArray[float32], L: int) =
    var peak: float32 = 0
    for i in 0 ..< L:
      let a = abs(w[i])
      if a > peak: peak = a
    let winStart = elapsed
    elapsed += L

    if peak >= threshold:
      if not inSpeech:
        inSpeech = true
        segStartSample = winStart - preroll.len  # back-date to include preroll
        if preroll.len > 0:
          seg.add(preroll)
          preroll.setLen(0)
      for i in 0 ..< L: seg.add(w[i])
      speechSamples += L
      silenceRun = 0
    elif inSpeech:
      for i in 0 ..< L: seg.add(w[i])  # keep the natural trailing tail
      silenceRun += L
      if silenceRun >= SilenceGap:
        flushSeg()
    else:
      for i in 0 ..< L: preroll.add(w[i])  # rolling pre-speech buffer
      if preroll.len > PrerollMax:
        preroll = preroll[preroll.len - PrerollMax .. ^1]

    if inSpeech and seg.len >= maxSeg:
      flushSeg()

  proc gateFrame(fr: ptr AVFrame) =
    let n = fr.nb_samples.int
    let data = cast[ptr UncheckedArray[float32]](fr.data[0])
    var i = 0
    while i < n:
      let L = min(WinSize, n - i)
      gateWindow(cast[ptr UncheckedArray[float32]](addr data[i]), L)
      i += L

  let dec = initDecoder(audioStream.codecpar)
  defer: avcodec_free_context(addr dec)
  let frame = av_frame_alloc()
  defer: av_frame_free(addr frame)
  let outFrame = av_frame_alloc()
  defer: av_frame_free(addr outFrame)
  let pkt = av_packet_alloc()
  defer: av_packet_free(addr pkt)

  var wargs = WorkerArgs(wctx: wctx, oc: addr oc, jobs: addr jobs,
    language: language, translate: (if translate: 1.cint else: 0.cint),
    threads: threads, prompt: prompt,
    maxLen: (if splitWords: 1.cint else: 0.cint), debug: debug)
  var worker: Thread[ptr WorkerArgs]
  createThread(worker, whisperWorker, addr wargs)

  while not stop[]:
    # avfoundation returns EAGAIN whenever no buffer is ready yet (including right
    # at startup), so retry on that; only EOF/fatal (e.g. device unplugged) stops.
    let ret = av_read_frame(fmtCtx, pkt)
    if ret == AVERROR_EAGAIN:
      sleep(5)
      continue
    if ret < 0:
      break
    if pkt.stream_index == audioStream.index and avcodec_send_packet(dec, pkt) >= 0:
      while avcodec_receive_frame(dec, frame) >= 0:
        discard av_buffersrc_write_frame(srcCtx, frame)
        av_frame_unref(frame)
        while av_buffersink_get_frame_flags(sinkCtx, outFrame, 0) >= 0:
          gateFrame(outFrame)
          av_frame_unref(outFrame)
    av_packet_unref(pkt)

  # Drain the resampler, enqueue whatever utterance was in progress, then let the
  # worker finish the whole backlog (Ctrl-C included) before we tear anything down.
  discard av_buffersrc_write_frame(srcCtx, nil)
  while av_buffersink_get_frame_flags(sinkCtx, outFrame, 0) >= 0:
    gateFrame(outFrame)
    av_frame_unref(outFrame)
  flushSeg()

  let pending = jobs.peek()
  if pending > 0:
    stderr.writeLine(&"finishing {pending} queued segment(s)...")
  jobs.send(Job(samples: @[]))  # sentinel
  joinThread(worker)
  jobs.close()
