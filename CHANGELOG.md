# 31.7.3

## Major
 -

## Features
 - New `burn` action/generator: draws a subtitle file (.srt, .ass, or a file's text stream) over a section or on its own layer, e.g. `add:burn:talk.srt`, with overrides for font, size, colors, and alignment.
 - New `text` action/generator: writes text over a section or on its own layer, e.g. `add:text:Chapter 1`, with the same overrides and an optional vertical layout.
 - `burn` without a file draws the subtitles of the media under it: its first text subtitle stream, else a .srt or .ass with the same name. They stay on their words through cuts and speed changes.
 - New `--font` option, the default font for `burn` and `text`.
 - New `scale` action: scales the picture about its center without growing the frame, e.g. `scale:0.8` or `scale:0.4:1`.
 - New `turn` action: turns the picture clockwise about its center without growing the frame, e.g. `turn:15`.
 - New `convolve` action: runs audio through an impulse response file, or a folder of H_LL/H_LR/H_RL/H_RR.wav files for true stereo.
 - `mask` and `confine` take `poly=x1/y1/x2/y2/...` for any closed polygon.
 - Keyframes can say when they are with `value@time`, in frames, `sec`, or `%` of the section, e.g. `zoom:1@0..2@1.5sec..1@100%`.
 - FCP7 XML import reads transitions as dissolves.
 - Exporting to an editor warns about the actions and tracks its format can't hold.
 - Enable the MJPEG encoder.

## Performance
 - x265 uses its assembly on arm64 for 10-bit encoding.
 - `zoom` scales only the part of the frame that stays visible and reuses its scaler, making 4K renders with zoom 1.4–1.9× faster.
 - Exporting to Premiere, Resolve, Final Cut Pro, Shotcut, and Kdenlive uses far less memory and is up to 1.6× faster. A 50,000-clip timeline peaks at 0.6 GiB instead of 2.1 GiB for Premiere, and 0.2 GiB instead of 1.6 GiB for Shotcut.
 - Importing FCP7 XML streams the file and uses about a third of the memory: a 50,000-clip Premiere XML peaks at 0.7 GiB instead of 1.8 GiB.

## Fixes
 - WebP images, still and animated, can again be used as inputs. Required enabling FFmpeg's vp8 decoder.
 - RGB sources keep their colors when encoded to YUV, instead of a strong green/purple shift (#1289).
 - Runs on older x86_64 CPUs. Checks for SSE4.2 when it runs, rather than requiring it, which crashed CPUs without them.
 - A sample aspect ratio set by the container (an MP4 `pasp` box, Matroska) is kept, in `info` and in renders. Before, only the one in the video bitstream was used.
 - A video-only file whose stream has no duration of its own, like Matroska, no longer gives an empty timeline.
 - Copying H.264 from Matroska with B-frames no longer fails with "Could not write packet: Invalid argument".
 - MJPEG video in avi/mov no longer freezes on its first frame.
 - Cover art is skipped for output formats that can't hold it.
 - Motion analysis no longer writes out of bounds when a stream changes resolution.
 - An unknown audio codec reports an error instead of crashing.
 - Subtitle cues starting before 0 no longer crash subtitle analysis.
 - Deeply nested `--edit` expressions report an error instead of overflowing the stack, and an invalid regex pattern reports an error instead of crashing.
 - Actions reject `nan` and `inf` values.
 - A speed too small to store in v1 timelines or FCP7 XML time remaps reports an error instead of hanging.
 - FCP7 XML import rejects bad integer fields, a timebase of 0, and clips that end before they start.
 - Exporting to Premiere, Resolve (FCP7 XML), Shotcut, or Kdenlive with an output path that can't be written reports an error instead of crashing.
 - FCP7 XML import reads text in CDATA sections, such as a `<pathurl>`, instead of dropping it.
 - Importing an FCP7 XML file that doesn't exist reports an error instead of crashing.

# Misc.
 - Can be now be used as a Nim library, without going through command-line strings.
 - Use whisper.cpp 1.9.5.
