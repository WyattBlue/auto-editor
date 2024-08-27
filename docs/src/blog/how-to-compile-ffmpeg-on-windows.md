---
title: How to Compile FFmpeg on Windows
author: WyattBlue
date: April 18, 2023
desc: Open the Windows Terminal application, go to `C:/`, then run `git clone https://github.com/m-ab-s/media-autobuild_suite`. Since Windows has a strict filename length limit, we'll need to shorten the directory name.
---
## Prerequisites
 * Windows 10 or greater
 * Windows Terminal
 * git

## Installing Media Autobuild Suite
Open the Windows Terminal application, go to `C:/`, then run:

```
git clone https://github.com/m-ab-s/media-autobuild_suite
```

Since Windows has a strict filename length limit, we'll need to shorten the directory name.

```
mv media-autobuild_suite ab-suite
```

then, we'll `cd` into the directory.

## The Questionnaire
Run `./media-autobuild_suite.bat`, the script will prompt you questions which you will answer with typing a number, then pressing enter.

For a light-weight ffmpeg, I recommend saying no to including third-party libraries except libmp3lame, libopen264, and maybe rav1e and dav1d (The av1 encoder and decoder respectively).

Don't worry about choosing an answer you'll regret later. You can change your answers after by editing the `./build/media-autobuild_suite.ini` file.

## Compiling Options
Before installing all tools and compiling, the script will give you a chance to edit `./build/ffmpeg_options.txt`. Delete everything in that file and put:

```
--disable-autodetect  # Don't automatically add libraries
--enable-small        # Reduce filesize in final binaries
--enable-version3     # Use the LGPLv3 License
--enable-libopenh264
--enable-librav1e
--disable-debug
--disable-doc
--disable-shared     # Keep everything self-contained
--disable-network    # Disables the ability to use http/other network protocols
--disable-indevs     # Disables ffmpeg's (rather sketchy) recording capabilities
--disable-outdevs    # Don't include any output devices
--disable-ffplay     # Also disables the sdl library
```

These are the most important options for building a light-weight, copyright-compliant ffmpeg and ffprobe binaries.

After you finish answering, the script will install all the compiling tools needed. It will take a while to install everything, but you'll only need to do it once. You'll find the output at `./local64/bin-video`

