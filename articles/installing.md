# Installing Auto-Editor

Download and Install [Python 3.9](https://www.python.org/downloads/release/python-397/). The best version for auto-editor.

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

About every 1 or 2 weeks, a new version will be available. It's recommended that you stay up to date so you always get the latest improvements and bug fixes. Upgrade by running:


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

Then run the local version using `py` or `python3`
```
python3 -m auto_editor example.mp4 --frame_margin 7
```

----

## Dependencies

If auto-editor could not be installed because a dependency couldn't be installed. Run:

```
pip3 install auto-editor --no-deps
```

```
pip3 install numpy
pip3 install av
pip3 install youtube-dl
```

### Numpy

Foundational math module needed for handling large data. Must be installed for any use with auto-editor.

### Av

Retrieve video data in a form Python can natively use. Allows for very fast rendering of videos.

### Youtube-dl

Public domain module used to download videos off of websites. When installed, always auto-editor to support URL inputs.


----

## Pitfalls to Avoid

If you get an error like this:
```
  File "<stdin>", line 1
    pip3 install auto-editor
         ^
SyntaxError: invalid syntax
```

It means you are incorrectly running pip in the Python interpreter. Run `quit()` to go back to the regular console.


If running auto-editor causes an error message to appear like this:

```
  File "auto_editor/__main__.py", line 56
    def add_argument(*names, nargs=1, type=str, default=None,
                                 ^
SyntaxError: invalid syntax
```

It's because you're using a version of Python that's too old. Auto-Editor will on work on Python versions 3.6 or greater. Older versions may cause an invalid syntax error message to pop up.
