---
title: info
---

## info
`info` is a utility program that displays media information relevant to auto-editor.

Here is an example. Note that you can use multiple files at once.
```
auto-editor info example.mp4 resources/only-video/man-on-green-screen.gif

example.mp4:
 - video:
   - track 0:
     - codec: h264
     - fps: 30
     - resolution: 1280x720
     - aspect ratio: 16:9
     - pixel aspect ratio: 1:1
     - duration: 42.400000
     - pix fmt: yuv420p
     - color range: tv
     - color space: bt709
     - color primaries: bt709
     - color transfer: bt709
     - timebase: 1/30000
     - bitrate: 240958
     - lang: eng
 - audio:
   - track 0:
     - codec: aac
     - samplerate: 48000
     - channels: 2
     - duration: 42.400000
     - bitrate: 317375
     - lang: eng
 - container:
   - duration: 42.400000
   - bitrate: 570335

resources/only-video/man-on-green-screen.gif:
 - video:
   - track 0:
     - codec: gif
     - fps: 30
     - resolution: 1280x720
     - aspect ratio: 16:9
     - pixel aspect ratio: 1:1
     - duration: 24.410000
     - pix fmt: bgra
     - timebase: 1/100
 - container:
   - duration: 24.410000
   - bitrate: 1649917
```

The default format is pseudo-yaml meant for humans. You can get a machine friendly output with the `--json` option.

```
auto-editor info example.mp4 --json

{
    "example.mp4": {
        "type": "media",
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
                "pixel_aspect_ratio": "1:1",
                "duration": "42.400000",
                "pix_fmt": "yuv420p",
                "color_range": "tv",
                "color_space": "bt709",
                "color_primaries": "bt709",
                "color_transfer": "bt709",
                "timebase": "1/30000",
                "bitrate": "240958",
                "lang": "eng"
            }
        ],
        "audio": [
            {
                "codec": "aac",
                "samplerate": 48000,
                "channels": 2,
                "duration": "42.400000",
                "bitrate": "317375",
                "lang": "eng"
            }
        ],
        "subtitle": [

        ],
        "container": {
            "duration": "42.400000",
            "bitrate": "570335",
            "fps_mode": null
        }
    }
}
```

You may call info with `aeinfo`.
