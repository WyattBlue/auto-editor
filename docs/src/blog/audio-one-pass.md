---
title: An Additional Note for 24w30a
author: WyattBlue
date: July 29, 2024
desc: In the 24w30a release, the default method for editing, `audio`, switched from being two-pass to one-pass. The motivation is speed, especially
---

In the 24w30a release, the default method for editing, `audio`, switched from being two-pass to one-pass. Speed, is the motivation (well, latency to be exact). You get the results as they come in without having to wait until the entire audio stream is decoded.

The [GUI](https://auto-editor.com/app) uses this property to full effect to deliver a fast, snappy experience. Besides the `levels` subcommand, the CLI doesn't currently take much advantage of this. It does allow for interesting optimizations, like allowing to skip decoding portions of the audio stream all together (think of cases like `--cut-out 30sec,end`).

To review, the old two-pass method divided every level (the loudest of a bundle of samples in timebase length) by the loudness sample in the audio file. The new one-pass method skips the division.

As a user, you might want to change the audio threshold to a lower value to account for this, although the difference is only large if the input audio's loudest sample is a lot less than the max possible.

If you like the audio threshold being "floating" instead of absolute, you can use this Palet procedure:

```palet
(define/c (audio-2pass [threshold threshold?] [stream nat?] -> bool-array?)
  (define arr (audio-levels stream))
  (define max-val arr.max-seq)
  (define result (map (lambda (x) (/ x max-val)) arr))
  (map (lambda (x) (>= x threshold)) result)
)
```

then call `audio-2pass` in the `--edit` option. This implementation uses the max audio level instead of the max audio sample, but this shouldn't matter in real-world cases.
