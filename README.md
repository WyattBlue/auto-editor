[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/badge/discord-kMHAWJJ-brightgreen.svg"></a>
<img src="https://img.shields.io/badge/version-20w38a-blue.svg">
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/auto-editor_banner.png" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing where sections are silent and making cuts based off that information.


Auto-Editor has a powerful suite of features to make your life easy, including:

<h3 align="center">Using URLs as input directly</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/download_url.png" width="600" title="Supports other websites too! Not just YouTube."></p>

<h3 align="center">Exporting to Adobe Premiere and DaVinci Resolve</h2>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/premiere_editing.png" width="700" title="Final Cut Pro and a few others might also work."></p>

<h3 align="center">Cross Platform Support</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/cross_platform.png" width="600" title="and chromeOS, but they are tricky to set up."></p>

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
* the options `--preset` and `--tune` have been added. They are for allowing finer compression with FFmpeg and they work pretty much the same way.

`--ignore` and `--cut_out` options have been added. Cut out means get rid of this part of the video. Ignore means ignore editing this section, don't cut anything out. Both use a new data type called **range syntax**,
so `0-20` selects the first 20 seconds (not frames) of a video, and `45-55.3` selects the 45th second to the 55.3 second. There's also a special value that is the length of the video. `30-end` selects the 30th second all the way to the end of the video.


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
* [See Docs](https://github.com/WyattBlue/auto-editor/blob/master/resources/docs.md)
* [See Changelog](https://github.com/WyattBlue/auto-editor/blob/master/resources/CHANGELOG.md) for all the differences between releases.

## Help
The best way to help is to tell other people about this project. You may put something like Edited using auto-editor. (https://github.com/WyattBlue/auto-editor) in the video description.

Auto-Editor is an open-source project so anyone can suggest changes, including you! Create a personal fork of the project, implement your fix/feature, then target the `experimental` branch if there is one, else go for `master`. 

No change is too small whether that be a typo in the docs or a small improvement of code.

## Software Licensing
[See Legal](https://github.com/WyattBlue/auto-editor/blob/master/resources/legalinfo.md)

## Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).

