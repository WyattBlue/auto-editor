---
title: Installing Auto-Editor
---

## Method 1 (Recommended)
Get the official binary, available on Windows, macOS, and Linux.

 1. Go to the [Releases page](https://github.com/WyattBlue/auto-editor/releases) on GitHub, and download the binary for your platform.
 2. Rename the binary to auto-editor (or auto-editor.exe for Windows).
 3. `cd` into your downloads folder. If on macOS/Linux, run `chmod +x ./auto-editor` first.
 4. Run Auto-Editor in the terminal. Because the binaries are unsigned, you may get "Unknown developer" warnings. Ignore them.

Congratulations, auto-editor should now be installed. To verify auto-editor is installed, run:

```sh
./auto-editor --help
```

It's recommended to place the binary in a PATH directory so that `auto-editor` is always available no matter your current working directory.

## Method 2: Platform Installers
If you're on macOS, use [Homebrew](https://brew.sh):
```sh
brew install auto-editor
```

Auto-Editor is available on the Arch Linux AUR:

```sh
yay -S auto-editor
```

### Notice for Pip Users
The auto-editor cli is no longer being published on pip. It is recommended to switch to a different installation method.

### Notice for 'Apt' Users
The pkg versions available are very old. Either use the official binaries (recommened) or use [Homebrew for Linux](https://docs.brew.sh/Homebrew-on-Linux).

## Installing from Source (Unix-Like):
Install `nim`, `nimble`, `cmake`, `meson`, `ninja`, then run:

```sh
nimble makeff  # Downloads and builds all dependencies
nimble make  # Build statically
```

or build dynamically

```sh
# Needs ffmpeg libs installed.
nimble brewmake
```

## Installing from Source (Windows)
To build an `.exe`, you'll need [WSL](https://learn.microsoft.com/en-us/windows/wsl/about). In that environment, install `nim`, `nimble`, `cmake`, `meson`, `ninja`, then run:

```sh
nimble makeffwin
nimble makewin
```

For Windows ARM, run:

```sh
nimble makeffwinarm
nimble makewinarm
```

## Optional Dependencies
If yt-dlp is installed, auto-editor can download and use URLs as inputs.
```sh
auto-editor "https://www.youtube.com/watch?v=kcs82HnguGc"
```

How yt-dlp is installed does not matter.

<a class="next" href="/docs/cookbook">Next: Cookbook</a>
