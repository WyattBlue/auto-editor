<p align="center"><img src="https://raw.githubusercontent.com/wyattblue/auto-editor/master/articles/imgs/auto-editor_banner.png" title="Auto-Editor" width="700"></p>

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

See [Installing](https://github.com/WyattBlue/auto-editor/blob/master/articles/installing.md) for additional information.


<h2 align="center">Cutting</h2>

Change the **pace** of the edited video by using `--frame-margin`.

`--frame-margin` will including small sections that are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```
auto-editor example.mp4 --frame-margin 8
```

<h3>Set how cuts are made</h3>

Use the `--edit` option to change how auto-editor makes automated cuts.

For example, edit out motionlessness in a video by setting `--edit motion`.


```
# cut out sections where percentage of motion is less than 2.
auto-editor example.mp4 --edit motion:threshold=2%

# --edit is set to "audio" by default
auto-editor example.mp4 --silent-threshold 4%

# audio and motion thresholds are toggled independently
auto-editor example.mp4 --edit 'audio:threshold=3% or motion:threshold=6%'
```

<h3>See what auto-editor cuts out</h3>

To export what auto-editor normally cuts out. Set `--video-speed` to `99999` and `--silent-speed` to `1`. This is the reverse of the usual default values.  

```
auto-editor example.mp4 --video-speed 99999 --silent-speed 1
```

<h2 align="center">Exporting to Editors</h2>

Create an XML file that can be imported to Adobe Premiere Pro using this command:

```
auto-editor example.mp4 --export premiere
```

Similar commands exist for:

- `--export final-cut-pro` for Final Cut Pro.
- `--export shotcut` for ShotCut.

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
```

And the inverse

```
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
    Scale the output media file by a certain factor.

    type: float_type
    default: 1
```


<h3 align="center">Auto-Editor is available on all platforms</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/articles/imgs/cross_platform.png" width="500" title="Windows, MacOS, and Linux"></p>


## Articles
 - [How to Install Auto-Editor](https://github.com/WyattBlue/auto-editor/blob/master/articles/installing.md)
 - [All the Options (And What They Do)](https://auto-editor.com/options)
 - [Supported Media](https://auto-editor.com/supported_media)
 - [What is Range Syntax](https://auto-editor.com/range_syntax)
 - [Subcommands](https://auto-editor.com/subcommands)
 - [GPU Acceleration](https://auto-editor.com/gpu_acceleration)


## Copyright
Auto-Editor is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) but contains non-free elements. See [this page](https://github.com/WyattBlue/auto-editor/blob/master/articles/legalinfo.md) for more info.


## Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) here. If you'll like to discuss this project, suggest new features, or chat with other users, you can use [the discord server](https://discord.com/invite/kMHAWJJ).
