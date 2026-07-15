# 31.2.1

## Major
 - Added first-class linked video/audio dissolve transitions with `--transition dissolve:DURATION[:MIN-CUT]`. Auto-Editor adds cross-dissolves at eligible cuts and fades at the timeline endpoints; cuts shorter than `MIN-CUT` are skipped (default: `1sec`).
 - The v3 timeline format can now store and render transitions, and Premiere OTIO/FCP7 exports preserve them as native editor transitions.

## Features
 - Support the end-of-options marker (`--`) in the CLI.
 - Added the `apple` transcription model to the `whisper` subcommand, using Apple's SpeechAnalyzer (macOS 26+ only).
 - Create retimed `_ALTERED` sibling subtitles.
 - Support named audio channel analysis with `--edit audio:channel=NAME`.
 - Preserve volume, de-essing, invert, flips, erosion, blur, color adjustments,
   lens correction, drawbox, pixelation, and chromatic aberration actions in
   Kdenlive and Shotcut exports.

## Performance
 - Vectorize motion pixel comparison with NEON, SSE2, and WebAssembly SIMD.

## Fixes
 -
