# 30.4.1

## Major
 -

## Features
 - Composite multiple video layers into one output: a v3 JSON timeline with stacked `v` tracks is now rendered bottom-to-top, with each overlay clip placed by a `pos` action in its effects. Still images (PNG/JPG/...) are supported as overlay sources (logos, watermarks), and overlay alpha is preserved.
 - Add the following actions: `drawbox`, `pos` (overlay placement, `pos:x:y[:scale]`), `rotate` with syntax `rotate:deg/rate`
 - Add the `add` virtual action, `add:path` or `add:path:x:y:scale`
 - Add animated effects: `zoom`, `opacity`, `blur`, and `brightness` accept keyframe ramps (`a..b..c`) that interpolate across the section, with optional easing via `:ease=curve[:duration]` (curve `linear`/`in`/`out`/`inout`, duration e.g. `2sec`). A standalone `ease:` token applies a curve to the animated actions that follow it.
 - Add AMD AMF hardware encoders (`h264_amf`, `hevc_amf`, `av1_amf`) for x86_64 Windows and Linux builds.
 - Show an indeterminate progress bar when duration of analysis is unknown.

## Performance
 - Skip demuxing unused streams during audio analysis and rendering, which is significantly faster when working with high-bitrate video files.
 - Speed up audio loudness analysis with a faster SIMD peak scan (NEON, SSE2, and WebAssembly SIMD).
 - Render audio as a bounded stream instead of assembling the whole timeline into a memory-mapped buffer first. Memory now scales with the largest clip rather than the total duration, which especially helps memory-constrained environments like WebAssembly. Normalization (`peak`/`ebu`) decodes the timeline twice to stay streaming.

## Fixes
 - Fix `whisper` subtitle timestamps being wrong (scaled by the ratio of the stream time base to the sample rate) by passing the stream's time base to the audio buffer source.
