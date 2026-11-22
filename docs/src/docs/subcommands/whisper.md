---
title: whisper
---

`whisper` transcribes the audio of a media file using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) `ggml` models. It is useful both on its own and for generating subtitles that `--edit subtitle` can then cut on.

Usage:
```
auto-editor whisper <file|:mic> <model> [options]
```

`<model>` is a path to a `ggml` whisper model. You can download them from [huggingface.co/ggerganov/whisper.cpp](https://huggingface.co/ggerganov/whisper.cpp).

Example:
```
% auto-editor whisper example.mp4 ggml-medium.en.bin

 And so my fellow Americans, ask not what your country can do for you,
 ask what you can do for your country.
```

By default the transcript is written to stdout as plain text. Use `--output` to write to a file; its extension (`.srt`, `.json`, or `.txt`) picks the format:
```sh
auto-editor whisper example.mp4 ggml-medium.en.bin -o out.srt
```

## Options

### `<file>`
The input media file, or `:mic` to transcribe the microphone live. Only the first audio stream is used; the audio is resampled to 16kHz (whisper's preferred rate) before transcription.

### `<model>`
Path to a `ggml` whisper model, e.g. `ggml-small.en.bin` or `ggml-large-v2.bin`. A [parakeet](https://huggingface.co/ggml-org/parakeet-GGUF) model works too, though it detects the language itself and doesn't take `--language`, `--translate`, or `--prompt`. On macOS 26 and later, `apple` uses the system's built-in transcriber, which doesn't take `--translate` or `--prompt`.

### `-l, --language LANG`
Set the spoken language instead of letting whisper auto-detect it: a code like `en`, `eng`, or `en-US`, or an English name like `english`. A language whisper doesn't know is an error. With the `apple` model, give a locale like `en_US`. (default `auto`)

### `-f, --format FORMAT`
Set the output format. Choices are `text`, `srt`, and `json`. Only needed to override the format `--output`'s extension picks. (default `text`)

### `-o, --output FILE`
Where to write the transcript. (defaults to stdout)

### `-tr, --translate`
Translate from the source language to English.

### `-sw, --split-word, --split-words`
Output one word per cue instead of full segments.

### `--queue SECS`
The maximum length in seconds of a single transcribed segment. Must be between 1 and 86400. (default 30)

### `--prompt TEXT`
Bias transcription toward given vocabulary or spelling, such as names and jargon.

### `-t, --threshold THRES`
The loudness (0-1) below which audio is treated as silence and skipped, like the `audio` edit method. (default 0.04)

### `--threads N`
Number of CPU threads to use for whisper processing. (default 4)

### `--debug`
Show debugging messages and values.

---
### Notes
`whisper` needs a build of auto-editor with whisper.cpp support. Without it, whisper reports that `This build of auto-editor has no whisper support`.

<a class="next" href="/docs/v1">Next: The v1 timeline format</a>
