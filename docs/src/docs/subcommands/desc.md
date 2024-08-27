---
title: desc
---

## desc
`desc` displays the video's description. If there is none, `No description.` will be displayed.
You may call `desc` with `aedesc`

Examples:

```
% yt-dlp --add-metadata -f "bestvideo[ext=mp4]" "https://www.youtube.com/watch?v=jNQXAC9IVRw" -o out.mp4
% auto-editor desc out.mp4

Chapters:

00:00 Intro
00:05 The cool thing
00:17 End

Interesting.... https://www.youtube.com/watch?v=VaLXzI92t9M
```

```
% auto-editor desc example.mp4

No description.
```
