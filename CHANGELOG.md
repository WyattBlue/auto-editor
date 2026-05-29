# 30.3.1

## Major
 -

## Features
 - Add micro-fade at clip edges to prevent audio pops.
 - For URL inputs, only the streams that are actually used are fetched: streams the output container can't hold are skipped unless an `--edit` method needs to analyze them. `--stats`/`--preview` downloads only the audio to a temporary location.
 - `-res WIDTH,HEIGHT` now limits the height of yt-dlp downloads (e.g. `-res 1920,1080` caps the video at 1080p).
 - URL inputs now default to an `mkv` container and the `h264` video codec (instead of inheriting the downloaded file's container/codec, e.g. webm/vp9).

## Fixes
 - Remove `--download-format` as it is now superfluous.
