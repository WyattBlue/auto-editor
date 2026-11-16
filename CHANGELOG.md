# 31.9.1

## Major
 - Track languages are stored as ISO 639-2/T codes. Two-letter codes, tags like `en-US`, and the ISO 639-2/B forms map to them (`en` and `en-US` give `eng`, `fre` gives `fra`), so MP4 outputs keep their language tags. A code that isn't ISO 639 gives `und`.

## Features
 - The `text` action takes `:ass`, which reads the text as raw ASS override tags, including in vertical layout.
 - `whisper --language` takes three-letter codes, tags like `en-US`, and language names. An unknown language is now an error.
 - With an explicit `--output`, retimed subtitle sidecars are named after the output and written beside it (`video.en.srt` with `-o out/final.mp4` gives `out/final.en.srt`).

## Performance
 - Rendering transitions is faster.
 - Rendering keeps fewer copies of each clip's audio.
 - The Windows x86_64 binary is about 3 MB smaller.

## Fixes
 - Exporting certain timeline formats to a path that can't be written reports an error instead of crashing.
 - An input with no audio stream, like a still image, is treated as silent by `--edit audio` instead of failing the edit.
 - A clip naming an audio or video stream its source lacks reports an error instead of crashing.
 - Shotcut and Kdenlive exports no longer crash on clips with no source.
 - A still-image layer is laid as one clip, so its animations no longer restart at every cut.
 - Fixed vertical `text` with ASS tags, and `text` actions that didn't round-trip through timeline files.
 - Fixed out-of-bounds reads when burning in subtitles and when matching regexes against truncated UTF-8.
 - Non-ASCII track languages no longer produce invalid UTF-8 in v3 exports.

# Misc.
 - The Windows binaries are signed
