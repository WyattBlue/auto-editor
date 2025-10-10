---
title: Audio Normalizing
---

# Audio Normalizing

Audio normalization is the process of adjusting audio levels to achieve consistent loudness across your media. This is especially useful when combining multiple audio sources with different volume levels, or when preparing content for platforms that have specific loudness requirements.

Auto-Editor supports two kinds of audio normalization: **peak** and **ebu**. Peak normalization is simpler and faster, scaling audio based on the highest amplitude. EBU R128 normalization is more sophisticated, analyzing perceived loudness to meet broadcast standards. Choose peak normalization for quick volume adjustments, or EBU normalization when you need precise loudness control for professional distribution.

## Peak

Example:

```
auto-editor --audio-normalize peak:-3  # set max peak to -3dB
```

The key idea is that peak normalization preserves the dynamic range of your audio—it just scales everything up or down so the loudest moment hits your target level. This is different from EBU normalization which
analyzes perceived loudness over time.

## EBU

EBU R128 normalization analyzes the perceived loudness of your audio over time and adjusts it to meet broadcast standards. Unlike peak normalization which simply scales the audio, EBU normalization uses a more sophisticated algorithm that considers how humans perceive loudness.

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

This approach ensures consistent perceived loudness across different audio content, making it ideal for broadcast, streaming platforms, and podcast production.
