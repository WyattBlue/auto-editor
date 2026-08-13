# 31.5.0

## Major
 -

## Features
 - Add the `confetti` action.
 - Let `add:` name `confetti` in place of a file, drawing it onto a transparent layer over the picture instead of baking it in
 - Add the `pitch` action to shift a section by -24 to 24 semitones without changing its speed or duration.
 - Add `-g`/`--gop` to set the maximum number of frames between keyframes.
 - Stack multiple effects on one clip when exporting fcp7 XML.
 - Update the bundled FFmpeg to 9.0.1.

## Performance
 - Let the per-frame libswscale contexts use every core.

## Fixes
 - Pick `mp4` for the default output name when the timeline gains a video track a container cannot hold, instead of writing an audio-only file and silently dropping video.
 - Use a one second GOP for fragmented output.

# Misc.
 - Support both FFmpeg 8.1 and 9.0.
 - Drop the AVX-512 code paths from the bundled x264, x265, libvpx, and SVT-AV1 on [Intel macOS](https://basswood.io/blog/sunsetting-intel-macos).
