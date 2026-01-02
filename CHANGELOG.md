# 29.6.0

## Major

## Features
 - Linux Aarch64 is now available as an official binary.
 - `--edit` will now look for external subtitle files if the input file doesn't have enough.
 - Whisper is now built on all platforms.
 - Cuda for whisper can now be built as an opt-in feature for Linux.
 - NOTE: Cuda Whisper for Windows cannot be built because NVIDIA does not provide MingW binaries. An alternative is to use the Linux binary in WSL.

## Fixes
 - Use the last video frame instead of inserting a black frame.
 - Fixed 6 month regression where `and` function performed 'logical or' instead of 'logical and'.
 - Fixed varispeed action causing misalignments in FCP7 and FCP11.
 - Whisper command: properly escape files with colons and backslashes.
