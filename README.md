[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/badge/discord-kMHAWJJ-brightgreen.svg"></a>
<img src="https://img.shields.io/badge/version-20w33a-blue.svg">
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/master/resources/auto-editor_banner.png" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing where sections are silent and making cuts based off that information.

## New in 20w33a
* the default for `--sample_rate` is now the same as the input.
* the default `--video_codec` is now the same as the video.
* the `--hardware_accel` option has been removed because it is not used anywhere in the program.

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

## Legal
Auto-Editor, nor any of its dependencies, claims any copyright over any **output file** it produces. All rights are reserved to you.


If you wish to use the **source code or binaries** of this project, you need to acknowledge auto-editors dependencies if they are present.


Both ffmpeg binaries are under the [LGPLv3 License](https://github.com/WyattBlue/auto-editor/blob/master/auto_editor/win-ffmpeg/LICENSE.txt)

wavfile.py is under the [BSD 3-Clause "New" or "Revised" License](https://github.com/scipy/scipy/blob/master/LICENSE.txt)

Everything else in auto-editor is under the [MIT License](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) and was made by [these people.](https://github.com/WyattBlue/auto-editor/blob/master/resources/CREDITS.md)

## Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).