---
title: subdump
---

`subdump` is a utility program that displays the textual representation of subtitle streams in media files.

Here's an example:

```
auto-editor subdump resources/mov_text.mp4

file: resources/mov_text.mp4 (0:mov_text)
0,0,Default,,0,0,0,,oop
1,0,Default,,0,0,0,,boop
------
```

Each line is a subtitle event as an ASS dialogue line, whatever the stream's format. The header gives each stream's index and codec.

With `--json`, it prints each stream's cues with their times in seconds and plain text instead:

```
auto-editor subdump --json resources/mov_text.mp4

{"resources/mov_text.mp4":[{"stream":0,"codec":"mov_text","cues":[{"start":0.523,"end":1.016,"text":"oop"},{"start":1.523,"end":1.916,"text":"boop"}]}]}
```

subdump won't work if the subtitle stream is internally represented as a bitmap image instead of formatted text.

<a class="next" href="./whisper">Next: whisper</a>
