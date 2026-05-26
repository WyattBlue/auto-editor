# 30.2.5

## Major
 -

## Features
 - Add OpenTimelineIO export (`--export premiere-otio`, `.otio`). Unlike the FCP7 XML export, it carries the `invert`, `hflip`, and `vflip` actions into Premiere Pro as native video effects.
 - Add `brightness`, `brighthue`, `contrast`, and `saturation` video actions. `brightness` shifts all RGB channels equally (`lutrgb`); `brighthue`/`contrast`/`saturation` adjust the Y/U/V channels and are fused into a single `lutyuv` pass when used together.

## Fixes
 - Add empty_moov for `--fragmented` mp4s  
 - Fix progress bars sometimes not clearing correctly
