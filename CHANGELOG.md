# 30.1.0

## Major
 -

## Features
 - Use FFmpeg 8.1.
 - Add setting Constant Rate Factor: `-crf`.
 - Add `--no-cache` to main program.
 - Add `-encoders` to info command.
 - Build whisper-cpp for Windows AArch64.

## Fixes
 - Implement Neon SIMD for readChunk proc (audio). Makes audio analysis faster by 10% for AArch64.
 - Use SvtAv1 4.1.0.
