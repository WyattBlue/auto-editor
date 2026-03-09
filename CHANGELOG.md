# 30.0.0

## Major
 - The cli will no longer open media files by default. Use the `--open` flag to restore the old behavior.
 - If you have purchased an Auto-Editor license, you may now use multiple inputs `auto-editor a.mp4 b.mp4` and they will be concatenated into a single output, with silence detection applied to each input independently.

## Features
 - Add `--set-action`.
 - whisper: Add `--language`, `--translate`, `--threads`.

## Fixes
 - whisper: enable BLAS on MacOS for speedup when not using GPU.
 - whisper: Downscale samplerate to 16k for better accuracy 
