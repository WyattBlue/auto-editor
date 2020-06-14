# Installing Auto-Editor for Windows
## Python 3
This project is written in python 3. Check if you have it by running this command in Command Prompt.
```terminal
python --version
```

If Command Prompt says this:

```terminal
command not found: python
```

or this:
```terminal
Python 2.7.16
```

you need to install [python 3](https://www.python.org/downloads/).

## FFmpeg
Check if you have ffmpeg.

```terminal
ffmpeg -h
```

If not then follow [this guide](https://www.wikihow.com/Install-FFmpeg-on-Windows). Unfortunately, it seems that you cannot install ffmpeg with the path correctly set with only commands. If you know how to do that, please show how in an issue.

## Dependencies
To install all of the needed dependencies, run this:
```terminal
pip3 install scipy audiotsm pillow pydub opencv-python youtube_dl
```

Wait for all the libraries to install and once that's done, close and reopen Command Prompt

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
