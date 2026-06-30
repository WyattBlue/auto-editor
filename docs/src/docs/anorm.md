---
title: Audio Normalizing
---

# Audio Normalizing

Audio normalization adjusts audio levels for consistent loudness — useful when combining sources at different volumes, or meeting a platform's loudness target.

Auto-Editor supports two kinds: **peak** scales by the highest amplitude (simple, fast, preserves dynamic range); **ebu** (EBU R128) analyzes perceived loudness over time to meet broadcast standards.

## Peak

Example:

```
auto-editor --audio-normalize peak:-3  # set max peak to -3dB
```

## EBU

Example:

```
auto-editor --audio-normalize ebu  # use default values
auto-editor --audio-normalize ebu:i=-16  # set integrated loudness target
auto-editor --audio-normalize "ebu:i=-5,lra=20,gain=5,tp=-1"  # customize all parameters
```

### Parameters

- **i** (integrated loudness): Target integrated loudness in LUFS (Loudness Units Full Scale)
  - Default: `-24.0`
  - Range: `-70.0` to `5.0`
  - Common values: `-23` (EBU R128), `-16` (streaming), `-14` (podcasts)

- **lra** (loudness range): Target loudness range in LU
  - Default: `7.0`
  - Range: `1.0` to `50.0`
  - Describes the variation between soft and loud passages

- **tp** (true peak): Maximum true peak level in dBTP
  - Default: `-2.0`
  - Range: `-9.0` to `0.0`
  - Prevents clipping during digital-to-analog conversion

- **gain**: Additional gain offset in dB
  - Default: `0.0`
  - Range: `-99.0` to `99.0`
  - Applied on top of the loudness normalization

### How It Works

EBU normalization uses a two-pass process:

1. **Analysis Pass**: Measures the integrated loudness, loudness range, and true peak of the entire audio
2. **Normalization Pass**: Applies the FFmpeg `loudnorm` filter with the measured values to normalize the audio to your target levels
