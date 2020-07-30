# Documentation

## Table of Contents

- [The Basics](#The-Basics)
- [Auto-Editor Options](#Auto-Editor-Options)
  - [Input](#Input)
  - [Basic Options](#Basic-Options)
  - [Advanced Options](#Advanced-Options)
  - [Audio Options](#Audio-Options)
  - [Cutting Options](#Options-for-Cutting)
  - [Developer/Debugging Options](#Developer-Debugging-Options)
  - [Export Options](#Export-Options)


## The Basics

### Minimal Example
Create an edited version of example.mp4 with the default parameters.
```terminal
auto-editor example.mp4
```



# Auto-Editor Options

## Input
Input is required for auto-editor to know what to edit from. It supports videos, audios, URLs, and folders.

Here an example of using a URL as the input for auto-editor. In certain enviroments, you must wrap the URL around single or double quotes.

```terminal
auto-editor "https://www.youtube.com/watch?v=kcs82HnguGc"
```
You can also add multiple inputs at once.

```terminal
auto-editor example.mp4 example2.mp4 --frame_margin 10
```

## Basic Options

### Frame Margin
Frame Margin is how much extra silent frames there are on each side between the loud parts.

```terminal
auto-editor example.mp4 --frame_margin 1
```

Command | `--frame_margin`
--------|--------------
type    | int
range   | 0 to Infinity
default | 4
short   | `-m`

### Silent Threshold
Silent Threshold is the level at which any section below it is considered "silent". It uses percentages that represent how loud a chunk is compared to the loudest part in the audio. Using Decibels (dB) is not supported yet.

```terminal
auto-editor example.mp4 --silent_threshold 0.02
```

Command | `--silent_threshold`
--------|--------------
type    | float_type
range   | 0 to 1, 0% to 100%
default | 0.04, 4%
short   | `-t`

### Video Speed
Video Speed represents how fast to play the parts of the video that are "loud". You can set to a number or a percentage. It also has an alias, `--sounded_speed` since auto-editor can edit audio files and setting the video speed is strange since there isn't a video in this case.

```terminal
auto-editor example.mp4 --video_speed 150%
```

Command | `--video_speed`
--------|--------------
type    | float_type
range   | 0 to 99999, 0% to 9999900%
default | 1, 100%
short   | `-v`
alias   | `--sounded_speed`

### Silent Speed
Silent Speed represents how fast to play the parts of the video that are "silent". It's default is set to 99999 which, unlike 99998, is a special number because it completely throws away any frames or audio without even considering creating new audio/frames. You can set to a number or a percentage.

```terminal
auto-editor example.mp4 --silent_speed 5
```

Command | `--silent_speed`
--------|--------------
type    | float_type
range   | 0 to 99999, 0% to 9999900%
default | 99999, 9999900%
short   | `-s`

### Output File
Output File changes where the new file will be saved. It if is blank, it will append "\_ALTERED" to the name.

```termianl
auto-editor example.mp4 --output_file edited_example.mp4
```

Command | `--output_file`
--------|--------------
type    | str
default | ''
short   | `-o`

### Help
Get all the commands and options in Auto-Editor.

```terminal
auto-editor --help
```

Command | `--help`
--------|--------------
type    | flag
short   | `-h`


## Advanced Options

### Zoom Threshold
You can tell auto-editor to zoom in when the input's audio is above the loudness threshold. Auto-Editor will hold the zoom until there's a cut. Setting this option to 101% or more will disable zooming.

```terminal
auto-editor example.mp4 --zoom_threshold 50%
```

Command | `--zoom_threshold`
--------|---------------------
type    | float_type
range   | 0 to 1.01, 0% to 101%
default | 1.01, 101%

Here is a side by side comparison between a video with no zoom, and a video with auto zoom.

<p align="center">
  <img src="/resources/auto_zoom_demo.gif" width="800">
</p>

(video source from jacksfilms)

## Audio Options

### Sample Rate
Sample Rate sets the sample rate of the audio.

```terminal
auto-editor example.mp4 --sample_rate 44.1 kHz
```

Command | `--sample_rate`
--------|---------------------
type    | sample_rate_type
range   | 0 to Infinity
default | 48000, 48000 Hz, 48.0 kHz
short   | `-r`


### Audio Bitrate
Audio Bitrate sets the number of bits per second for audio.

```terminal
auto-editor example.mp4 --audio_bitrate '192k'
```

Command | `--audio_bitrate`
--------|---------------------
type    | str
default | '160k'

### Background Music
Background Music adds in a audio file you specify and will automatically change the volume so that it is lower than audio track being cut.

```terminal
auto-editor example.mp4 --background_music resources/Magic_in_the_Garden.mp3
```

### Background Volume
Background Volume sets the difference between the video's audio and the background's music volume.

Command | `--background_volume`
--------|---------------------
type    | float
range   | -Infinity to Infinity
default | -8

## Options for Cutting

### Cut By This Audio
Choose which audio track to cut by.

```terminal
auto-editor example.mp4 --cut_by_this_audio resources/newCommentary.mp3
```

Command | `--cut_by_this_audio`
--------|---------------------
type    | file_type
alias   | `-ca`

### Cut By This Track
Select a certain audio track in a video before editing.

```terminal
auto-editor videoWith2Tracks.mp4 --cut_by_this_track 1
```

Command | `--cut_by_this_track`
--------|---------------------
type    | int
range   | 0 to Infinity
default | 0
short   | `-ct`

### Cut By All Tracks
Cut By All Tracks combines all audio tracks into one before determining how to edit the video.

```terminal
auto-editor videoWith2Tracks.mp4 --cut_by_all_tracks
```

Command | `--cut_by_all_tracks`
--------|---------------------
type    | flag
alias   | `-cat`


### Keep Tracks Seperate
Keep Tracks Seperate tells auto-editor don't combine the audio tracks when outputing a video with multiple audio tracks.

Command | `--keep_tracks_seperate`
--------|---------------------
type    | flag

## Developer Debugging Options

### Clear Cache
Clear Cache will delete the directory named `.CACHE` in the auto-editor folder.

```terminal
auto-editor --clear_cache
```

Command | `--clear_cache`
--------|---------------------
type    | flag

### Version
Get the version of auto-editor you're using.

```terminal
auto-editor --version
```

Command | `--version`
--------|---------------------
type    | flag


### My FFmpeg
Use your own ffmpeg instead of the one's provided.

```terminal
auto-editor example.mp4 --my_ffmpeg
```

Command | `--my_ffmpeg`
--------|---------------------
type    | flag

### Debug
Debug will get debug information regarding auto-editor, including your python version, whether the your python is 64-bit or not, and the current version.

```terminal
auto-editor --debug
```

Command | `--debug`
--------|---------------------
type    | flag


## Export Options

### Preview
Preview gives you an overview of how auto-editor will cut the video without having to create the new video.

```terminal
auto-editor --preview
```

Command | `--preview`
--------|---------------------
type    | flag

### Export To Premiere
Export To Premiere makes a XML file that can be imported to Adobe Premiere Pro instead of making a new video.

```terminal
auto-editor --export_to_premiere
```

Command | `--export_to_premiere`
--------|---------------------
type    | flag

