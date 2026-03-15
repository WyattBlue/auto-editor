# 30.0.0

## Major
 - If you have purchased an Auto-Editor license, you may now use multiple inputs `auto-editor a.mp4 b.mp4` and they will be concatenated into a single output, with silence detection applied to each input independently.
 - Will no longer open media files by default. Use the `--open` flag to restore the old behavior.
 - Will no longer handle options with underscores. Use dashes instead. e.g. `--sample_rate` -> `sample-rate`

## Features
 - Add `--set-action`. Allows adding any action anywhere, and is preferred over video/silent speed.
 - whisper: Add `--language`, `--translate`, `--threads`.

## Fixes
 - whisper: enable BLAS on MacOS for speedup when not using GPU.
 - whisper: Downscale samplerate to 16k for better accuracy.
 - Fix wrong colors when encoding HDR content with `hevc_videotoolbox`.
 - Improve audio rendering performance for single channel streams.
 - Improve audio rendering for exotic layouts (do: 7.1 -> 7.1 instead of: 7.1 -> stereo -> 7.1).
