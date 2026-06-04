# 30.4.1

## Major
 -

## Features
 - Add the `rotate` action, which rotates the picture clockwise about its center, filling the exposed corners with the background color. `rotate:deg` is a fixed angle; `rotate:deg/rate` spins continuously at `rate` degrees per second (driven by ffmpeg's per-frame time expression).
 - Add animated effects: `zoom`, `opacity`, `blur`, and `brightness` accept a ramp (`from..to`) that interpolates across the section. An `ease` action sets the interpolation curve (`linear`/`in`/`out`/`inout`) and an optional duration (e.g. `2sec`) for the animated actions that follow it.
 - Add AMD AMF hardware encoders (`h264_amf`, `hevc_amf`, `av1_amf`) for x86_64 Windows and Linux builds.
 - Show an indeterminate progress bar when the duration is unknown, instead of a misleading percentage.

## Performance
 - Skip demuxing unused streams during audio analysis and rendering, which is significantly faster when working with high-bitrate video files.
 - Speed up audio loudness analysis with a faster SIMD peak scan (NEON, SSE2, and WebAssembly SIMD).
 - Render audio as a bounded stream instead of assembling the whole timeline into a memory-mapped buffer first. Memory now scales with the largest clip rather than the total duration, which especially helps memory-constrained environments like WebAssembly. Normalization (`peak`/`ebu`) decodes the timeline twice to stay streaming.

## Fixes
 - Fix `whisper` subtitle timestamps being wrong (scaled by the ratio of the stream time base to the sample rate) by passing the stream's time base to the audio buffer source.
