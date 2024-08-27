---
title: How To Shrink File Size
---

# How To Shrink File Size

## Auto-Editor Makes Files That Are Too Big!
This is generally good since auto-editor tries to preserve video quality as much as possible. However, there are tricks you can use to shrink file size with little to no quality loss.

## Tips For General Encoders
Change the video bitrate to a lower value. Auto-Editor by default sets the video bitrate to `5M` or 5 Megabytes. This is a very high bitrate so most video encoders will use a lower value, however, the encoder still might set a bitrate too high for your liking. You can set it manually based on the file size you expect.

Assuming the video is 2 minutes, the file size will be about 27600k (2 * 60 * 230), not including audio size.
```
auto-editor my-video.mp4 -b:v 230k
```

Examples:
```
auto-editor my-huge-h264-video.mp4 -b:v 10M  # Maximum quality, big file size
auto-editor my-h264-video.mp4 -b:v unset  # Let ffmpeg chose, efficient and good looking quality
auto-editor i-want-this-tiny.mp4 -b:v 125k  # Set bitrate to 125 kilobytes, quality may vary
auto-editor my-mpeg4-video.mp4 -c:v h264 -b:v unset
```

## Knowing What Encoder You're Using
Let's assume your video is using the h264 codec. In that case you're either using the libopen264 encoder or the libx264 encoder in auto-editor. If you've set the `--my-ffmpeg` flag or you're on Linux, you're probably using libx264. If not, you're using libopenh264.


## Tips for libx264
Use Constant Rate Factor (CRF) unless you already know exactly what you want the bitrate to be. Setting `-preset` to a slower value than `medium` doesn't hurt either.

If you do use video bitrate, don't set it to a high number like `10M`, it will do what you say, not what you want. libx264 with faithfully target that absurd number even if the quality gain is teeny-tiny.

Recommended options:
```
auto-editor my-video.mp4 --my-ffmpeg -c:v libx264 -b:v unset --extras "-preset slow -crf 22"
```

[FFmpeg's wiki page explains the options you can use in more detail.](https://trac.ffmpeg.org/wiki/Encode/H.264)


## Using Better Codecs
If your video codec sucks, your file size will be big. h264 is great but not the best. hevc (also known as h265) can achieve much smaller sizes with about the same quality. One tradeoff with hevc however is that some media players don't support it such as QuickTime.

Due to copyright and patent law affecting software makers, auto-editor does not bundle hevc by default, but you can still use it if you have your own ffmpeg installed.

Example:
```
auto-editor my-video.mp4 --my-ffmpeg -c:v hevc -b:v unset
```
