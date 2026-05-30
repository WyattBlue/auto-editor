# 30.3.1

## Major
 -

## Features
 - Add the `deesser` action to reduce harsh "s"/"sh" sibilance in audio sections; accepts positional `intensity[:max[:freq]]` (e.g. `--when-normal deesser:0.5`).
 - Store audio/motion/waveform analysis levels as 16-bit normalized values, roughly halving level-cache file size. `levels`/`waveform` output values are rounded accordingly.
 - Add micro-fade at clip edges to prevent audio pops.
 - For URL inputs, only the streams that are actually used are fetched: streams the output container can't hold are skipped unless an `--edit` method needs to analyze them. `--stats`/`--preview` downloads only the audio to a temporary location.
 - `-res WIDTH,HEIGHT` now limits the height of yt-dlp downloads (e.g. `-res 1920,1080` caps the video at 1080p).
 - URL inputs now default to an `mkv` container and the `h264` video codec (instead of inheriting the downloaded file's container/codec, e.g. webm/vp9).

## Fixes
 - `info` now reports the intended display aspect ratio: it folds in the pixel aspect ratio so anamorphic video shows its true ratio (e.g. `720x480` with SAR `32:27` shows `16:9`), and snaps codec-rounding artifacts to the common ratio they approximate (e.g. `854x480` shows `16:9` instead of the meaningless exact reduction `427:240`).
 - Remove `--download-format` as it is now superfluous.
