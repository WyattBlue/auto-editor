# Installing Auto-Editor

Download and Install [Python 3](https://www.python.org/downloads/).

> If you are installing on Windows, make sure "Add Python 3.10 to PATH" is checked.

Once that's done, you should have pip on your PATH. That means when you run `pip3` on your console, you should get a list of commands and not `command not found`. If you don't have pip on your PATH, try reinstalling Python.

Then run:
```
pip install --upgrade pip
```

to upgrade pip to the latest version. Then use pip to install auto-editor:

```
pip install auto-editor
```

> Linux users: you will need to have FFmpeg installed and on your PATH.

Now run this command and it should list all the options you can use.

```
auto-editor --help
```

If that works then congratulations, you have successfully installed auto-editor. You can use now use this with any other type of video or audio that you have.

```
auto-editor C:path\to\your\video.mp4
```

About every 1 or 2 weeks, a new version will be available. It's recommended that you stay up to date so you always get the latest improvements and bug fixes. Upgrade by running:


```
pip install auto-editor --upgrade
```

Run this to uninstall auto-editor:

```
pip uninstall auto-editor
```


----

## Installing from Source

Use git to download the repository:

```terminal
pip install git+https://github.com/WyattBlue/auto-editor.git
```

Then run the local version using `py` or `python3`
```
python3 -m auto_editor example.mp4 --frame-margin 7
```

----

## Dependencies

If auto-editor could not be installed because a dependency couldn't be installed. Run:

```
pip install auto-editor --no-deps
```

```
pip install numpy
pip install av
pip install Pillow
pip install yt-dlp
```

### numpy

Foundational math module needed for handling large data. Must be installed for any use with auto-editor.

### av

Retrieve low level video data in a form auto-editor can natively use. Allows for very fast rendering of videos.

### Pillow

Render video objects like text and ellipses.

### yt-dlp

Module used to download videos off of websites.
