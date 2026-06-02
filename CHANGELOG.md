# 30.4.1

## Major
 -

## Features
 - Add AMD AMF hardware encoders (`h264_amf`, `hevc_amf`, `av1_amf`) for x86_64 Windows and Linux builds.
 - Show an indeterminate progress bar when the duration is unknown, instead of a misleading percentage.

## Performance
 - Skip demuxing unused streams during audio analysis and rendering, which is significantly faster when working with high-bitrate video files.
 - Speed up audio loudness analysis with a faster SIMD peak scan (NEON, SSE2, and WebAssembly SIMD).

## Fixes
 -
