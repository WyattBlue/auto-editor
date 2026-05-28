# 30.3.1

## Major
 -

## Features
 - When downloading a URL with yt-dlp, only the streams that are actually used are fetched: streams the output container can't hold are skipped unless an `--edit` method needs to analyze them (e.g. `-o out.mp3` downloads audio only, while `-o out.mp3 --edit motion` still downloads the video). `--stats`/`--preview` downloads only the audio to a temporary location.
 - `-res WIDTH,HEIGHT` now limits the height of yt-dlp downloads (e.g. `-res 1920,1080` caps the video at 1080p).
 - URL inputs now default to an `mkv` container and the `h264` video codec (instead of inheriting the downloaded file's container/codec, e.g. webm/vp9).

## Fixes
 - Remove `--download-format` as it is now superfluous.
