# Installing Auto-Editor for Linux
## Python 3
This project is written in python 3. Check if you have it by running this command in the Terminal.
```terminal
python --version
```

If Terminal says this:

```terminal
command not found: python
```

or this
```terminal
Python 2.7.16
```

you need to install [python 3](https://www.python.org/downloads/).


## FFmpeg
Run this command to install ffmpeg and its dependences.

```terminal
sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg
```

Make sure ffmpeg is on your PATH by running this:

```terminal
ffmpeg -h
```

## Other Dependencies
To install all of the needed dependencies, run this:
```terminal
pip3 install audiotsm pillow pydub opencv-python youtube_dl
```
> This usually takes about 5 minutes.

Wait for all the libraries to install and once that's done, close and reopen Terminal.

## Running Auto-Editor

If you have git, then you can simply run:
```terminal
git clone https://github.com/WyattBlue/auto-editor.git
```

to download the repo or download the zip version [here.](https://github.com/WyattBlue/auto-editor/archive/master.zip)

Run
```terminal
python auto-editor.py --help
```
to test it and if that runs successfully, then congratulations, you have successfully installed auto-editor. See [the docs](/resources/docs.md) for more commands and usages.
