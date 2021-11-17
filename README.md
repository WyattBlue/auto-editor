<p align="center"><img src="https://raw.githubusercontent.com/wyattblue/auto-editor/master/articles/imgs/auto-editor_banner.png" title="Auto-Editor" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing a variety of methods, most notability audio loudness.

---

[![Actions Status](https://github.com/wyattblue/auto-editor/workflows/build/badge.svg)](https://github.com/wyattblue/auto-editor/actions)
<a href="https://discord.com/invite/kMHAWJJ/"><img src="https://img.shields.io/discord/711767814821773372?color=%237289DA&label=chat&logo=discord&logoColor=white"></a>

Before doing the real editing, you first cut out the "dead space" which is typically silence. This is known as a "first pass". Cutting these is a boring task, especially if the video is very long.

```
auto-editor path/to/your/video.mp4
```

<h2 align="center">Installing</h2>

```
pip3 install auto-editor
```

See [Installing](https://auto-editor.com/cli/installing) for additional information.


<h2 align="center">Cutting</h2>

Change the **pace** of the edited video by using `--frame_margin`.

`--frame_margin` will including small sections that are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```
auto-editor example.mp4 --frame_margin 8
```


<h2 align="center">Exporting to Editors</h2>

Create an XML file that can be imported to Adobe Premiere Pro using this command:

```
auto-editor example.mp4 --export_to_premiere
```

Similar flags exist also for:

- `--export_to_resolve` for DaVinci Resolve.
- `--export_to_final_cut_pro` for Final Cut Pro.
- `--export_to_shot_cut` for ShotCut.


<h2 align="center">More Options</h2>

List all available options:

```
auto-editor --help
```

Use `--help` with a specific option for more information:

```
auto-editor --scale --help
  --scale
    scale the output media file by a certain factor.

    type: float_type
    default: 1
```


<h3 align="center">Auto-Editor is available on all platforms</h3>
<p align="center"><img src="https://raw.githubusercontent.com/WyattBlue/auto-editor/master/articles/imgs/cross_platform.png" width="500" title="Windows, MacOS, and Linux"></p>


## Articles
 - [How to Install Auto-Editor](https://auto-editor.com/cli/installing)
 - [How to Edit Videos With Auto-Editor](https://auto-editor.com/cli/editing)
 - [How to Use Motion Detection in Auto-Editor](https://auto-editor.com/cli/motion_detection)
 - [What's new in Range Syntax](https://auto-editor.com/cli/range_syntax)
 - [Subcommands](https://auto-editor.com/cli/subcommands)
 - [Branding Guide](https://auto-editor.com/docs/branding)
 - [GPU Acceleration](https://auto-editor.com/docs/gpu_acceleration)
 - Effects
   - [Rectangles](https://auto-editor.com/cli/effects/rectangles)
   - [Zooming](https://auto-editor.com/cli/effects/zooming)
 
## Copyright
Auto-Editor is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) but contains non-free elements. See [this page](https://github.com/WyattBlue/auto-editor/blob/master/articles/legalinfo.md) for more info.


## Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) here. If you'll like to discuss this project, suggest new features, or chat with other users, you can use [the discord server](https://discord.com/invite/kMHAWJJ).
