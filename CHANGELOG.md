# 31.1.1

## Major
 - 

## Features
 - 

## Performance
 - 

## Fixes
 - Allow dynamic builds to link to whisper-cpp, allowing package manager like Homebrew to use transcription features.
 - Premiere XML: non-standard NTSC timebases now use the correct 1000/1001 ratio on import and export (was 999/1000).
 - `--edit`/`--audio-normalize` expressions with a missing closing parenthesis or stray tokens are now rejected with a clear error instead of being silently misparsed.
 - `--audio-bitrate` is no longer silently ignored; the requested bitrate now reaches the audio encoder.
 - kdenlive export: `varispeed` clips now get timewarp producers like `speed` clips instead of playing 1x from the wrong source position.
 - kdenlive export: timewarp producers now span the warped source length instead of the timeline length, so sped-up clips near the end of the source no longer freeze.
