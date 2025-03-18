---
title: How To Shrink File Size
---

# How To Shrink File Size

## Auto-Editor Makes Files That Are Too Big!
This is generally good since auto-editor tries to preserve video quality as much as possible. However, there are tricks you can use to shrink file size with little to no quality loss.

## Video Bitrate
Change the video bitrate to a lower value. Auto-Editor by default sets the video bitrate to `5M` or 5 Megabytes. This is a very high bitrate so most video encoders will use a lower value, however, the encoder still might set a bitrate too high for your liking. You can set it manually based on the file size you expect.

Assuming the video is 2 minutes, the file size will be about 27600k (2 * 60 * 230), not including audio size.
```
auto-editor my-video.mp4 -b:v 230k
```

Examples:
```
auto-editor my-huge-h264-video.mp4 -b:v 10M  # Maximum quality, big file size
auto-editor my-h264-video.mp4 -b:v auto  # Let ffmpeg chose, efficient and good looking quality
auto-editor i-want-this-tiny.mp4 -b:v 125k  # Set bitrate to 125 kilobytes, quality may vary
auto-editor my-video.mp4 -c:v h264 -b:v 0  # Set a variable bitrate
```

## Audio Streams
Your audio contributes to size too, if you use the AAC encoder, it should always be a reasonable size.

| Encoder               | Type             | Quality   | Speed     |
|-----------------------|------------------|-----------|-----------|
| aac_at (AudioToolBox) | Hardware (Apple) | best      | very fast |
| fdk_aac               | Software         | very good | fast      |
| aac (ffmpeg)          | Software         | good      | fast      |

## Using Better Video Encoders
Your file size depends on the encoder used. h264 is great but not the best. hevc (also known as h265) can achieve much smaller sizes with about the same quality. One trade-off is that some software, such as media players and editors, doesn't the next-gen encoders.

The table below compares different video codecs:

| Codecs  | Compression | Speed      | Compatibility |
|---------|-------------|------------|---------------|
| h264    | high        | very fast  | best          |
| hevc    | very high   | fast*      | so-so         |
| vp9     | very high   | slow       | high          |
| av1     | very high   | very slow  | high          |
| mpeg4   | very low    | superfast  | so-so         |


Due to copyright and patent law affecting software makers, auto-editor does not bundle hevc software encoders, but you can re-encode your videos if you have your own ffmpeg installed.

Example:
```
ffmpeg -i my-video.mp4 -c:a copy -c:v hevc -b:v 0 my-video-h265.mp4
```

## Tips for libx264
Auto-Editor doesn't ship libx264 for legal reasons, but you can still use x264 if you have ffmpeg installed.

```
ffmpeg -i input.mp4 -c:a copy -c:v libx264 -preset medium out.mp4
```

Use Constant Rate Factor (CRF) unless you already know exactly what you want the bitrate to be. Setting `-preset` to a slower value than `medium` doesn't hurt either.

If you do use video bitrate, don't set it to a high number like `10M`. Unlike libopenh264, libx264 with faithfully target that absurd number even if the quality gain is teeny-tiny.

[FFmpeg's wiki page explains the options you can use in more detail.](https://trac.ffmpeg.org/wiki/Encode/H.264)
