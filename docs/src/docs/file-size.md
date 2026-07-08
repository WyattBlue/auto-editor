---
title: How to Shrink File Size
---

# How to Shrink File Size

## Auto-Editor Makes Files That Are Too Big!
This is generally good since auto-editor tries to preserve video quality as much as possible. However, there are tricks you can use to shrink file size with little to no quality loss.

## Video Bitrate
Change the video bitrate to a lower value. By default, the video bitrate is set to `auto`, which lets the encoder choose. The encoder might set a bitrate too high for your liking, so you can set it manually based on the file size you expect.

Assuming the video is 2 minutes, the video stream will be about 27,600 kbits (2 * 60 * 230), or about 3.45 MB, not including audio size.
```sh
auto-editor my-video.mp4 -b:v 230k
```

Examples:
```sh
auto-editor my-huge-h264-video.mp4 -b:v 10M  # Maximum quality, big file size
auto-editor my-h264-video.mp4 -b:v auto  # Let ffmpeg chose, efficient and good looking quality
auto-editor i-want-this-tiny.mp4 -b:v 125k  # Set bitrate to 125 kilobits per second, quality may vary
auto-editor my-video.mp4 -c:v h264 -b:v 0  # Set a variable bitrate
```

## Audio Streams
Your audio contributes to size too, if you use the AAC encoder, it should always be a reasonable size.

| Encoder               | Type             | Quality   | Speed     |
|-----------------------|------------------|-----------|-----------|
| opus (libopus)        | Software         | best      | fast      |
| aac (ffmpeg 9+)       | Software         | excellent | fast      |
| fdk_aac               | Software         | great     | fast      |
| aac_at (AudioToolBox) | Hardware (Apple) | good      | very fast |
| aac (ffmpeg <9)       | Software         | meh       | fast      |

## Using Better Video Encoders
Your file size depends on the encoder used. h264 is great but not the best. hevc (also known as h265) can achieve much smaller sizes with about the same quality. One trade-off is that various software, such as media players and NLEs, doesn't understand next-gen encoders.

The table below compares different video codecs:

| Codecs  | Compression | Encoder Speed | Compatibility |
|---------|-------------|---------------|---------------|
| h264    | high        | very fast     | best          |
| hevc    | very high   | fast          | high          |
| av1     | very high   | fast          | high          |
| vp9     | very high   | meh           | high          |
| gif     | okay to bad | superfast     | high          |
| mpeg4   | very low    | superfast     | so-so         |
| av2     | super       | fast?         | experimental  |
| vvc     | super       | fast?         | experimental  |

Auto-Editor's static builds do not include AV2 or VVC encoders.

Example:
```sh
ffmpeg -i my-video.mp4 -c:a copy -c:v hevc -b:v 0 my-video-h265.mp4
```

<a class="next" href="./subcommands">Next: Subcommands</a>
