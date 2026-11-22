# 31.9.1

## Major

## Features
 - Timeline markers. `--marker` adds a named point or span (`--marker 30sec,Intro`) that follows the edit through cuts. Markers are carried into editor exports, read when importing FCP7 XML, FCPXML and EDL, and written as chapters by default (`--no-chapters` turns that off).
 - `whisper --language` takes three-letter codes, tags like `en-US`, and language names. An unknown language is now an error.
 - With an explicit `--output`, retimed subtitle sidecars are named after the output and written beside it (`video.en.srt` with `-o out/final.mp4` gives `out/final.en.srt`).
 - `--output` can be a device or pipe, like `/dev/null`, `/dev/stdout`, or `>(cmd)`. MP4 sent to a pipe is fragmented so it plays.
 - Time ranges take clock time (`1:30`, `1:02:03.5`) and timecode (`00:01:30:00`, or `;` for drop frame), and `f` marks a frame count (`30f`).

## Performance
 - Rendering transitions is faster.
 - Rendering keeps fewer copies of each clip's audio.
 - The video encoder uses every CPU core, and VP9 also encodes rows in parallel.
 - Audio is encoded on its own thread.
 - Motion analysis is faster.

## Fixes
 - An input with no audio stream, like a still image, is treated as silent by `--edit audio` instead of failing the edit.
 - A still-image layer is laid as one clip, so its animations no longer restart at every cut.
 - Fixed vertical `text` with ASS tags, and `text` actions that didn't round-trip through timeline files.
 - Fixed out-of-bounds reads when burning in subtitles and when matching regexes against truncated UTF-8.
 - Non-ASCII track languages no longer produce invalid UTF-8 in v3 exports.
 - The `word` method matches words and phrases that begin or end with punctuation, like `really?`.
 - A mono source on a stereo timeline plays in both channels instead of only the left.
 - Opus output keeps the right pitch when the source's sample rate isn't one Opus takes.
 - Embedded subtitles are retimed by each clip's speed.
 - Motion and black-frame detection line up with the audio on files that don't start at zero, like MPEG-TS.
 - FCPXML exports with more than one source give each clip its own length and name.

# Misc.
 - FFmpeg is updated to 9.1.
 - The Windows binaries are now signed.
 - On macOS, AAC audio uses Apple's encoder by default.
 - Track languages are stored as ISO 639-2/T codes. Two-letter codes, tags like `en-US`, and the ISO 639-2/B forms map to them (`en` and `en-US` give `eng`, `fre` gives `fra`), so MP4 outputs keep their language tags.

