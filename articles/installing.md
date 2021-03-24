# Installing Auto-Editor

> You probably have Python already on your computer, but install it again anyway. Modern Python has important utilities like pip that need to be installed too.

Download and Install [Python 3](https://www.python.org/downloads/).

> If you are installing on Windows, make sure "Add Python 3.9 to PATH" is checked.

Once that's done, you should have pip on your PATH. That means when you run `pip3` on your console, you should get a list of commands and not `command not found`. If you don't have pip on your PATH, try reinstalling Python.

Then run:
```
pip3 install --upgrade pip
```

to upgrade pip to the latest version.


:warning: | Windows users need to install [Visual Studio](https://visualstudio.microsoft.com/vs/features/cplusplus/) to compile the C program, opencv.
:---: | :---

After upgrading pip, run:

```
pip3 install auto-editor
```

> Linux users will need to install FFmpeg. This command should work for most distros: `sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg`

Now run this command and it should list all the options you can use.

```
auto-editor -h
```

If that works then congratulations, you have successfully installed auto-editor. You can use now use this with any other type of video or audio that you have.

```
auto-editor C:path\to\your\video.mp4
```

Upgrading is simple, just run:
```
pip3 install auto-editor --upgrade
```

Run this to uninstall auto-editor:
```
pip3 uninstall auto-editor
```


----

## Installing from Source

Use git to download the repository:

```terminal
git clone https://github.com/WyattBlue/auto-editor.git
cd auto-editor
```

Then run the local version using `python` or `python3`
```
python -m auto_editor example.mp4 --frame_margin 7
```

----

## Dependencies

If auto-editor could not be installed because a dependency couldn't be installed. Run:

```
pip3 install auto-editor --no-deps
```

```
pip3 install numpy
pip3 install audiotsm2
pip3 install av
pip3 install opencv-python
pip3 install youtube-dl
pip3 install requests
```

### Numpy

Foundational math module needed for handling large data. Must be installed for any use with auto-editor.

### Av

Retrieve video data in a form Python can natively use. Allows for very fast rendering of videos.

### Audiotsm2

The lead developer's own fork of audiotsm. Used for making new audio files at a different speed. Recommended to be installed by all users but not required if `--video_speed` or `--silent_speed` are never used.

### Opencv-Python

Sometimes referred to as opencv or cv2. This module is used to determine where motion happens.

### Youtube-dl

Public domain module used to download videos off of websites. When installed, always auto-editor to support URL inputs. i.e

### Requests

https module used to check there's a new version of auto-editor. Not necessary for anything else.




----

## Pitfalls to Avoid

If you get an error like this:
```
  File "<stdin>", line 1
    pip3 install auto-editor
         ^
SyntaxError: invalid syntax
```

It means you are incorrectly running pip in the Python interpretor. Run `quit()` to go back to the regular console.


If running auto-editor causes an error message to appear like this:
```
  File "auto_editor/__main__.py", line 56
    def add_argument(*names, nargs=1, type=str, default=None,
                                 ^
SyntaxError: invalid syntax
```
It's because you're using a version of Python that's too old. Auto-Editor will on work on Python versions 3.6 or greater. Anything else will cause an invalid syntax error messages to pop up.
