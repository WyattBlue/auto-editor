---
title: Auto-Editor - Install
---

# Installing Auto-Editor

## Method 1 (Recommended)
Get the official binary, available on Windows, MacOS, and Linux.

 1. Go to the [Releases page](https://github.com/WyattBlue/auto-editor/releases) on GitHub, and download the binary for your platform.

 2. Rename the binary to auto-editor (or auto-editor.exe for Windows).

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
If you're on MacOS, use [Homebrew](https://homebrew.sh):
```
brew install auto-editor
```

Auto-Editor is available on the Arch Linux AUR:

```
yay -S auto-editor
```

### Notice for Pip Users
The auto-editor cli is no longer being published on pip. It is recommended to switch to a different installation method.

### Notice for 'Apt' Users
The pkg versions available are very old. Either use the official binaries (recommened) or use [Homebrew for Linux](https://docs.brew.sh/Homebrew-on-Linux).

## Installing from Source (Unix-Like):

Install nim, make sure `nimble` is available. You'll also need cmake, meson, and ninja.

```
nimble makeff  # Downloads and builds all dependencies
nimble make  # Build statically
```

or build dynamically

```
# Needs ffmpeg libs installed.
nimble brewmake
```

## Installing from Source (Windows)
To build an `.exe`, you'll need to install [WSL](https://learn.microsoft.com/en-us/windows/wsl/about), then install nim on that environment. Make sure `nimble` is available. You'll also need cmake, meson, and ninja.

Then run:

```
nimble makeffwin
nimble windows
```

For ARM, run:

```
nimble makeffwinarm
nimble windowsarm
```

## Optional Dependencies
If yt-dlp is installed, auto-editor can download and use URLs as inputs.
```
auto-editor "https://www.youtube.com/watch?v=kcs82HnguGc"
```

How yt-dlp is installed does not matter.
