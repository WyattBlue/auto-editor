[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w32a</sup>

<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/master/resources/auto-editor_banner.png" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing where sections are silent and making cuts based off that information.

## New in 20w32a
 * `--export_to_resolve` added. This option creates an XML that can be imported by DaVinci Resolve. Go to File > Import Timeline > Import AAF, EDL, XML and choose the XML Auto-Editor just created.
 * `--background_music`, `--background_volume`, and `--zoom_threshold` have been removed. `--background_music` was rarely used and it was not any more convenient than using a traditional editor. It was never obvious where `--zoom_threshold` would choose to zoom so it wasn't very helpful for editing. Removing those options also made it possible to delete three hundred lines of code and remove two modules.
 * New option added `--video_codec`, which does what you think it does. It is set to "copy" as the default but can be changed to "h264" and others so the output size is a lot smaller.

#### Bug Fixes
 * Preview now prints chunks values in debug mode.
 * Using audio files with `--export_to_premiere` no longer causes an error by referencing a non-existent variable.
 * If you input an invalid argument for `--hardware_accel`, it will now stop before causing problems and will list valid arguments instead. Unfortunately, there isn't any use for this option right now, so it has been moved to depreciated.

[See the Changelog](https://github.com/WyattBlue/auto-editor/blob/master/resources/CHANGELOG.md) for all the differences between releases.

## Usage

Auto-Editor is used by many people, including youtubers who want to edit their long livestream quickly, editors to make a base before tweaking the cuts so that it feels just right, and regular viewers who want to make their boring lectures more enjoyable.

Here's how you create an edited version of example.mp4 with the default parameters.
```terminal
auto-editor example.mp4
```

You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```terminal
auto-editor example.mp4 --frame_margin 8
```

There are many more features in auto-editor, including **adding in background music** that automatically gets quieter, and **zooming in** the video when it gets especially loud.

[See the docs](https://github.com/WyattBlue/auto-editor/blob/master/resources/docs.md) for more commands and usages.

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


## Upgrading

```terminal
pip3 install auto-editor --upgrade
```

## Contributing
The best way to contribute is to [fork auto-editor](https://github.com/WyattBlue/auto-editor/fork) and make changes there. Once you're happy with those changes, make a new pull request and type in a brief description on how you improved the code.

No change is too small whether that be a typo in the docs or a small improvement of code.

## Licensing
The FFmpeg binaries are under the [LGPL License](https://github.com/WyattBlue/auto-editor/blob/master/auto_editor/win-ffmpeg/LICENSE.txt)

wavfile.py is under the [BSD 3-Clause "New" or "Revised" License](https://github.com/scipy/scipy/blob/master/LICENSE.txt)

Everything else in auto-editor is under the [MIT License](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) and was made by [these people.](https://github.com/WyattBlue/auto-editor/blob/master/resources/CREDITS.md)

## Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).
