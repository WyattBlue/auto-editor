---
title: Auto-Editor - Install
---

# Installing Auto-Editor

## Method 1 (Recommended)
Get the offical binary, available on Windows, MacOS, and x86_64 Linux.

 1. go to the [Releases page](https://github.com/WyattBlue/auto-editor/releases) on GitHub, and download the binary for your platform.

 2. rename the binary to auto-editor (or auto-editor.exe for Windows).

 3. In the terminal/PowerShell, `cd` into your downloads folder.

If you're on MacOS/Linux, run:

```
chmod +x ./auto-editor
```

 4. Run Auto-Editor in the terminal. Because the binaries are unsigned, you may get "Unknown developer" warnings. Ignore them.

Congratulations, auto-editor should now be installed. To verify auto-editor is installed, run:

```
./auto-editor --help
```

It's recommended to place the binary in a PATH directory so that `auto-editor` is always available no matter your current working directory.


## Method 2: Platform Installers
If you're on MacOS, it's recommend to use [Homebrew](https://homebrew.sh):
```
brew install auto-editor
```

Auto-Editor is available on apt:

```
sudo apt install auto-editor
```

Auto-Editor is avaiable on the Arch Linux AUR:

```
yay -S auto-editor
```

## Method 3: Pip

Notice: It is not recommned to use this method because new versions of auto-editor are no longer being published on pip.

First, download and install [Python](https://python.org)
<blockquote><p>If you are installing on Windows, make sure "Add Python 3.x to PATH" is checked.</p></blockquote>

Once that's done, you should have pip on your PATH. That means when you run `pip` on your console, you should get a list of commands and not `command not found`. If you don't have pip on your PATH, try reinstalling Python.

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

## Installing from Source (unix-like):

Install nim, make sure `nimble` is available. You'll also need cmake, meson, and ninja.

```
nimble makeff  # Downloads and builds all dependencies
nimble make
```

## Installing from Source (Windows)
To build an `.exe`, you'll need to install [WSL](https://learn.microsoft.com/en-us/windows/wsl/about), then install nim on that environment. Make sure `nimble` is available. You'll also need cmake, meson, and ninja.

Then run:

```
nimble makeffwin
nimble windows
```

## Optional Dependencies
If yt-dlp is installed, auto-editor can download and use URLs as inputs.
```
auto-editor "https://www.youtube.com/watch?v=kcs82HnguGc"
```

How yt-dlp is installed does not matter.
