# 31.1.0

## Major
 - 

## Features
 - Add mask/confine actions. `mask` creates an alpha mask. `confine` confines effects to a certain region. Both use rectanges, squircles, or ellipses as the region shape.
 - MacOS: Allow using the microphone as an input for the whisper cmd with `:mic`.
 - Add `--prompt` to the whisper cmd, allowing biasing for certain vocab.
 - MacOS: Default to the `aac_at` (AudioToolbox) encoder for AAC audio.

## Performance
 - 

## Fixes
 - Fix wrong progress bar total when analysis duration falls back to the container duration.
 - Remove vestigial `--temp-dir` option.
