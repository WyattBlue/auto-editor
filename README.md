[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/badge/discord-kMHAWJJ-brightgreen.svg"></a>
<img src="https://img.shields.io/badge/version-20w38a-blue.svg">
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/master/resources/auto-editor_banner.png" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing where sections are silent and making cuts based off that information.


Auto-Editor has a powerful suite of features to make your life easy, including:

<h3 align="center">Using URLs as input directly</h3>
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/experimental/download_url.png" width="600" title="Supports other websites too! Not just YouTube."></p>

<h3 align="center">Exporting to Adobe Premiere and DaVinci Resolve</h2>
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/experimental/resources/premiere_editing.png" width="650" title="Final Cut Pro and a few others might also work."></p>

<h3 align="center">Cross Platform Support</h3>
<p align="center"><img src="https://github.com/WyattBlue/auto-editor/blob/experimental/resources/cross_platform.png" width="600" title="and chromeOS, but they are tricky to set up."></p>

## New Features
The help option has been changed so that it can be chained to any option and it will give more information about that option.

```
auto-editor --video_codec --help
  --preset, -p
    set the preset for ffmpeg to help save file size or increase quality.

    type: str
    default: medium
    choices: ultrafast, superfast, faster, fast, medium, slow, slower, veryslow
```
* the --preset, --tune, --ignore and --cut_out options have been added.
* the default way the video is compressed has been changed so it now uses crf instead of a video bitrate to shrink the file size. The quality should be a lot better now.
* fixed a bug where the program would crash if the output folder is on another drive.


## Usage
Here's how to create an edited version of 'example.mp4' with the default parameters.
```
auto-editor example.mp4
```

You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```
auto-editor example.mp4 --frame_margin 8
```

## Installing
[See Installing](https://github.com/WyattBlue/auto-editor/blob/master/resources/installing.md)

## Documentation
* [See docs](https://github.com/WyattBlue/auto-editor/blob/master/resources/docs.md)
* [See Changelog](https://github.com/WyattBlue/auto-editor/blob/master/resources/CHANGELOG.md) for all the differences between releases.

## Help
The best way to contribute is to [fork auto-editor](https://github.com/WyattBlue/auto-editor/fork) and make changes there. Once you're happy with those changes, make a new pull request and type in a brief description on how you improved the code.

No change is too small whether that be a typo in the docs or a small improvement of code.

## Software Licensing
[See Legal](https://github.com/WyattBlue/auto-editor/blob/master/resources/legalinfo.md)

## Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).

