# 30.2.1

## Major
 -

## Features
 -

## Fixes
 - Fix only the first uncached audio stream being analyzed when multiple are referenced
 - Fix `--export resolve`/`final-cut-pro` offsetting every clip's timeline position by the media's start timecode, breaking the edit for footage with embedded timecode
 - Fix `--export resolve`/`final-cut-pro` writing an invalid sequence `audioLayout` (e.g. `mono`) rejected by Final Cut Pro; layouts now map to `stereo` or `surround`
 - Fix `--export final-cut-pro` setting each `asset`'s `duration` to the edited timeline length instead of the source media's duration
 - Fix `--export premiere` forcing mono sources into an exploded stereo track-pair, leaving the audio playing on only one side; mono sources now export as a single `Mono` track
 - Fix `--export premiere` writing duplicate `clipitem` ids and dangling `<link>` references
