---
title: Auto-Editor - Cookbook
---

# Cookbook

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
