---
title: Auto-Editor - Install
---

# Installing Auto-Editor

## Method 1 (Recommended)

Step 1, go to the [Releases page](https://github.com/WyattBlue/auto-editor/releases) on GitHub, and download the binary for your platform (Note which folder you've downloaded it too).

Step 2, rename the binary to auto-editor (or auto-editor.exe for Windows)

Step 3, In the terminal/PowerShell, `cd` into your downloads folder.

If you're on MacOS/Linux, run:

```
chmod +x ./auto-editor
```

Step 4, Run Auto-Editor in the terminal. Because the binaries are unsigned, you may get "Unknown developer" warnings. Ignore them.

Step 5, run:

```
./auto-editor --help
```

to verify it's working. It's recommended to place the binary in a PATH directory so that it's available as `auto-editor` no matter your current working directory.


## Method 2: Homebrew
If you're on MacOS (or Linux) run this to install auto-editor:
```
brew install auto-editor
```

Notify the homebrew package maintainers if this doesn't work.

## Method 3: Apt
If you're on a Debian-based Linux distro, run:

```
sudo apt install auto-editor
```

(If you can contact the Debian maintainers, tell them open-cv isn't an auto-editor dependency)


## Method 4: Pip (Deprecated)
First, download and install [Python](https://python.org)
<blockquote><p>If you are installing on Windows, make sure "Add Python 3.14 to PATH" is checked.</p></blockquote>

Once that's done, you should have pip on your PATH. That means when you run `pip3` on your console, you should get a list of commands and not `command not found`. If you don't have pip on your PATH, try reinstalling Python.

Then run:
```
pip install auto-editor
```

Now run this command and it should list all the options you can use
```
auto-editor --help
```

If that works then congratulations, you have successfully installed auto-editor. You can use now use this with any other type of video or audio that you have.
```
auto-editor C:path\to\your\video.mp4
```

If you would like to uninstall auto-editor, run:
```
pip uninstall auto-editor
```

## Optional Dependencies
If yt-dlp is installed, auto-editor can download and use URLs as inputs.
```
auto-editor "https://www.youtube.com/watch?v=kcs82HnguGc"
```
