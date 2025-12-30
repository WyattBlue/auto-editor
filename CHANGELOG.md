# 29.6.0

## Major

## Features
 - Linux Aarch64 is now available as an official binary.
 - Whisper is now built on all platforms.
 - Cuda for whisper can now be built as an opt-in feature for Linux.
 - NOTE: Cuda Whisper for Windows cannot be built because NVIDIA does not provide MingW binaries. An alternative is to use the Linux binary in WSL.

## Fixes
 - Use the last video frame instead of inserting a black frame.
 - Whisper command: properly escape files with colons and backslashes.
