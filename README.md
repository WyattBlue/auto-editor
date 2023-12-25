<p align="center"><img src="https://auto-editor.com/img/auto-editor-banner.webp" title="Auto-Editor" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing a variety of methods, most notably audio loudness.

---

[![Actions Status](https://github.com/wyattblue/auto-editor/workflows/build/badge.svg)](https://github.com/wyattblue/auto-editor/actions)
<a href="https://github.com/psf/black"><img alt="Code style: black" src="https://img.shields.io/badge/code%20style-black-000000.svg"></a>

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

`--margin` adds in some "silent" sections to make the editing feel nicer.

```
# Add 0.2 seconds of padding before and after to make the edit nicer.
# `0.2s` is the default value for `--margin`
auto-editor example.mp4 --margin 0.2sec

# Add 0.3 seconds of padding before, 1.5 seconds after
auto-editor example.mp4 --margin 0.3s,1.5sec
```

### Methods for Making Automatic Cuts
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

You can also use `dB` unit, a volume unit familiar to video-editors (case sensitive):
```
auto-editor example.mp4 --edit audio:threshold=-19dB
auto-editor example.mp4 --edit audio:-7dB
auto-editor example.mp4 --edit motion:-19dB

# The `dB` unit is a just a macro that expands into an S-expression:
# '-19dB
# > '(pow 10 (/ -19 20))
# (eval '(pow 10 (/ -19 20)))
# > 0.11220184543019636
```

### Working With Multiple Audio Tracks
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

### See What Auto-Editor Cuts Out
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

- DaVinci Resolve with `--export resolve`
- Final Cut Pro with `--export final-cut-pro`
- ShotCut with `--export shotcut`

Other editors, like Sony Vegas, can understand the `premiere` format. If your favorite editor doesn't, you can use ` --export clip-sequence` which creates many video clips that can be imported and manipulated like normal.

### Naming Timelines
By default, auto-editor will name the timeline to "Auto-Editor Media Group" if the export supports naming.

```
auto-editor example.mp4 --export 'premiere:name="Your name here"'

auto-editor example.mp4 --export 'resolve:name="Your name here"'

auto-editor example.mp4 --export 'final-cut-pro:name="Your name here"'

# No other export options support naming
```

### Split by Clip

If you want to split the clips, but don't want auto-editor to do any more editing. There's a simple command.
```
auto-editor example.mp4 --silent-speed 1 --video-speed 1 --export premiere
```

<h2 align="center">Manual Editing</h2>

Use the `--cut-out` option to always remove a section.

```
# Cut out the first 30 seconds.
auto-editor example.mp4 --cut-out 0,30sec

# Cut out the first 30 frames.
auto-editor example.mp4 --cut-out 0,30

# Always leave in the first 30 seconds.
auto-editor example.mp4 --add-in 0,30sec

# Cut out the last 10 seconds.
auto-editor example.mp4 --cut-out -10sec,end

# You can do multiple at once.
auto-editor example.mp4 --cut-out 0,10 15sec,20sec
auto-editor example.mp4 --add-in 30sec,40sec 120,150sec
```

And of course, you can use any `--edit` configuration.

If you don't want **any automatic cuts**, you can use `--edit none` or `--edit all/e`

```
# Cut out the first 5 seconds, leave the rest untouched.
auto-editor example.mp4 --edit none --cut-out 0,5sec

# Leave in the first 5 seconds, cut everything else out.
auto-editor example.mp4 --edit all/e --add-in 0,5sec
```

<h2 align="center">More Options</h2>

List all available options:

```
auto-editor --help
```

Use `--help` with a specific option for more information:

```
auto-editor --scale --help
  --scale NUM

    default: 1.0
    Scale the output video's resolution by NUM factor
```

<h3 align="center">Auto-Editor is available on all major platforms</h3>
<p align="center"><img src="https://auto-editor.com/img/cross-platform.webp" width="500" title="Windows, MacOS, and Linux"></p>

## Articles
 - [How to Install Auto-Editor](https://auto-editor.com/installing)
 - [All the Options (And What They Do)](https://auto-editor.com/options)
 - [Docs](https://auto-editor.com/docs)
 - [Blog](https://auto-editor.com/blog)

## Copyright
Auto-Editor is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE) and includes all directories besides the ones listed below. Auto-Editor was created by [these people.](https://auto-editor.com/blog/thank-you-early-testers)

ae-ffmpeg is under the [LGPLv3 License](https://github.com/WyattBlue/auto-editor/blob/master/ae-ffmpeg/LICENSE.txt). The ffmpeg and ffprobe programs were created by the FFmpeg team.

