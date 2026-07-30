# 31.4.1

## Major
 -

## Features
 - Add support for partial lossless AV1 too.

## Performance
 -

## Fixes
 - Keep internal-only commands out of generated zsh completions.
 - Improve `--edit` error messages by reporting the expected and received argument counts.
 - Fix inaccurate seeks in long videos with fractional frame rates by converting frame positions to timestamps with rational arithmetic.
 - Fix H.264 partial-lossless rendering when Matroska omits the first copied packet’s DTS.
 - Round time-based edit settings and ranges to the nearest frame, preventing NTSC margins and smoothing thresholds from being one frame shorter than non-NTSC.
 - Keep adjacent audio clips contiguous at fractional frame rates by deriving their sample durations from absolute sample boundaries.
