# 22w37a

## New Features

You can now add audio to the timeline and change its volume.
```
auto-editor movie.mp4 \
--source my-background:/Users/wyattblue/Downloads/music.mp3 \
--add audio:0,500,my-background,volume=0.7
```

Auto-Editor renders volume using FFmpeg's [volume audio filter](https://www.ffmpeg.org/ffmpeg-filters.html#volume) and accepts both raw floats and decibels.

### dB units for audio threshold

dB is now a supported unit. 

```
auto-editor --edit audio:threshold=-24dB  # equivalent to 0.063
```

## Minor Improvements
 * ZipSafe is now set to True, which makes auto-editor slightly faster
 * You can now add background music/audio


## Breaking Changes
 * Removed `--timeline` and `--api` options. Instead, use the export option as so: `--export timeline:api=$VAL`

## Bug Fixes
* Final Cut Pro: Use numerator and denominator of timebase fraction by @marcelohenrique in https://github.com/WyattBlue/auto-editor/pull/302

## New Contributors
* @marcelohenrique made their first contribution in https://github.com/WyattBlue/auto-editor/pull/302

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w35c...22w37a

