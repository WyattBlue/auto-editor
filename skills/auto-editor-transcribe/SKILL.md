---
name: auto-editor-transcribe
description: Transcribe a media file's speech to text or subtitles with auto-editor's whisper subcommand, then edit by spoken content — cut to keep (or drop) sections whose subtitles match a word or regex. Use when someone wants a transcript/captions, or wants to cut a video based on what is said rather than on loudness.
---

# Transcribe & edit by speech

auto-editor wraps whisper.cpp to transcribe audio, and can cut a timeline based on subtitle content via `--edit subtitle`/`word`.

## Transcribe — `auto-editor whisper`

```
auto-editor whisper <file> <model> [options]
```

`<model>` is a path to a `ggml` whisper model e.g. `ggml-small.en.bin`, `ggml-medium.en.bin`, `ggml-large-v3.bin`. Only the first audio stream is used; it's resampled to 16 kHz first. The transcript prints to stdout by default.

```bash
auto-editor whisper example.mp4 ggml-medium.en.bin                      # plain text → stdout
auto-editor whisper example.mp4 ggml-medium.en.bin --format srt -o out.srt
```

Options: `--format text|srt|json`, `-o/--output FILE`, `-l/--language en`
(default auto), `-tr/--translate` (→ English), `-sw/--split-words` (one word per
token), `--queue SECS` (default 30), `--vad-model PATH`, `--threads N` (default 4).

> The whisper filter must be built into the ffmpeg auto-editor uses; otherwise it
> reports `Could not find whisper filter`.

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
