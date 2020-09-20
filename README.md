[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/badge/discord-kMHAWJJ-brightgreen.svg"></a>
<img src="https://img.shields.io/badge/version-20w38a-blue.svg">
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/master/resources/auto-editor_banner.png" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing where sections are silent and making cuts based off that information.

Auto-Editor has a powerful suite of features to make your life easy that can:


<h3 align="center">Run on Any Platform</h3>
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/experimental/resources/cross_platform.png" width="600">


<h3 align="center">Export to your Favorite Editing Software.</h2>
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/experimental/resources/premiere_editing.png"><br><span style="color: gray">Including Adobe Premiere Pro and DaVinci Resolve</span></p>

## New in 20w38a
* argparse has been replaced with a custom parser that can be expanded upon more easily one change that has is the ability for the help option to give specific instructions if it's next to another option.
* the --preset, --tune, --ignore and --cut_out options have been added.
* the default way the video is compressed has been changed so it now uses crf instead of a video bitrate to shrink the file size. The quality should be a lot better now.
* fixed a bug where the program would crash if the output folder is on another drive.

[See the Changelog](https://github.com/WyattBlue/auto-editor/blob/master/resources/CHANGELOG.md) for all the differences between releases.

## Usage
Auto-Editor is used by many people, including youtubers who want to edit their long livestream quickly, editors to make a base before tweaking the cuts so that it feels just right, and regular viewers who want to make their boring lectures more enjoyable.

Here's how you create an edited version of example.mp4 with the default parameters.
```
auto-editor example.mp4
```

You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```
auto-editor example.mp4 --frame_margin 8
```

There are many more features in auto-editor, including **adding in background music** that automatically gets quieter, and **zooming in** the video when it gets especially loud.

[See the docs](https://github.com/WyattBlue/auto-editor/blob/master/resources/docs.md) for more commands and usages.

## Installing Auto-Editor
Download and install the latest version of [Python 3](https://www.python.org/downloads/), then run `pip3 install auto-editor` on your console then run

The binaries you'll need are already installed, unless you're using Linux.
Linux users need to run this command. `sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg`

Now run it with the example video to make sure it is working.

```
auto-editor example.mp4
```

If that works then congratulations, you have successfully installed auto-editor. You can use now use this with any other type of video or audio that you have.

```
auto-editor C:path\to\your\video
```

## Upgrading
```
pip3 install auto-editor --upgrade
```

## Contributing
The best way to contribute is to [fork auto-editor](https://github.com/WyattBlue/auto-editor/fork) and make changes there. Once you're happy with those changes, make a new pull request and type in a brief description on how you improved the code.

No change is too small whether that be a typo in the docs or a small improvement of code.

## Software Licensing
[See Legal Info](https://github.com/WyattBlue/auto-editor/blob/master/resources/legalinfo.md)

## Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).