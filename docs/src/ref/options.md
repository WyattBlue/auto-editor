---
title: Options
---

## Editing Options:

### `--edit METHOD`
#### Aliases: `-e`

Set an expression which determines how to make auto edits. (default is "audio")

### `--when-normal ACTION`
#### Aliases: `-w:1` `--when-active`

When a segment is active (defined by \--edit) do an action. The default action being 'nil'

### `--when-silent ACTION`
#### Aliases: `-w:0` `--when-inactive`

When a segment is inactive (defined by \--edit) do an action. The default action being 'cut'



Actions available:

  nil, unchanged/do nothing

  cut, remove completely

  speed, (val: float),

    change the speed while preserving pitch. val: between (0-99999)

  varispeed, (val: float),

    change the speed by varying pitch. val: between [0.2-100]

  invert, invert all pixels in a video

  zoom, (val: float),

    zoom in/out with a factor of val. val: between (0-100]

### `--margin LENGTH[,LENGTH?]`
#### Aliases: `-m`

Set sections near "loud" as "loud" too if section is less than LENGTH away. (default is "0.2s")

### `--smooth MINCUT[,MINCLIP?]`
Make sections 'smoother' by applying minimum cut and minimum clip rules. (default is 0.2s,0.1s)

Examples:

  \--smooth 0.2s,0.1s  # Set mincut to 0.2 seconds, minclip to 0.1 seconds.

  \--smooth 0  # Turn off smoothing

### `--output FILE`
#### Aliases: `-o`

Set the name/path of the new output file

### `--cut [START,STOP ...]`
#### Aliases: `--cut-out`

Set segment(s) that will be cut/removed

### `--keep [START,STOP ...]`
#### Aliases: `--add-in`

Set segment(s) that are leaved "as is", overriding other actions

### `--set-speed-for-range [SPEED,START,STOP ...]`
#### Aliases: `--set-speed`

Set segment(s) to a SPEED, overriding other actions

### `--set-action ACTION,start,end`
Set a time segment to an ACTION, overriding other actions

Examples:

  \--set-action nil,0,5sec

  \--set-action speed:1.5,varispeed:1.5,30sec,end

### `--silent-speed NUM`
\[Deprecated\] Set speed of inactive segments to NUM. (default is 99999)

### `--video-speed NUM`
\[Deprecated\] Set speed of active segments to NUM. (default is 1)

## Timeline Options:

### `--frame-rate NUM`
#### Aliases: `-tb` `--time-base` `-r` `-fps`

Set timeline frame rate

### `--sample-rate NAT`
#### Aliases: `-ar`

Set timeline sample rate

### `--resolution WIDTH,HEIGHT`
#### Aliases: `-res`

Set timeline width and height

### `--background COLOR`
#### Aliases: `-b` `-bg`

Set the background as a solid RGB color

## URL Download Options:

### `--yt-dlp-location PATH`
Set a custom path to yt-dlp

### `--download-format FORMAT`
Set the yt-dlp download format (\--format, -f)

### `--output-format TEMPLATE`
Set the yt-dlp output file template (\--output, -o)

### `--yt-dlp-extras CMD`
Add extra options for yt-dlp. Must be in quotes

## Display Options:

### `--progress PROGRESS`
Set what type of progress bar to use

### `--debug`
Show debugging messages and values

### `--quiet`
#### Aliases: `-q`

Display less output

### `--stats`
#### Aliases: `--preview`

Show stats on how the input will be cut and halt

## Container Settings:

### `-vn`
Disable the inclusion of video streams

### `-an`
Disable the inclusion of audio streams

### `-sn`
Disable the inclusion of subtitle streams

### `-dn`
Disable the inclusion of data streams

### `--faststart`
Enable movflags +faststart, recommended for web (default)

### `--no-faststart`
Disable movflags +faststart, will be faster for large files

### `--fragmented`
Use fragmented mp4/mov to allow playback before video is complete. See: ffmpeg.org/ffmpeg-formats.html#Fragmentation

### `--no-fragmented`
Do not use fragmented mp4/mov for better compatibility (default)

## Video Rendering:

### `--video-codec ENCODER`
#### Aliases: `-c:v` `-vcodec`

Set video codec for output media

### `--video-bitrate BITRATE`
#### Aliases: `-b:v`

Set the number of bits per second for video

### `-crf NUM`
Set the Constant Rate Factor for quality-based encoding. Lower = better quality. [0-63]

### `-vprofile PROFILE`
#### Aliases: `-profile:v`

Set the video profile. For h264: high, main, or baseline

### `--scale NUM`
Scale the output video's resolution by NUM factor

### `--no-seek`
Disable file seeking when rendering video. Helpful for debugging desync issues

## Audio Rendering:

### `--audio-codec ENCODER`
#### Aliases: `-c:a` `-acodec`

Set audio codec for output media

### `--audio-layout LAYOUT`
#### Aliases: `-layout`

Set the audio layout for the output media/timeline

### `--audio-bitrate BITRATE`
#### Aliases: `-b:a`

Set the number of bits per second for audio

### `--mix-audio-streams`
Mix all audio streams together into one

### `--audio-normalize NORM-TYPE`
#### Aliases: `-anorm`

Apply audio normalizing (either ebu or peak). Applied right before rendering the output file

## Miscellaneous:

### `--no-cache`
Disable reading and writing cache files

### `--open`
Open the output file after editing is done

### `--no-open`
Do not open the output file after editing is done (default)

### `--license-key`
#### Aliases: `-k`

Provide a license key, which activates certain features

### `--temp-dir PATH`
Set where the temporary directory is located

### `--version`
#### Aliases: `-V` `-v`

Show info about this program or option

---
Version 30.1.1<br>Generated: 2026-03-26.
