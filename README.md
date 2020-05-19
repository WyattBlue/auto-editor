[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w20a
# Auto-Editor
Auto-Editor is a video editing tool that will automatically edit raw source video into a entertaining and polished video.
It works by analyzing the video's audio to detect when a section needs to be cut, kept in, or zoomed in, then auto-editor runs a subproccess called ffmpeg to create the new video.

# Usage
## Minimal Example

Create an edited version of example.mp4 with the default parameters.
```console
$ python auto-editor.py example.mp4
```

## Change Video Speed

You can change how fast the video plays at when the video is normal and when it's silent (below the silent thershold). Use use the flags --video_speed and --silent_speed respectively. This snippet shows how to set the video speed to 1.8 times the normal playback and the silent speed to 8 times.

```console
$ python auto-editor.py example.mp4 --video_speed 1.8 --silent_speed 8
```

Alternatively, you can use the short versions:

```console
$ python auto-editor.py example.mp4 -v 1.8 -s 8
```

## Zoom In Automatically
<p align="center">
  <img src="https://github.com/WyattBlue/auto-editor/blob/master/auto_zoom_demo.gif" width="800">
</p>

You can now tell auto-editor to zoom in whenever the video gets especially loud. 

You do that by setting the loudness thershold to a number between 0 (when the video is completely quiet) and 1 (when the video is at its loudest). 0.8 is a good value to set it to.

```console
$ python auto-editor.py example.mp4 --loudness_threshold 0.8
```

(video source from jacksfilms)

## Using Audio File Types

You can use audio formats (.wav, .mp3) instead of just video formats and auto-editor will output an altered version.

```console
$ python auto-editor.py example.wav
```

## Download Video from a Website

Thanks to youtube-dl, you can enter in URL's as your input source instead of local files.

```console
$ python auto-editor.py "https://www.youtube.com/watch?v=kcs82HnguGc"
```

## Other Commands

Get the list of all the other commands by typing in this command.

```console
$ python auto-editor.py --help
```

Auto-Editor will print out all the commands and a brief description on how to use them.


# Installing Auto-Editor
[Installing for Windows](/install_win.md)

[Installing for Mac](/install_mac.md)

[Installing for Linux](/install_lin.md)
