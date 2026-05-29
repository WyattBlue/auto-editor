---
title: whisper
---

## whisper
`whisper` transcribes the audio of a media file using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) `ggml` models. It is useful both on its own and for generating subtitles that `--edit subtitle` can then cut on.

Usage:
```
auto-editor whisper <file> <model> [options]
```

`<model>` is a path to a `ggml` whisper model. You can download them from [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp).

Example:
```
% auto-editor whisper example.mp4 ggml-medium.en.bin

 And so my fellow Americans, ask not what your country can do for you,
 ask what you can do for your country.
```

By default the transcript is written to stdout as plain text. Use `--output` to write to a file and `--format` to choose the representation:
```
auto-editor whisper example.mp4 ggml-medium.en.bin --format srt -o out.srt
```

## Options

### `<file>`
The input media file. Only the first audio stream is used; the audio is resampled to 16kHz (whisper's preferred rate) before transcription.

### `<model>`
Path to a `ggml` whisper model, e.g. `ggml-small.en.bin` or `ggml-large-v2.bin`.

### `-l, --language LANG`
Set the spoken language instead of letting whisper auto-detect it. Examples: `en`, `ja`. (default `auto`)

### `--format FORMAT`
Set the output format. Choices are `text`, `srt`, and `json`. (default `text`)

### `-o, --output FILE`
Where to write the transcript. (defaults to stdout)

### `-tr, --translate`
Translate from the source language to English.

### `-sw, --split-words`
Split the output so that each token is at most one word long.

### `--queue SECS`
The maximum amount of audio (in seconds) queued before processing. Must be between 1 and 86400. (default 30)

### `--vad-model VAD-MODEL`
Set a Voice Activity Detection (VAD) model.

### `--threads N`
Number of CPU threads to use for whisper processing. (default 4)

---
### Notes
The `whisper` filter must be enabled in the ffmpeg auto-editor is using. If it isn't, whisper will report that it `Could not find whisper filter`.
