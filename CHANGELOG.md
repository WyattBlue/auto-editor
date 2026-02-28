# 29.8.1

## Major

## Features
 -

## Fixes
 - Remove "Cuda" builds because they were too big and bloated. You can compile whisper-cpp's cli with
CUDA support if you really need it.
 - Switch to `config.nims` so that the correct flags are always passed no matter what nimble command is used.
 - Fix `--scale` not rounding to nearest 2 when most video formats require it.
 - `--preview`: Fix crash when there are no audio clips in the timeline.
