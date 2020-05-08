[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)

# Auto-Editor
Auto-Editor is a tool that can find the silent (boring) parts of the video and cut or speed them up.
It works by using ffmpeg to split the video up into the audio and the frames. Calculates the new audio and adds and drops frames where needed, and stiches that back into a video.

This project is a fork of Carykh's inactive [jumpcutter](https://github.com/carykh/jumpcutter). This project seeks to fix the issues (and design flaws) of the original while still following the same general idea and allowing the same parameters.

## Usage
Using auto-editor with its default parameters.

```python auto-editor.py example.mp4```

Download a video in a URL and remove the boring parts.

```python auto-editor.py "https://www.youtube.com/watch?v=kcs82HnguGc"```

speed up a lecture with Carykh's procrastinator settings.

```python auto-editor.py "https://www.youtube.com/watch?v=_PwhiWxHK8o" --video_speed=1.8 --silent_speed=8```

get help on any of the other parameters

```python auto-editor.py --help```

## Download the Libraries and Dependencies
This program is written in Python. Check if you have Python 3 by running.

```python --version```

if your command-line says ```command not found``` or it has the wrong version you need to get Python 3 [from python.org](https://www.python.org/downloads/) and install it.

> Note: ```python``` points to Python 2.7 on macOS but points to Python 3.8 on Linux and Windows. ```python3``` doesn't work on Windows but ```py``` works only on Windows.

Check if you have Homebrew.

```brew --version```

If not then go to https://brew.sh and install Homebrew.

To install all of the needed dependencies, paste this to your command-line.
```
brew update
brew install ffmpeg
brew install youtube-dl
pip3 install numpy scipy audiotsm opencv-python
```
> Note: Be warned that ffmpeg can take up to 15 minutes to install if you do not already have it.

## Installation
Open your command-line and run ```git clone https://github.com/WyattBlue/auto-editor.git```

then run ```cd auto-editor```. This will take you where auto-editor is.

Run ```python auto-editor.py --help``` to make sure your command-line can find the file.

If that runs successfully, then congratulations, you have successfully installed auto-editor. See the usage section for more examples.

## Help 
If it didn't run successfully or if you have any other suggestions or concerns, then feel free to create a new issue on this page. Alternatively, you can discuss the issue in jumpcutter's [official discord.](https://discord.gg/2snkzhy)
