[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w2a
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
## Download the Libraries and Dependencies
This project is written in Python3. Check if you have it by typing in
`python --version`

if your command-line says ```command not found``` or it has the wrong version you need to get Python 3 [from python.org](https://www.python.org/downloads/) and install it.

> Note: `python` points to Python 2.7 on macOS but points to Python 3.8 on Linux and Windows. `python3` doesn't work on Windows but `py` works only on Windows.

Check if you have Homebrew.

`brew --version`

If not then go to https://brew.sh and install Homebrew.

To install all of the needed dependencies, paste this to your command-line.
```
brew update
brew install ffmpeg
brew install youtube-dl
pip3 install scipy audiotsm pillow
```
> Note: Be warned that ffmpeg can take up to 15 minutes to install if you do not already have it.

## Running Auto-Editor on your Terminal

Open your command-line and run `git clone https://github.com/WyattBlue/auto-editor.git`

then run `cd auto-editor`. This will take you where auto-editor is.

Run `python auto-editor.py --help` to make sure your command-line can find the file.

If that runs successfully, then congratulations, you have successfully installed auto-editor. See the usage section for more examples.

# Help 
If you can't figure out how to install this or you have any other suggestions or concerns, then create a new issue on project with the details.
