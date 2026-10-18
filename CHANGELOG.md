# 31.7.3

## Major
 -

## Features
 - New `burn` action/generator: draws a subtitle file (.srt, .ass, or a file's text stream) over a section or on its own layer, e.g. `add:burn:talk.srt`, with overrides for font, size, colors, and alignment.
 - New `text` action/generator: writes text over a section or on its own layer, e.g. `add:text:Chapter 1`, with the same overrides and an optional vertical layout.

## Performance
 -

## Fixes
 - WebP images, still and animated, can again be used as inputs. Required enabling FFmpeg's vp8 decoder.
 - RGB sources keep their colors when encoded to YUV, instead of a strong green/purple shift (#1289).
 - Runs on older x86_64 CPUs. Checks for SSE4.2 when it runs, rather than requiring it, which crashed CPUs without them.
 - A sample aspect ratio set by the container (an MP4 `pasp` box, Matroska) is kept, in `info` and in renders. Before, only the one in the video bitstream was used.
 - A video-only file whose stream has no duration of its own, like Matroska, no longer gives an empty timeline.
 - Copying H.264 from Matroska with B-frames no longer fails with "Could not write packet: Invalid argument".

# Misc.
 - Can be now be used as a Nim library, without going through command-line strings.
 - Use whisper.cpp 1.9.5.
