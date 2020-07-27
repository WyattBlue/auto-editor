[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w30b hotfix

<p align="center">
  <img src="https://github.com/WyattBlue/auto-editor/blob/master/resources/auto-editor_banner.png" width="700">
</p>


**Auto-Editor** is a command line application for automatically **editing video and audio** by removing the silent parts.

## New in 20w30b

 * fastVideoPlus and fastVideo have been combined.
 * Auto-Editor is now a proper command line program. You can now download **everything** with pip.

#### Hotfix
 * fixed macOS FFmpeg binaries not working unless the user already installed ffmpeg at some point.
 * fixed premiere.py searching for the width and height of an audio file.

[See the Changelog](/resources/CHANGELOG.md) for all the differences between releases.

## Usage
Create an edited version of example.mp4 with the default parameters.
```terminal
auto-editor example.mp4
```

You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```terminal
auto-editor example.mp4 --frame_margin 8
```

There are many more features in auto-editor, including **adding in background music** that automatically gets quieter, and **zooming in** the video when it gets especially loud.


## Installing Auto-Editor
 1. Download and Install the Latest Version of [Python 3](https://www.python.org/downloads/).

```terminal
pip3 install auto-editor
```

The binaries you'll need are already installed, unless you're using Linux.
Linux users need to run this command. `sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg`

Now run it with the example video to make sure it is working.

```terminal
auto-editor example.mp4
```

If that works then congratulations, you have successfully installed auto-editor. You can use now use this with any other type of video or audio that you have.

```terminal
auto-editor C:path\to\your\video
```

[See the docs](/resources/docs.md) for more commands and usages.


## Upgrading

```terminal
pip3 install auto-editor --upgrade
```

## Contributing
The best way to contribute is to [fork auto-editor](https://github.com/WyattBlue/auto-editor/fork) and make changes there. Once you're happy with those changes, make a new pull request and type in a brief description on how you improved the code.

No change is too small whether that be a typo in the docs or a small improvement of code.

## Licensing
The FFmpeg binaries are under the [LGPL License](/scripts/win-ffmpeg/LICENSE.txt)

wavfile.py is under the [BSD 3-Clause "New" or "Revised" License](https://github.com/scipy/scipy/blob/master/LICENSE.txt)

Everything else in auto-editor is under the [MIT License](/LICENSE)

## Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).
