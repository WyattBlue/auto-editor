---
name: auto-editor-transcribe
description: Transcribe a media file or live microphone to text or subtitles with auto-editor's whisper subcommand, then edit by spoken content — cut to keep (or drop) sections whose subtitles match a word or regex. Use when someone wants a transcript, captions, live speech transcription, or to cut a video based on what is said rather than on loudness.
---

# Transcribe & edit by speech

Use auto-editor's whisper.cpp (Whisper or NVIDIA Parakeet models) or Apple Speech backend to transcribe audio. Cut a timeline based on subtitle content with `--edit subtitle`/`word`.

## Transcribe — `auto-editor whisper`

```
auto-editor whisper <file|:mic> <model> [options]
```

Set `<model>` to a `ggml` model path. Three backends, chosen by the model:

- **Whisper**: `ggml-small.en.bin`, `ggml-medium.en.bin`, `ggml-large-v3.bin`, …
  (https://huggingface.co/ggerganov/whisper.cpp). 99+ languages, `--translate`,
  `--prompt`.
- **Parakeet**: any model with "parakeet" in the filename, e.g.
  `ggml-parakeet-tdt-0.6b-v3-q8_0.bin` (https://huggingface.co/ggml-org/parakeet-GGUF).
  Faster than Whisper at comparable English accuracy; language is
  auto-detected. `--translate`, `--prompt`, and `--language` are rejected.
- **Apple**: the magic model name `apple` uses Apple's built-in transcriber;
  requires macOS 26 or later.

Only the first audio stream of a file is used. Audio is resampled to 16 kHz, and
text prints to stdout by default.

```bash
auto-editor whisper example.mp4 ggml-medium.en.bin                      # plain text → stdout
auto-editor whisper example.mp4 ggml-medium.en.bin --format srt -o out.srt
auto-editor whisper example.mp4 ggml-parakeet-tdt-0.6b-v3-q8_0.bin      # parakeet backend
auto-editor whisper example.mp4 apple --language en_US                  # macOS 26+
```

Options: `--format text|srt|json`, `-o/--output FILE`, `-l/--language en`
(default auto), `-tr/--translate` (→ English), `-sw/--split-words` (one word per
cue), `--queue SECS` (default 30), `--prompt TEXT`, `--threads N` (default 4),
and `-t/--threshold THRES` (default 0.04).

`--split-words` works with on all backends. Parakeet is the most accurate.

With the `apple` model, set `--language` to a supported language or locale.
Apple speech cannot auto-detect language, so `auto` falls back to `en_US` with a
warning. Do not pass `--translate` or `--prompt`; neither is supported. The first
use of a language may download Apple's speech model and therefore needs network
access.

### Transcribe a live microphone

Pass `:mic` instead of a file. Stop capture gracefully with Ctrl-C.

```bash
auto-editor whisper :mic ggml-medium.en.bin
auto-editor whisper :mic apple --language en_US    # macOS 26+
auto-editor whisper :mic ggml-medium.en.bin -o transcript.srt
```

This streams the microphone directly to transcription and does not save a
media recording. To retain and edit the captured audio, use `auto-editor :mic`;
editor and timeline exports save a sibling lossless-FLAC `_RECORDING.mka` by
default.

Live capture supports macOS, Windows, and Linux:

- macOS uses AVFoundation and prefers a USB microphone, then the system default.
- Windows uses DirectShow and prefers a USB microphone, then the first audio capture device.
- Linux uses the default ALSA input device.

When `-o/--output` ends in `.srt`, `.json`, `.txt`, or `.text`, the output format is
inferred unless `--format` is set explicitly.

## Edit by spoken content

`--edit subtitle`/`word` marks the time a matching subtitle line occupies as
**active** (kept by default). Use an existing subtitle stream, or transcribe to
an `.srt` first and feed it in.

| Method | Active when… | Args (defaults) |
|---|---|---|
| `subtitle` / `regex` | `pattern` (regex) matches a line | `pattern=""` (empty matches every line), `stream=0`, `ignore-case=#f` |
| `word` | `value` appears as a whole word | `value` required, `stream=0`, `ignore-case=#t` |

`pattern` is optional for `subtitle`/`regex`: with none, the empty regex matches
every subtitle line, so `--edit subtitle` keeps all sections that have a subtitle
(i.e. cut everything with no speech). `word`, by contrast, requires a `value`.

```bash
# Keep only sections that have any subtitle (cut the silent gaps between speech)
auto-editor talk.mkv --edit subtitle

# Keep only sections where "introduction" is spoken
auto-editor lecture.mp4 --edit word:introduction

# Regex match (case-insensitive); keep matched lines
auto-editor talk.mkv --edit "subtitle:pattern=(yes|no),ignore-case=#t"

# Cut filler words instead of keeping them: invert with `not`
auto-editor video.mp4 --edit "(not word:um)"
```

### Transcribe → cut workflow

When the media has no subtitle stream, generate a **sidecar** named after the
input — for `talk.mp4`, auto-editor auto-loads `talk.srt` (then `talk.ass`) when
the requested subtitle stream isn't embedded:

```bash
auto-editor whisper talk.mp4 ggml-medium.en.bin --format srt -o talk.srt
auto-editor talk.mp4 --edit word:question        # picks up talk.srt automatically
```

Inspect subtitle streams with `auto-editor subdump FILE` (text subtitles only;
bitmap subtitles won't dump).

For loudness/motion-based cutting and pace, see the **auto-editor** skill.
