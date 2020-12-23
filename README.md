[![Actions Status](https://github.com/wyattblue/auto-editor/workflows/test-program/badge.svg)](https://github.com/wyattblue/auto-editor/actions)
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/discord/711767814821773372?color=%237289DA&label=chat&logo=discord&logoColor=white"></a>
<img src="https://img.shields.io/badge/version-20w52a-blue.svg">
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/articles/imgs/auto-editor_banner.png" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing where sections are silent and cutting them up.

When editing videos, before you do the real editing, you first cut out the "dead space" which is typically just silence. This is typically known as a "first pass". Cutting all these dead spaces is a boring task, especially if the video is 15 minutes, 30 minutes, or even an hour long.

Luckily, this can be automated with software. [Once you'll installed auto-editor](https://github.com/WyattBlue/auto-editor/blob/master/articles/installing.md), you can run:

```
auto-editor path/to/your/video.mp4
```

from your console and it will generate a **brand new video** with all the silent sections cut off. Generating a new video **takes a while** so instead, you can export the new video to your editor directly. For example, running:

```
auto-editor path/to/your/video.mp4 --export_to_premiere
```

Will create an XML file that can be imported to Adobe Premiere Pro. This is **much much faster** than generating a new video (takes usually seconds). DaVinici Resolve and Final Cut Pro are also supported.

Auto-Editor has a powerful set of features, including:

<h3 align="center">Analyzing where the video has lots of motion and cutting based on that.</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/articles/imgs/m_detection.png" width="700" title="See How to Use Motion Detection in Auto-Editor"></p>

<h3 align="center">Exporting to Adobe Premiere and DaVinci Resolve</h2>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/articles/imgs/premiere_editing.png" width="700" title="Final Cut Pro and a few others might also work."></p>

<h3 align="center">Full Cross Platform Support</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/articles/imgs/cross_platform.png" width="500" title="and chromeOS, but they are tricky to set up."></p>

## Usage
Here's how to create an edited version of 'example.mp4' with the default parameters.
```
auto-editor example.mp4
```

You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```
auto-editor example.mp4 --frame_margin 8
```

## Articles
 - [How to Install Auto-Editor](https://github.com/WyattBlue/auto-editor/blob/master/articles/installing.md)
 - [How to Use Motion Detection in Auto-Editor](https://github.com/WyattBlue/auto-editor/blob/master/articles/motionDetection.md)

## Contributing
Auto-Editor is an open to all levels of contributions. Learn how to make a contribution.

 - [Contributing for Beginners](https://github.com/WyattBlue/auto-editor/blob/mastesr/articles/contributeBeginner.md)
 - [Contributing for Advanced Users](https://github.com/WyattBlue/auto-editor/blob/mastesr/articles/contributeAdvanced.md)

No change is too small whether that be a typo in the docs or a small improvement of code.

## Copyright
Auto-Editor is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) but contains non-free elements. See [this page](https://github.com/WyattBlue/auto-editor/blob/master/articles/legalinfo.md) for more info.

## Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) here. If you'll like to discuss this project, suggest new features, or chat with other users, you can use [the discord server](https://discord.com/invite/kMHAWJJ).