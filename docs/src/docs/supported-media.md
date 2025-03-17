---
title: Supported Media
---

# Supported Media
Auto-Editor supports a wide range of media formats thanks to ffmpeg. Listed below is what is and is not allowed.

## What's allowed
 * Media with only audio streams
 * Media with only video streams
 * Media with video, audio, subtile, embedded images, and data streams

## What isn't
 * Media with only subtitle/data streams.
 * Media with video or audio streams longer than 24 hours
 * Video streams whose total number of frames exceeds a 60fps 24 hour video
 * Audio streams whose total number of samples exceeds a 192kHz 24 hour video

Using specific codecs/containers depends on which ffmpeg program auto-editor uses.

---
### Footnotes
The terms "stream" and "track" are used interchangeably.
