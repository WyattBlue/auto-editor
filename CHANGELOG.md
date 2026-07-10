# 31.2.0

## Major
 - 

## Features
 - New `pixelate` action: turn the picture into a coarse mosaic of blocks, the classic censoring look. `pixelate` uses 16px blocks, `pixelate:n` square n×n blocks, `pixelate:w:h` rectangular ones. Pair with `confine` to censor just a face or plate: `confine:400:300:200:80,pixelate:24`.
 - Motion detection now takes `x:y:w:h` region parameters (as 0–1 fractions of the frame, default the full frame), restricting analysis to a subsection of the picture, e.g. `--edit motion:x=0.25:w=0.5`.
 - Misspelled subcommands, options, and action names now get a "Did you mean ...?" suggestion.

## Performance
 - Keyframe lookup when seeking now uses a binary search instead of a linear scan.

## Fixes
 - zsh tab completion now works for subcommands.
 - Premiere XML import: clips whose Time Remap filter is followed by Motion/Opacity filters (Premiere's normal order) no longer lose their speed and import at 1x.
 - `nan` in numeric option/action values is now rejected instead of slipping past range checks into undefined conversions.
