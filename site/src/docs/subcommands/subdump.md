---
title: subdump
---

## subdump
`subdump` is a utility program that displays the textual representation of subtitle streams in media files.

Here's an example:

```
auto-editor subdump resources/subtitle.mp4

file: resources/subtitle.mp4 (0:und:srt)
1
00:00:00,523 --> 00:00:01,016
oop

2
00:00:01,523 --> 00:00:01,916
boop


------
```

subdump won't work if the subtitle stream is interally represented as a bitmap image instead of formatted text.

You may call subdump with `aesubdump`.
