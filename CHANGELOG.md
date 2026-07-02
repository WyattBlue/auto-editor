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
 - `subdump` now dumps every subtitle stream instead of only the first.
 - `--stats`/`--preview` cut statistics: the trailing cut and single-clip leading cuts are now counted, and sped-up clips no longer skew the numbers.
 - AVI (and other pts-less/DTS-only sources) no longer render as black video, and seeks in sources whose timebase numerator isn't 1 land on the right frame.
 - An option missing its value (e.g. `-o --edit audio`) now errors instead of silently dropping the option
 - kdenlive and ShotCut exports: MLT `out` points are inclusive, so every clip was one frame too long, repeating a frame at each cut and drifting the timeline +1 frame per clip. Clips now end on their true last frame.
 - `--export resolve` with multiple multi-track sources no longer fails: every source's `*_tracks` folder is now created, not just the first's.
 - Effects no longer compound on repeated source frames (slow motion, or a lower-fps source in a higher-fps timeline), which made the video visibly pulse; animated effects now also keep progressing on repeated frames instead of freezing.
 - Final Cut Pro / Resolve export: drop-frame source timecodes (29.97/59.94 with a ";" separator) are now converted correctly; asset start points were ~108 frames per hour late.
 - Motion detection: frame rows were misaligned whenever the scaled width didn't match FFmpeg's row alignment (e.g. `motion:width=402`)
