<p align="center"><img src="https://raw.githubusercontent.com/wyattblue/auto-editor/master/site/src/img/auto-editor-banner.webp" title="Auto-Editor" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing a variety of methods, most notably audio loudness.

---

[![Actions Status](https://github.com/wyattblue/auto-editor/workflows/build/badge.svg)](https://github.com/wyattblue/auto-editor/actions)
<a href="https://github.com/psf/black"><img alt="Code style: black" src="https://img.shields.io/badge/code%20style-black-000000.svg"></a>
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/discord/711767814821773372?color=%237289DA&label=chat&logo=discord&logoColor=white"></a>

Before doing the real editing, you first cut out the "dead space" which is typically silence. This is known as a "first pass". Cutting these is a boring task, especially if the video is very long.

```
auto-editor path/to/your/video.mp4
```

<h2 align="center">Installing</h2>

```
pip install auto-editor
```

See [Installing](https://auto-editor.com/installing) for additional information.


<h2 align="center">Cutting</h2>

Change the **pace** of the edited video by using `--margin`.

`--margin` adds in some "silent" sections to make the editing feel nicer. Setting `--margin` to `0.2sec` will add up to 0.2 seconds in front of and 0.2 seconds behind the original clip.

```
auto-editor example.mp4 --margin 0.2sec
```

<h3>Working With Multiple Audio Tracks</h3>
By default, only the first audio track will used for editing (track 0). You can change this with these commands.

Use all audio tracks for editing:
```
auto-editor multi-track.mov --edit audio:stream=all
```

Use only the second, fourth, and sixth audio track:
```
# track numbers start at 0
auto-editor so-many-tracks.mp4 --edit "(or audio:stream=1 audio:stream=3 audio:stream=5)"
```

<h3>Methods for Making Automatic Cuts</h3>

The `--edit` option is how auto-editor makes automated cuts.

For example, edit out motionlessness in a video by setting `--edit motion`.

```
# cut out sections where percentage of motion is less than 2.
auto-editor example.mp4 --edit motion:threshold=2%

# --edit is set to "audio:threshold=4%" by default.
auto-editor example.mp4

# Different tracks can be set with different attribute.
auto-editor multi-track.mov --edit "(or audio:stream=0 audio:threshold=10%,stream=1)"
```

Different editing methods can be used together.
```
# 'threshold' is always the first argument for edit-method objects
auto-editor example.mp4 --edit "(or audio:3% motion:6%)"
```


<h3>See What Auto-Editor Cuts Out</h3>

To export what auto-editor normally cuts out. Set `--video-speed` to `99999` and `--silent-speed` to `1`. This is the reverse of the usual default values.  

```
auto-editor example.mp4 --video-speed 99999 --silent-speed 1
```

<h2 align="center">Exporting to Editors</h2>

Create an XML file that can be imported to Adobe Premiere Pro using this command:

```
auto-editor example.mp4 --export premiere
```

Auto-Editor can also export to:

- Final Cut Pro with `--export final-cut-pro`
- ShotCut with `--export shotcut`

Other editors, like Sony Vegas, can understand the `premiere` format. If your favorite editor doesn't, you can use ` --export clip-sequence` which creates many video clips that can be imported and manipulated like normal.

<h2 align="center">Manual Editing</h2>

Use the `--cut-out` option to always remove a section.

```
# Cut out the first 10 seconds.
auto-editor example.mp4 --cut-out start,10sec

# Cut out the first 10 frames.
auto-editor example.mp4 --cut-out start,10

# Cut out the last 10 seconds.
auto-editor example.mp4 --cut-out -10sec,end

# Cut out the first 10 seconds and cut out the range from 15 seconds to 20 seconds.
auto-editor example.mp4 --cut-out start,10sec 15sec,20sec
```

And of course, all the audio cuts still apply.

If you don't want **any automatic cuts**, use `--edit none`

```
# Cut out the first 5 seconds, leave the rest untouched.
auto-editor example.mp4 --edit none --cut-out start,5sec

# Leave in the first 5 seconds, cut everything else out.
auto-editor example.mp4 --edit all --add-in start,5sec
```

<h2 align="center">More Options</h2>

List all available options:

```
auto-editor --help
```

Use `--help` with a specific option for more information:

```
auto-editor --scale --help
--scale

  type: number
  default: 1.0
  ------------

  Scale the input video's resolution by the given factor.
```

<h3 align="center">Auto-Editor is available on all platforms</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/site/src/img/cross-platform.webp" width="500" title="Windows, MacOS, and Linux"></p>

## Articles
 - [How to Install Auto-Editor](https://auto-editor.com/installing)
 - [All the Options (And What They Do)](https://auto-editor.com/options)
 - [Docs](https://auto-editor.com/docs)
 - [Blog](https://auto-editor.com/blog)

## Copyright
Auto-Editor is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) and includes all directories besides the ones listed below. Auto-Editor was created by [these people.](https://github.com/WyattBlue/auto-editor/blob/master/AUTHORS.md)

ae-ffmpeg is under the [LGPLv3 License](https://github.com/WyattBlue/auto-editor/blob/master/auto_editor/ffmpeg/LICENSE.txt). The FFmpeg and FFprobe programs were created by the FFmpeg team and purposely compiled by WyattBlue for use in auto-editor.

## Issues
If you encounter a bug or have a feature request, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new). If you'll like to discuss this project, and chat with other users, you can use the [discord server](https://discord.com/invite/kMHAWJJ).
