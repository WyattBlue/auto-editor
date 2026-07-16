# 31.2.1

## Major
 - Added first-class linked video/audio dissolve transitions with `--transition dissolve:DURATION[:MIN-CUT]`. Auto-Editor adds cross-dissolves at eligible cuts and fades at the timeline endpoints; cuts shorter than `MIN-CUT` are skipped (default: `1sec`). Formats that cannot represent transitions (`v1`, `v2`, `clip-sequence`) drop them and keep the cuts.
 - The v3 timeline format can now store and render transitions, and every editor export preserves them natively: Premiere OTIO/FCP7 XML, Final Cut Pro and Resolve FCPXML (Cross Dissolve spine transitions), and Shotcut/Kdenlive MLT (same-track transitions/mixes plus edge fades).

## Features
 - Support the end-of-options marker (`--`) in the CLI.
 - Added the `apple` transcription model to the `whisper` subcommand, using Apple's SpeechAnalyzer (macOS 26+ only).
 - Create retimed `_ALTERED` sibling subtitles.
 - Support named audio channel analysis with `--edit audio:channel=NAME`.
 - Preserve volume, de-essing, invert, flips, erosion, blur, color adjustments,
   lens correction, drawbox, pixelation, and chromatic aberration actions in
   Kdenlive and Shotcut exports.
 - Animated `volume` and `blur` ramps (including easing) survive Kdenlive and
   Shotcut exports as MLT keyframe animations instead of collapsing to their
   first value.
 - Support NVIDIA Parakeet models in the `whisper` subcommand, including
   `--split-words` with word timestamps from the TDT decoder. Models:
   https://huggingface.co/ggml-org/parakeet-GGUF
 - Upgrade whisper.cpp to v1.9.1.

## Performance
 - Vectorize motion pixel comparison with NEON, SSE2, and WebAssembly SIMD.

## Fixes
 - Fatal errors no longer dump a ggml backtrace after the error message when a
   model fails to load; auto-editor now exits cleanly with code 1.
