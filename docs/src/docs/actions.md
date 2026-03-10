---
title: Actions
---

# Actions

Actions define what auto-editor does to different parts of your media. By default, inactive (silent) sections are cut out and active (loud) sections are kept unchanged. Actions give you fine-grained control over this behavior.

## Basic Syntax

Actions are specified using the `--when-silent` and `--when-normal` options:

```bash
# Cut silent sections (default behavior)
auto-editor video.mp4 --when-silent cut

# Keep normal sections unchanged (default behavior)
auto-editor video.mp4 --when-normal nil
```

These options have aliases:
- `--when-silent` = `--when-inactive`, `-w:0`
- `--when-normal` = `--when-active`, `-w:1`

## Available Actions

### nil
**Syntax:** `nil`

Do nothing. Keep the section unchanged at normal speed with normal pitch.

```bash
# Keep everything, even silent sections
auto-editor video.mp4 --when-silent nil
```

### cut
**Syntax:** `cut`

Remove the section completely from the output.

```bash
# Remove silent sections (default behavior)
auto-editor video.mp4 --when-silent cut

# Remove loud sections (inverted editing)
auto-editor video.mp4 --when-normal cut
```

### speed
**Syntax:** `speed:<value>`

Change the playback speed while preserving pitch using time-stretching.
- **Value range:** 0.0 to 99999.0

```bash
# Speed up silent sections to 8x (preserving pitch)
auto-editor video.mp4 --when-silent speed:8

# Slow down normal sections to half speed
auto-editor video.mp4 --when-normal speed:0.5
```

**How it works:** Uses FFmpeg's `atempo` filter to change speed without affecting pitch.

### varispeed
**Syntax:** `varispeed:<value>`

Change the playback speed by varying pitch, like analog tape or vinyl.
- **Value range:** 0.2 to 100.0

```bash
# Speed up silent sections with pitch variation
auto-editor video.mp4 --when-silent varispeed:2

# Create slow-motion effect with lower pitch
auto-editor video.mp4 --when-normal varispeed:0.5
```

**How it works:** Uses FFmpeg's `asetrate` + `aresample` filters to change sample rate, which changes both speed and pitch together.

### volume
**Syntax:** `volume:<value>`

Adjust the audio volume level.
- **1.0** = normal volume
- **0.5** = half volume (-6dB)
- **2.0** = double volume (+6dB)

```bash
# Reduce silent section volume to 20%
auto-editor video.mp4 --when-silent volume:0.2

# Boost loud sections
auto-editor video.mp4 --when-normal volume:1.5
```

### invert
**Syntax:** `invert`

Invert all pixels in the video section.

```bash
auto-editor video.mp4 --when-silent invert
```

### zoom
**Syntax:** `zoom:<value>`

Zoom in or out by a factor.
- **Value range:** greater than 0.0, up to 100.0
- **1.0** = no zoom

```bash
# Zoom in 2x on active sections
auto-editor video.mp4 --when-normal zoom:2

# Zoom out on silent sections
auto-editor video.mp4 --when-silent zoom:0.5
```

## Multiple Actions (Chaining)

You can combine multiple actions using commas. Actions are applied in the order specified.

```bash
# Speed up AND reduce volume
auto-editor video.mp4 --when-silent speed:3,volume:0.5

# Combine speed and varispeed
# Effective speed: 1.25 × 1.25 = 1.5625x
auto-editor video.mp4 --when-normal varispeed:1.25,speed:1.25

# Triple action: speed, varispeed, and volume
auto-editor video.mp4 --when-silent speed:2,varispeed:1.5,volume:0.8
```

## Setting Actions for a Time Range

Use `--set-action` to apply an action to a specific time range, overriding the default actions:

```bash
# Keep a section unchanged from 0 to 5 seconds
auto-editor video.mp4 --set-action nil,0,5sec

# Apply speed + varispeed from 30 seconds to the end
auto-editor video.mp4 --set-action speed:1.5,varispeed:1.5,30sec,end
```

The format is `ACTION,START,END` where `ACTION` can be any action or comma-separated list of actions.

## Common Use Cases

### Fast-Forward Through Silence
```bash
auto-editor video.mp4 --when-silent speed:8
```

### Subtle Speed Variations
```bash
# Slightly slow down normal sections for emphasis
auto-editor video.mp4 --when-normal speed:0.9
```

### Duck Audio During Silence
```bash
# Keep silent sections but reduce volume
auto-editor video.mp4 --when-silent volume:0.3
```

### Podcast Editing
```bash
# Cut silence, slightly speed up speech
auto-editor podcast.mp3 --when-silent cut --when-normal speed:1.15
```

### Music Editing
```bash
# Keep everything but boost quiet parts
auto-editor song.mp3 --when-silent volume:1.8 --when-normal volume:1.0
```

### Creative Effects
```bash
# Nightcore effect: speed up and pitch up
auto-editor video.mp4 --when-normal varispeed:1.25

# Slow-mo with deep voice
auto-editor video.mp4 --when-normal varispeed:0.75

# Fast silent sections with reduced volume
auto-editor video.mp4 --when-silent speed:6,volume:0.4
```

## Deprecated Options

The following options are deprecated but still supported:

```bash
# Old way (deprecated)
auto-editor video.mp4 --silent-speed 8 --video-speed 1

# New way (preferred)
auto-editor video.mp4 --when-silent speed:8 --when-normal speed:1
```

## See Also
- [Range Syntax](./range-syntax) - Manual editing with `--cut-out` and `--add-in`
- [Audio Normalization](./anorm) - Volume normalization options
