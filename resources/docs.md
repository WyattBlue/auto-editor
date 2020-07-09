# Documentation


## Table of Contents

- [The Basics](#The-Basics)
- [Vocabulary](#Vocabulary)
- [Auto-Editor Options](#Options)
  - [Basic Options](#Basic-Options)
  - [Advanced Options](#Advanced-Options)
  - [Audio Options](#Audio-Options)
  - [Options for Cutting](#Options-for-Cutting)
  - [Options for Debugging](#Options-for-Debugging)
  - [Options That Completely Change What Auto-Editor Does](#Options-That-Completely-Change-What-Auto-Editor-Does)
  - [Deprecated Options](#Deprecated-Options)


## The Basics

### Minimal Example
Create an edited version of example.mp4 with the default parameters.
```terminal
 $ python auto-editor.py example.mp4
```

### A Note about Formating
Dollar sign notation is used to indicate that you should be running this in your console.
Don't actually put one in when typing commands.

`python` works for Windows and some Linux distros, but not for all. In that case, you should replace `python` with some other key word that links to your Python 3 installation, typically `python3`.

You can see where a keyword links to by typing in.
```terminal
 $ which python
```

## Auto-Editor Options

### Basic Options

Frame margin is how much extra silent frames there are on each side between the loud parts.

```terminal
 $ python auto-editor.py example.mp4 --frame_margin 1
```

Command | `--frame_margin`
--------|--------------
type    | int
range   | 0 to Infinity
default | 4
short   | `-m`

Silent Threshold is the level at which any section below it is considered "silent". It uses percentages that represent how loud a chunk is compared to the loudest part in the audio. Using Decibels (dB) is not supported yet.

```terminal
 $ python auto-editor.py example.mp4 --silent_threshold 0.02
```

Command | `--silent_threshold`
--------|--------------
type    | float_type
range   | 0 to 1, 0% to 100%
default | 0.04, 4%
short   | `-t`

Video Speed represents how fast to play the parts of the video that are "loud". You can set to a number or a percentage. It also has an alias, `--sounded_speed` since auto-editor can edit audio files and setting the video speed is strange since there isn't a video in this case.

```terminal
 $ python auto-editor.py example.mp4 --video_speed 150%
```

Command | `--video_speed`
--------|--------------
type    | float_type
range   | 0 to 99999, 0% to 9999900%
default | 1, 100%
short   | `-v`
alias   | `--sounded_speed`

Silent Speed represents how fast to play the parts of the video that are "silent". It's default is set to 99999 which, unlike 99998, is a special number because it completely throws away any frames or audio without even considering creating new audio/frames. You can set to a number or a percentage.

```terminal
 $ python auto-editor.py example.mp4 --silent_speed 5
```

Command | `--silent_speed`
--------|--------------
type    | float_type
range   | 0 to 99999, 0% to 9999900%
default | 99999, 9999900%
short   | `-s`

Output File changes where the new file will be saved. It if is blank, it will append "\_ALTERED" to the name.

```termianl
 $ python auto-editor.py example.mp4 --output_file edited_example.mp4
```

Command | `--output_file`
--------|--------------
type    | str
default | ''
short   | `-o`

### Advanced Options

### Audio Options

### Options for Cutting

### Options for Debugging

### Options That Completely Change What Auto-Editor Does

### Deprecated Options



## Changing Video Speed
Video speed will change speed of the output's video and audio. For instance, if the speed is set to 2. Half of the frames will be dropped and the audio will be speed up. This does not affect parts of the video that are below the silent threshold.
```
 $ python auto-editor.py example.mp4 --video_speed 2
```

Command | `--video_speed`
--------|--------------
type    | float
range   | 0 to 99999
default | 1
short   | `-v`
alias   | `--sounded_speed`

You can also do the same, but for the silent parts with --silent_speed
```
 $ python auto-editor.py example.mp4 --video_speed 2 --silent_speed 8
```


Command | `--silent_speed`
--------|--------------
type    | float
range   | 0 to 99999
default | 99999
short   | `-s`


## Zooming In
You can tell auto-editor to zoom in when the input's audio is above the loudness threshold. Auto-Editor will hold the zoom until there's a cut.

```terminal
--zoom_threshold
```

Command | `--zoom_threshold`
--------|---------------------
type    | float
range   | 0 to 1
default | 2
short   | `-l`


Here is a side by side comparison between a video with no zoom, and a video with auto zoom.

<p align="center">
  <img src="/resources/auto_zoom_demo.gif" width="800">
</p>

(video source from jacksfilms)

## Inputing Files
```
auto-editor.py input
```

Input is the only required argument for auto-editor. It supports video formats, audio formats, and URLs. For certain commands that do simple things, such as `--clear_cache` or `--version`, it's okay to skip providing an input.

Here an example of using a url as the input for auto-editor. You should always wrap the url around single quotes or double quotes.

```terminal
 $ python auto-editor.py "https://www.youtube.com/watch?v=kcs82HnguGc"
```

## Adding Music
You can add background music to your video automatically.

```terminal
 $ python auto-editor.py example.mp4 --background_music media/Magic_in_the_Garden.mp3
```

It will be quiet than the video's audio by 10dB and will fade out at the last second of the video.

## Adding Commentary
You can add an audio track to your video that will replace the video's audio as the one to base cuts on.

```terminal
 $ python auto-editor.py example.mp4 --cut_by_this_audio media/newCommentary.mp3
```

This option is good for combining gameplay videos with commentary, but beware that it doesn't change the volume for either audio unlike `--background_music`.

## Video Tracks
Video files can contain more than audio file and auto-editor. These 'audio files' are what we call audio tracks and auto-editor has a set of tools to deal with these tracks. First, if you'll like the tracks be separated on the output, use the flag `--keep_tracks_seperate`

```terminal
 $ python auto-editor.py videoWith2Tracks.mp4 --keep_tracks_seperate
```

Auto-Editor works by cutting out the silent parts and it needs to choose which audio track to base cuts on. By default it will be set to 0 (the first track) but you can change that with the `--cut_by_this_track` command.

```terminal
 $ python auto-editor.py videoWith2Tracks.mp4 --cut_by_this_track 1
```

Now the video with be cut by second audio track's volume! But what if you wanted to just ignore tracks all together? Well, with the `--cut_by_all_tracks` command, auto-editor will act is if all tracks were muxed into a single one.

```terminal
 $ python auto-editor.py videoWith2Tracks.mp4 --cut_by_all_tracks
```

## Caching In
Some videos need to be converted to a jpeg image sequence beforehand and this can take awhile. What if you want to use the same video but use different parameters. That's where caching comes in. The jpeg sequence and the audio are stored away in the .CACHE folder, ready to be used again if it is right.

The .CACHE folder can take quiet a bit of space so if you want to delete the folder and all its contents, run this command.

```terminal
 $ python auto-editor.py --clear_cache
```

Or, you can clear the cache before making a new one.

```terminal
 $ python auto-editor.py example.mp4 --clear_cache
```

## Miscellaneous
Get the list of commands generated by argparse.

```terminal
 $ python auto-editor.py --help
```

Get the version of auto-editor you're using.

```terminal
 $ python auto-editor.py --version
```

Get debug information regarding auto-editor, including your python version, whether the your python is 64-bit or not, and the current version.

```terminal
 $ python auto-editor.py --debug
```
