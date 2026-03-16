# 30.0.0

This is a big release with big changes. The most important being going forward, certain releases may require a license key to work. While these are the same license keys used in the proprietary [GUI](https://app.auto-editor.com), the auto-editor cli (and all of its components) remains open source. I call this the FOSSIL model, FOSS + (I)ntegrated (L)icense keys, and I'll explain more of the details in an upcoming blog post.

## Major
 - If you have purchased an Auto-Editor license, you may now use multiple inputs `auto-editor a.mp4 b.mp4` and they will be concatenated into a single output, with silence detection applied to each input independently.
 - Will no longer open media files by default. Use the `--open` flag to restore the old behavior.
 - Will no longer handle options with underscores. Use dashes instead. e.g. `--sample_rate` -> `sample-rate`
 - Add `--smooth` for setting mincut and minclip respectively. It will apply them with equal precedence. `--edit audio:mincut=,minclip=` is no supported.

## Features
 - Add `--set-action`. Allows adding any action anywhere, and is preferred over video/silent speed.
 - whisper: Add `--language`, `--translate`, `--threads`.

## Fixes
 - whisper: enable BLAS on MacOS for speedup when not using GPU.
 - whisper: Downscale samplerate to 16k for better accuracy.
 - Fix wrong colors when encoding HDR content with `hevc_videotoolbox`.
 - Improve audio rendering performance for single channel streams.
 - Improve audio rendering for exotic layouts (do: 7.1 -> 7.1 instead of: 7.1 -> stereo -> 7.1).
