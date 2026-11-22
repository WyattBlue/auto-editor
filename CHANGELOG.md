# 31.9.1

## Major
 -

## Features
 - The `text` action takes `:ass`, which reads the text as raw ASS override tags, including in vertical layout.
 - `whisper --language` takes three-letter codes, tags like `en-US`, and language names. An unknown language is now an error.
 - With an explicit `--output`, retimed subtitle sidecars are named after the output and written beside it (`video.en.srt` with `-o out/final.mp4` gives `out/final.en.srt`).
 - `--output` can be a device or pipe, like `/dev/null`, `/dev/stdout`, or `>(cmd)`. MP4 sent to a pipe is fragmented so it plays.

## Performance
 - Rendering transitions is faster.
 - Rendering keeps fewer copies of each clip's audio.

## Fixes
 - An input with no audio stream, like a still image, is treated as silent by `--edit audio` instead of failing the edit.
 - A still-image layer is laid as one clip, so its animations no longer restart at every cut.
 - Fixed vertical `text` with ASS tags, and `text` actions that didn't round-trip through timeline files.
 - Fixed out-of-bounds reads when burning in subtitles and when matching regexes against truncated UTF-8.
 - Non-ASCII track languages no longer produce invalid UTF-8 in v3 exports.

# Misc.
 - The Windows binaries are now signed.
 - Track languages are stored as ISO 639-2/T codes. Two-letter codes, tags like `en-US`, and the ISO 639-2/B forms map to them (`en` and `en-US` give `eng`, `fre` gives `fra`), so MP4 outputs keep their language tags.

