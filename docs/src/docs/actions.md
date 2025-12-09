---
title: Actions
---

# Actions

Actions define what auto-editor does to different parts of your media. By default, silent sections are cut out and loud sections are kept at normal speed. Actions give you fine-grained control over this behavior.

## Basic Syntax

Actions are specified using the `--when-silent` and `--when-normal` options:

```bash
# Cut silent sections (default behavior)
auto-editor video.mp4 --when-silent cut

# Keep normal sections unchanged (default behavior)
auto-editor video.mp4 --when-normal nil
```

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
- **Typical range:** 0.5 to 3.0

```bash
# Speed up silent sections to 8x (preserving pitch)
auto-editor video.mp4 --when-silent speed:8

# Slow down normal sections to half speed
auto-editor video.mp4 --when-normal speed:0.5
```

**How it works:** Uses FFmpeg's `atempo` filter to change speed without affecting pitch. This is like a DJ's time-stretching feature.

### varispeed
**Syntax:** `varispeed:<value>`

Change the playback speed by varying pitch, like analog tape or vinyl.
- **Value range:** 0.2 to 100.0
- **Typical range:** 0.5 to 2.0

```bash
# Speed up silent sections with pitch variation
auto-editor video.mp4 --when-silent varispeed:2

# Create slow-motion effect with lower pitch
auto-editor video.mp4 --when-normal varispeed:0.5
```

**How it works:** Uses FFmpeg's `asetrate` filter to change sample rate, which changes both speed and pitch together. This is the classic tape speed effect.

### volume
**Syntax:** `volume:<value>`

Adjust the audio volume level.
- **Value range:** Any positive float
- **1.0** = normal volume
- **0.5** = half volume (-6dB)
- **2.0** = double volume (+6dB)

```bash
# Reduce silent section volume to 20%
auto-editor video.mp4 --when-silent volume:0.2

# Boost loud sections
auto-editor video.mp4 --when-normal volume:1.5
```

## Multiple Actions (Chaining)

You can combine multiple actions using commas. Actions are applied in the order specified and their effects multiply together.

```bash
# Speed up AND reduce volume
auto-editor video.mp4 --when-silent speed:3,volume:0.5

# Combine speed and varispeed for complex effects
# Effective speed: 1.25 × 1.25 = 1.5625x
auto-editor video.mp4 --when-normal varispeed:1.25,speed:1.25

# Triple action: speed, varispeed, and volume
auto-editor video.mp4 --when-silent speed:2,varispeed:1.5,volume:0.8
```

### How Speed Multiplies

When you combine `speed` and `varispeed`, their effects multiply:

```bash
# These combinations give you fine control:
varispeed:1.25,speed:1.25  # = 1.5625x total speed
varispeed:2,speed:0.5      # = 1x speed (varispeed pitch, normal speed)
speed:2,speed:1.5          # = 3x total speed
```

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

### Creative Effects
```bash
# Nightcore effect: speed up and pitch up
auto-editor video.mp4 --when-normal varispeed:1.25

# Slow-mo with deep voice
auto-editor video.mp4 --when-normal varispeed:0.75

# Fast silent sections with reduced volume
auto-editor video.mp4 --when-silent speed:6,volume:0.4
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

## Deprecated Options

The following options are deprecated but still supported:

```bash
# Old way (deprecated)
auto-editor video.mp4 --silent-speed 8 --video-speed 1

# New way (preferred)
auto-editor video.mp4 --when-silent speed:8 --when-normal speed:1
```

## Technical Details

### Audio Processing
- **speed:** Uses `atempo` filter, supports values 0.5-100.0 per stage
- **varispeed:** Uses `asetrate` + `aresample`, range 0.2-100.0
- **volume:** Uses `volume` filter, any positive value

### Video Processing
- Both `speed` and `varispeed` affect video frame selection
- Effects multiply together for combined speed calculations
- Video is resampled to match the effective playback speed

### Filter Chain Order
When using multiple actions, they're applied in this order:
1. `speed` (time-stretching)
2. `varispeed` (sample rate change)
3. `volume` (gain adjustment)

This order ensures optimal audio quality.

## Examples by Category

### Speed Variations
```bash
# Subtle speedup
auto-editor video.mp4 --when-normal speed:1.1

# Aggressive silence removal
auto-editor video.mp4 --when-silent speed:99999
# (speed:99999 is equivalent to cut)

# Complex speed layering
auto-editor video.mp4 --when-normal speed:1.2,varispeed:1.1
```

### Volume Control
```bash
# Normalize loud/quiet sections
auto-editor video.mp4 --when-silent volume:2 --when-normal volume:0.8

# Ducking effect
auto-editor video.mp4 --when-silent volume:0.1
```

### Creative Combinations
```bash
# Chipmunk effect on silence
auto-editor video.mp4 --when-silent varispeed:2,volume:1.2

# Deep voice on normal sections
auto-editor video.mp4 --when-normal varispeed:0.7

# Fast and quiet silence
auto-editor video.mp4 --when-silent speed:10,volume:0.2
```

## See Also
- [Range Syntax](./range-syntax) - Manual editing with `--cut-out` and `--add-in`
- [Audio Normalization](./anorm) - Volume normalization options
