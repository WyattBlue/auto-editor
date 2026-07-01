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
