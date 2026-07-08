---
title: info
---

`info` is a utility program that displays media information relevant to auto-editor.

Here is an example. Note that you can use multiple files at once.
```
auto-editor info example.mp4 resources/only-video/man-on-green-screen.gif

example.mp4:
 - recommendedTimebase: 30/1
 - video:
   - track 0:
     - codec: h264
     - fps: 30
     - resolution: 1280x720
     - aspect ratio: 16:9
     - pixel aspect ratio: 1
     - duration: 42.4
     - pix fmt: yuv420p
     - color range: 1 (tv)
     - color space: 1 (bt709)
     - color primaries: 1 (bt709)
     - color transfer: 1 (bt709)
     - timebase: 1/30000
     - bitrate: 240958
     - lang: eng
 - audio:
   - track 0:
     - codec: aac
     - layout: stereo
     - samplerate: 48000
     - duration: 42.4
     - bitrate: 317375
     - lang: eng
 - container:
   - duration: 42.4
   - bitrate: 570335

resources/only-video/man-on-green-screen.gif:
 - recommendedTimebase: 3333/100
 - video:
   - track 0:
     - codec: gif
     - fps: 100/3
     - resolution: 1280x720
     - aspect ratio: 16:9
     - pixel aspect ratio: 64/64
     - duration: 24.41
     - pix fmt: bgra
     - timebase: 1/100
 - container:
   - duration: 24.41
   - bitrate: 1649917
```

The default format is pseudo-yaml meant for humans. You can get a machine friendly output with the `--json` option.

```
auto-editor info example.mp4 --json

{
  "example.mp4": {
    "type": "media",
    "recommendedTimebase": "30/1",
    "video": [
      {
        "codec": "h264",
        "fps": "30",
        "resolution": [
          1280,
          720
        ],
        "aspect_ratio": [
          16,
          9
        ],
        "pixel_aspect_ratio": "1",
        "duration": 42.4,
        "pix_fmt": "yuv420p",
        "color_range": 1,
        "color_space": 1,
        "color_primaries": 1,
        "color_transfer": 1,
        "timebase": "1/30000",
        "bitrate": 240958,
        "lang": "eng"
      }
    ],
    "audio": [
      {
        "codec": "aac",
        "layout": "stereo",
        "samplerate": 48000,
        "duration": 42.4,
        "bitrate": 317375,
        "lang": "eng"
      }
    ],
    "subtitle": [],
    "image": [],
    "container": {
      "duration": 42.4,
      "bitrate": 570335
    }
  }
}
```

<a class="next" href="./levels">Next: levels</a>
