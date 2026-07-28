# 31.4.0

## Major
 -

## Features
 - Support partial-lossless rendering for H.264, HEVC, and VP9. Complete GOPs are copied without re-encoding, while fragments touching edit points are re-encoded. Use `--no-partial-lossless` to opt-out.
 - Add support for WebCodecs-based H.264, HEVC, AV1, VP8, VP9, and AAC encoding for WebAssembly builds.
 - Add `--webcodecs` to enable browser WebCodecs decoding in WebAssembly builds.
 - Support the `--` end-of-options separator in all subcommands.

## Performance
 - Speed up scaled video rendering by reusing a persistent scaling context.
 - Reduce allocations and reuse media resources during rendering.

## Fixes
 - Fix first-time URL downloads failing when no cached download exists.
 - Fix several minor decoder, container, and rendering resource leaks.
 - Fix motion and audio analysis for media whose decoded frames lack presentation timestamps.
 - Fix edit-expression token handling for apostrophes and missing values.

## Misc.
 - Unlicensed single-source rendering is supported through 3200×1800; higher resolutions require a license key.
 - Unlicensed multi-source media can render up to SD instead of being rejected; multi-source timeline exports still require a license key.
