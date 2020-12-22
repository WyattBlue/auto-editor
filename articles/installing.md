# Installing Auto-Editor

> You probably have Python already installed on your computer, but install it again anyway. Modern Python has some important utilities like pip that need to be installed to.

Download the [Python 3 Installer](https://www.python.org/downloads/) and install Python. If you are installing on Windows, make sure the "Add Python 3.9 to PATH" is checked.

Once that's done, you should have pip on your PATH. That means when you run `pip3` on your console, you should get a list of commands and not `command not found`. If you don't have pip on your PATH, try reinstalling Python.

Then run: `pip3 install --upgrade pip` to upgrade Pip to the latest version.


> FFmpeg for Windows and MacOS is already installed, but Linux users will need to install it seperately. This command should work for most distros: `sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg`

After upgrading pip, run `pip3 install auto-editor` and wait for pip to finish.

Now run this command and it should list all the commands and options you can use.

```
auto-editor -h
```

If that works then congratulations, you have successfully installed auto-editor. You can use now use this with any other type of video or audio that you have.

```
auto-editor C:path\to\your\video
```

Upgrading is simple, just run:
```
pip3 install auto-editor --upgrade
```


## Pitfalls to Avoid

If you get an error like this:
```
  File "<stdin>", line 1
    pip3 install auto-editor
         ^
SyntaxError: invalid syntax
```

It means you are incorrectly running pip in the Python interpretor instead of running the command on the console. Run `quit()` to get kicked out of the Python interpretor, and to the console.



If running auto-editor causes an error message to appear like this:
```
  File "auto_editor/__main__.py", line 56
    def add_argument(*names, nargs=1, type=str, default=None,
                                 ^
SyntaxError: invalid syntax
```
It's because you're using a version of Python that's too old. Auto-Editor will on work on Python versions >=3.6 . Anything else will cause weird invalid syntax error messages to pop up.


## Installing from Source

Use git to download the repository:

```terminal
git clone https://github.com/WyattBlue/auto-editor.git
cd auto-editor
```


Then run \_\_main\_\_.py with python.
```
python auto_editor/__main__.py example.mp4 [add your options here]
```

> MacOS/Linux users might need to use python3 instead of python.
