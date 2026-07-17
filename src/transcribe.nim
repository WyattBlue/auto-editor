import std/[os, json, strformat, strutils, typedthreads]
import ./[av, ffmpeg, log]

type
  WhisperCtx = pointer
  WhisperSegmentCb = proc(user: pointer, text: cstring, t0ms, t1ms: int64) {.cdecl.}

when defined(whisper):
  {.emit: """
#include <whisper.h>
#include <parakeet.h>
#include <ggml.h>
#include <ggml-backend.h>

static void ae_quiet_log(enum ggml_log_level level, const char *text, void *user) {
    (void) level; (void) text; (void) user;
}

void *ae_whisper_init(const char *model_path, int use_gpu, int verbose) {
    if (!verbose) {
        whisper_log_set(ae_quiet_log, NULL);
        ggml_log_set(ae_quiet_log, NULL);
    }

    static int loaded = 0;
    if (!loaded) { ggml_backend_load_all(); loaded = 1; }

    struct whisper_context_params cp = whisper_context_default_params();
    cp.use_gpu = use_gpu != 0;
    cp.flash_attn = true;
    return whisper_init_from_file_with_params(model_path, cp);
}

// text is non-const char* to match Nim's cstring callback type (same TU now).
typedef void (*ae_seg_cb)(void *user, char *text, int64_t t0_ms, int64_t t1_ms);

// Transcribe one segment of mono f32 16kHz samples. on_segment is called once per
// resulting text segment, synchronously, on the caller's thread. t0/t1 are in ms,
// relative to the start of `samples`. Returns 0 on success.
int ae_whisper_run(void *ctx, const float *samples, int n_samples,
                   const char *language, int translate, int n_threads,
                   const char *initial_prompt, int max_len,
                   ae_seg_cb on_segment, void *user) {
    struct whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.print_special = false;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_timestamps = false;
    p.translate = translate != 0;
    p.language = language;
    p.n_threads = n_threads;
    // Carry the previous segment(s) as context. whisper keeps prior tokens in the
    // context's prompt_past (capped to ~recent), so reusing the same ctx across
    // calls conditions each utterance on the last — better continuity/spelling.
    p.no_context = false;
    p.initial_prompt = (initial_prompt && initial_prompt[0]) ? initial_prompt : NULL;
    if (max_len > 0) {
        p.max_len = max_len;
        p.token_timestamps = true;
        p.split_on_word = true;
    }

    if (whisper_full((struct whisper_context *) ctx, p, samples, n_samples) != 0)
        return -1;

    int n = whisper_full_n_segments((struct whisper_context *) ctx);
    for (int i = 0; i < n; i++) {
        const char *text = whisper_full_get_segment_text((struct whisper_context *) ctx, i);
        int64_t t0 = whisper_full_get_segment_t0((struct whisper_context *) ctx, i) * 10;
        int64_t t1 = whisper_full_get_segment_t1((struct whisper_context *) ctx, i) * 10;
        on_segment(user, (char *) text, t0, t1);
    }
    return 0;
}

void ae_whisper_free(void *ctx) {
    if (ctx) whisper_free((struct whisper_context *) ctx);
}

void *ae_parakeet_init(const char *model_path, int use_gpu, int verbose) {
    if (!verbose) {
        parakeet_log_set(ae_quiet_log, NULL);
        ggml_log_set(ae_quiet_log, NULL);
    }

    static int loaded = 0;
    if (!loaded) { ggml_backend_load_all(); loaded = 1; }

    struct parakeet_context_params cp = parakeet_context_default_params();
    cp.use_gpu = use_gpu != 0;
    return parakeet_init_from_file_with_params(model_path, cp);
}

// Same contract as ae_whisper_run. Parakeet has no language/translate/prompt
// knobs; each utterance is decoded independently. All t0/t1 are in 10ms mel
// frames, same scale as whisper's centiseconds. With split_words, one callback
// fires per word: tokens are grouped on is_word_start, with word times taken
// from the TDT token durations (punctuation has no word-start marker, so it
// attaches to the preceding word).
int ae_parakeet_run(void *ctx, const float *samples, int n_samples,
                    int n_threads, int split_words, ae_seg_cb on_segment, void *user) {
    struct parakeet_context *c = (struct parakeet_context *) ctx;
    struct parakeet_full_params p = parakeet_full_default_params(PARAKEET_SAMPLING_GREEDY);
    p.n_threads = n_threads;

    if (parakeet_full(c, p, samples, n_samples) != 0)
        return -1;

    int n = parakeet_full_n_segments(c);
    for (int i = 0; i < n; i++) {
        if (!split_words) {
            const char *text = parakeet_full_get_segment_text(c, i);
            int64_t t0 = parakeet_full_get_segment_t0(c, i) * 10;
            int64_t t1 = parakeet_full_get_segment_t1(c, i) * 10;
            on_segment(user, (char *) text, t0, t1);
            continue;
        }
        int nt = parakeet_full_n_tokens(c, i);
        char word[512]; int wlen = 0;
        int64_t t0 = 0, t1 = 0;
        for (int j = 0; j < nt; j++) {
            parakeet_token_data td = parakeet_full_get_token_data(c, i, j);
            if (td.is_word_start && wlen > 0) {
                on_segment(user, word, t0 * 10, t1 * 10);
                wlen = 0;
            }
            if (wlen == 0) t0 = td.t0;
            const char *ts = parakeet_token_to_str(c, td.id);
            wlen += parakeet_token_to_text(ts, wlen == 0, word + wlen, (int)sizeof(word) - wlen);
            if (wlen > (int)sizeof(word) - 1) wlen = (int)sizeof(word) - 1;
            t1 = td.t1;
        }
        if (wlen > 0)
            on_segment(user, word, t0 * 10, t1 * 10);
    }
    return 0;
}

void ae_parakeet_free(void *ctx) {
    if (ctx) parakeet_free((struct parakeet_context *) ctx);
}
""".}

  proc ae_whisper_init(modelPath: cstring, useGpu, verbose: cint): WhisperCtx {.importc, nodecl, cdecl.}
  proc ae_whisper_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    language: cstring, translate: cint, nThreads: cint, initialPrompt: cstring,
    maxLen: cint, onSegment: WhisperSegmentCb, user: pointer): cint {.importc, nodecl, cdecl.}
  proc ae_whisper_free(ctx: WhisperCtx) {.importc, nodecl, cdecl.}
  proc ae_parakeet_init(modelPath: cstring, useGpu, verbose: cint): WhisperCtx {.importc, nodecl, cdecl.}
  proc ae_parakeet_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    nThreads, splitWords: cint, onSegment: WhisperSegmentCb, user: pointer): cint {.importc, nodecl, cdecl.}
  proc ae_parakeet_free(ctx: WhisperCtx) {.importc, nodecl, cdecl.}
else:
  proc ae_whisper_init(modelPath: cstring, useGpu, verbose: cint): WhisperCtx = nil
  proc ae_whisper_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    language: cstring, translate: cint, nThreads: cint, initialPrompt: cstring,
    maxLen: cint, onSegment: WhisperSegmentCb, user: pointer): cint = -1
  proc ae_whisper_free(ctx: WhisperCtx) = discard
  proc ae_parakeet_init(modelPath: cstring, useGpu, verbose: cint): WhisperCtx = nil
  proc ae_parakeet_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    nThreads, splitWords: cint, onSegment: WhisperSegmentCb, user: pointer): cint = -1
  proc ae_parakeet_free(ctx: WhisperCtx) = discard

# Whisper and parakeet GGUFs share the same ggml magic, and a failed
# whisper_init on a parakeet file leaks Metal buffers, so probing is not an
# option — go by the conventional model file name (ggml-parakeet-*).
func isParakeetModel*(model: string): bool =
  "parakeet" in model.extractFilename.toLowerAscii

# Apple SpeechAnalyzer backend (src/ae_speech.swift), selected with model "apple".
when defined(appleSpeech):
  proc ae_speech_init(locale: cstring): WhisperCtx {.importc, cdecl.}
  proc ae_speech_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    splitWords: cint, onSegment: WhisperSegmentCb, user: pointer): cint {.importc, cdecl.}
  proc ae_speech_free(ctx: WhisperCtx) {.importc, cdecl.}
else:
  proc ae_speech_run(ctx: WhisperCtx, samples: ptr float32, nSamples: cint,
    splitWords: cint, onSegment: WhisperSegmentCb, user: pointer): cint = -1
  proc ae_speech_free(ctx: WhisperCtx) = discard

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
    apple: bool
    parakeet: bool
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
    let rc =
      if a.apple:
        ae_speech_run(a.wctx, addr job.samples[0], job.samples.len.cint,
          a.maxLen, segCb, a.oc)
      elif a.parakeet:
        ae_parakeet_run(a.wctx, addr job.samples[0], job.samples.len.cint,
          a.threads, a.maxLen, segCb, a.oc)
      else:
        ae_whisper_run(a.wctx, addr job.samples[0], job.samples.len.cint,
          a.language.cstring, a.translate, a.threads, a.prompt.cstring,
          a.maxLen, segCb, a.oc)
    if rc != 0:
      stderr.writeLine(&"transcription failed on segment at {job.startMs} ms; skipping")

proc run*(fmtCtx: ptr AVFormatContext, audioStream: ptr AVStream,
    model, language: string, translate: bool, format, output: string,
    queue: int, threshold: float32, prompt: string, threads: cint,
    splitWords, debug: bool, stop: ptr bool) =
  ## Read `audioStream` from the open `fmtCtx` (a file or the live mic) until it
  ## ends or `stop[]` is set, transcribing each detected speech segment. Output
  ## goes to `output` ("-" = stdout).
  let useApple = model == "apple"
  let useParakeet = not useApple and isParakeetModel(model)
  var wctx: WhisperCtx
  if useApple:
    when defined(appleSpeech):
      # Blocks while downloading the system model on first use.
      if language == "auto":
        stderr.writeLine("Apple speech cannot auto-detect language; assuming en_US (set --language to override)")
      let locale = (if language == "auto": "en_US" else: language)
      wctx = ae_speech_init(locale.cstring)
      if wctx == nil:
        error &"Apple speech init failed. It needs macOS 26+ at runtime, a supported " &
          &"language (got: {locale}), and network access for the first-run model download"
    else:
      error "The 'apple' model needs a build made on macOS 26 or later"
  elif useParakeet:
    wctx = ae_parakeet_init(model.cstring, 1, (if debug: 1.cint else: 0.cint))
    if wctx == nil:
      when defined(whisper):
        error &"Could not load parakeet model: {model}"
      else:
        error "This build of auto-editor has no whisper support"
  else:
    wctx = ae_whisper_init(model.cstring, 1, (if debug: 1.cint else: 0.cint))
    if wctx == nil:
      when defined(whisper):
        error &"Could not load whisper model: {model}"
      else:
        error "This build of auto-editor has no whisper support"
  defer:
    if useApple: ae_speech_free(wctx)
    elif useParakeet: ae_parakeet_free(wctx)
    else: ae_whisper_free(wctx)

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

  var wargs = WorkerArgs(wctx: wctx, apple: useApple, parakeet: useParakeet,
    oc: addr oc, jobs: addr jobs,
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

  # Flush the decoder first: delay codecs (AAC/MP3) still hold the last frames,
  # which carry the end of the final utterance.
  discard avcodec_send_packet(dec, nil)
  while avcodec_receive_frame(dec, frame) >= 0:
    discard av_buffersrc_write_frame(srcCtx, frame)
    av_frame_unref(frame)
    while av_buffersink_get_frame_flags(sinkCtx, outFrame, 0) >= 0:
      gateFrame(outFrame)
      av_frame_unref(outFrame)

  # Drain the resampler, enqueue whatever utterance was in progress, then let the
  # worker finish the whole backlog (Ctrl-C included) before we tear anything down.
  discard av_buffersrc_write_frame(srcCtx, nil)
  while av_buffersink_get_frame_flags(sinkCtx, outFrame, 0) >= 0:
    gateFrame(outFrame)
    av_frame_unref(outFrame)
  flushSeg()

  let pending = jobs.peek()
  if pending > 0:
    stderr.writeLine(&"\nFinishing {pending} queued segment(s)...")
  jobs.send(Job(samples: @[]))  # sentinel
  joinThread(worker)
  jobs.close()
