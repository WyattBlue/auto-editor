[![Actions Status](https://github.com/wyattblue/auto-editor/workflows/test-program/badge.svg)](https://github.com/wyattblue/auto-editor/actions)
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/discord/711767814821773372?color=%237289DA&label=chat&logo=discord&logoColor=white"></a>
<img src="https://img.shields.io/badge/version-20w52a-blue.svg">
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/auto-editor_banner.png" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing where sections are silent and cutting them up.


Auto-Editor has a powerful set of features, including:

<h3 align="center">Analyzing where the video has lots of motion and cutting based on that.</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/m_detection.png" width="700" title="See How to Use Motion Detection in Auto-Editor"></p>

<h3 align="center">Exporting to Adobe Premiere and DaVinci Resolve</h2>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/premiere_editing.png" width="700" title="Final Cut Pro and a few others might also work."></p>

<h3 align="center">Full Cross Platform Support</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/resources/cross_platform.png" width="500" title="and chromeOS, but they are tricky to set up."></p>

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

## Articles
 - [How to Use Motion Detection in Auto-Editor](https://github.com/WyattBlue/auto-editor/blob/master/resources/motionDetection.md)

## Contributing
Auto-Editor is an open-source project so anyone can suggest changes, including you! Create a personal fork of the project, implement your fix/feature, then target the `experimental` branch if there is one, else go for `master`.

No change is too small whether that be a typo in the docs or a small improvement of code.

## Copyright
Auto-Editor is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) but contains non-free elements. See [This Page](https://github.com/WyattBlue/auto-editor/blob/master/resources/legalinfo.md) for more info.

## Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).