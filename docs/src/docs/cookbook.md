---
title: Cookbook
---

Short, practical recipes for getting started with auto-editor. Each one is a
command you can copy, paste, and tweak. Replace `video.mp4` with your own file.

## The simplest edit

Cut out the silent "dead space" automatically. This is all you need to start:

```sh
auto-editor video.mp4
```

The result is written to `video_ALTERED.mp4`. To name it yourself, use `-o`:

```sh
auto-editor video.mp4 -o trimmed.mp4
```

## Smooth the cuts with dissolves

Blend each kept section into the next instead of jump-cutting, with a fade in
at the start and a fade out at the end:

```sh
auto-editor video.mp4 --transition dissolve:0.5sec
```

By default, cuts that removed less than a second of material stay hard so
short silence trims don't stutter. Use `:0` to dissolve at every cut:

```sh
auto-editor video.mp4 --transition dissolve:0.5sec:0
```

Transitions survive editor exports too — see [Transitions](./transition).

## Record and edit a microphone

Use `:mic` in place of an input file to capture from a microphone. Press
Ctrl-C when you are done recording; auto-editor will then remove the quiet
sections and write `mic_ALTERED.wav`:

```sh
auto-editor :mic
```

All normal editing and output options apply. For example:

```sh
auto-editor :mic --edit audio:threshold=6% -o trimmed.m4a
```

Use `--sample-rate` to resample the recording before it is edited:

```sh
auto-editor :mic --sample-rate 44.1kHz
```

Timeline and editor exports save the microphone capture as a lossless FLAC
stream in `*_RECORDING.mka`. Use `-c:a` to choose a different codec supported
by Matroska:

```sh
auto-editor :mic --export resolve -c:a opus -o interview.fcpxml
```

Live microphone capture is supported on macOS, Windows, and Linux. Timeline
and editor exports keep the original capture in a sibling
`*_RECORDING.mka` file so the exported project can still reference it.

## Look before you render

See how much will be cut without producing a file yet:

```sh
auto-editor video.mp4 --preview
```

## Make the pace feel natural

By default auto-editor keeps `0.2` seconds of padding around each kept section
so cuts don't feel abrupt. Widen it to let speech breathe, or use different
padding before and after:

```sh
# 0.5 seconds of padding on both sides
auto-editor video.mp4 --margin 0.5sec

# 0.3s before, 1.5s after
auto-editor video.mp4 --margin 0.3sec,1.5sec
```

## Cut more (or less) aggressively

`--edit` decides what counts as "loud enough" to keep. Raise the threshold to
cut more, lower it to keep more. You can use a percentage or a `dB` value:

```sh
# Keep only louder audio (cuts more)
auto-editor video.mp4 --edit audio:threshold=6%

# The same idea in decibels
auto-editor video.mp4 --edit audio:-18dB
```

To analyze one channel instead of the loudest sample across all channels, use
its layout name:

```sh
auto-editor video.mp4 --edit audio:channel=left
```

Channel names are layout-aware (`left`, `right`, `center`, `lfe`,
`back-left`, and so on). A mono channel acts as left, right, and center. With
`stream=all`, streams without the requested channel are skipped as long as at
least one stream contains it.

## Cut by motion instead of sound

Useful for screen recordings or silent footage — drop the still parts:

```sh
auto-editor video.mp4 --edit motion:threshold=2%
```

## Speed through silence instead of cutting it

Keep every moment, but fast-forward the quiet parts:

```sh
auto-editor video.mp4 -w:0 speed:8
```

See the [Actions Cookbook](./actions) for volume, zoom, overlays, and more.

## Trim the beginning or end

```sh
# Drop the first and last 30 seconds, on top of the automatic edit
auto-editor video.mp4 --cut-out start,30sec -30sec,end
```

More in [Range Syntax](./range-syntax).

## Edit by what was said

Transcribe speech, then cut on the words. First make subtitles, then edit with
them:

```sh
auto-editor whisper video.mp4 ggml-medium.en.bin --format srt -o video.srt
auto-editor video.mp4 --edit subtitle
```

Auto-Editor understands `video.srt` is related to `video.mp4`. See the [whisper command](./subcommands/whisper) for more details.

## Hand off to your video editor

Instead of rendering, export a project you can open in your editor:

```sh
auto-editor video.mp4 --export premiere
```

Auto-editor can also export to `resolve`, `final-cut-pro`, `shotcut`, and
`kdenlive`. To get each kept section as its own file, use `clip-sequence`:

```sh
auto-editor video.mp4 --export clip-sequence
```

## Edit straight from a URL

If [yt-dlp](https://github.com/yt-dlp/yt-dlp) is installed, pass a link as the
input:

```sh
auto-editor "https://www.youtube.com/watch?v=kcs82HnguGc"
```

## See Also
- [How to Shrink File Size](./file-size)
- [All the Options (and What They Do)](/ref/options)

<a class="next" href="./actions">Next: Actions Cookbook</a>
