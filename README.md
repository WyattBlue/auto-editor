<p align="center"><img src="https://auto-editor.com/img/auto-editor-banner.webp" title="Auto-Editor" width="700"></p>

**Auto-Editor** is a command line application for automatically **editing video and audio** by analyzing a variety of methods, most notably audio loudness.

---

[![Actions Status](https://img.shields.io/github/actions/workflow/status/wyattblue/auto-editor/build.yml?style=flat)](https://github.com/wyattblue/auto-editor/actions)
[![Nim](https://img.shields.io/badge/nim-%23FFE953.svg?style=flat&logo=nim&logoColor=black)](https://nim-lang.org)

Before doing the real editing, you first cut out the "dead space" which is typically silence. This is known as a "first pass". Cutting these is a boring task, especially if the video is very long.

```
auto-editor path/to/your/video.mp4
```

<h2 align="center">Installing</h2>

See [Installing](https://auto-editor.com/installing) for more information.

<h2 align="center">Skills</h2>

```
npx skills add WyattBlue/auto-editor
```

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
# cut out sections where the total motion is less than 2%.
auto-editor example.mp4 --edit motion:threshold=0.02

# `--edit audio:threshold=0.04,stream=all` is used by defaut.
auto-editor example.mp4

# Different tracks can be set with different attribute.
auto-editor multi-track.mov --edit "(or audio:stream=0 audio:threshold=10%,stream=1)"
```

Different editing methods can be used together.
```
# 'threshold' is always the first argument for edit-method objects
auto-editor example.mp4 --edit "(or audio:0.03 motion:0.06)"
```

### Content-Aware Cuts with TwelveLabs Pegasus
The `pegasus` method goes beyond loudness and motion: it asks [TwelveLabs](https://twelvelabs.io) Pegasus, a video-understanding model, *what* is happening on screen and keeps only the moments that match a plain-language prompt. It is fully opt-in and changes nothing unless you ask for it.

```
# Keep only the parts where someone is speaking on camera.
auto-editor example.mp4 --edit pegasus --pegasus-prompt "a person is speaking to the camera"

# Combine it with the audio heuristic: keep loud parts OR action shots.
auto-editor example.mp4 --edit "(or audio:0.04 pegasus)" --pegasus-prompt "an exciting action moment"
```

Set the `TWELVELABS_API_KEY` environment variable first. You can grab a free API key at [twelvelabs.io](https://twelvelabs.io) — there's a generous free tier. The video is uploaded to TwelveLabs for analysis. Use `--pegasus-prompt` for any multi-word prompt, since `--edit` tokens cannot contain spaces.

You can also use `dB` unit, a volume unit familiar to video-editors (case-sensitive):
```
auto-editor example.mp4 --edit audio:-19dB
auto-editor example.mp4 --edit audio:-7dB
auto-editor example.mp4 --edit motion:-19dB
```

### Labels
Every moment gets an integer **label**: `0` is silent (cut by default), `1` is active (kept). `--edit` sets what's label `1`; `-w:0`/`-w:1` set each one's action. Add more classes with `--edit:N` and `--when:N` (`N` up to 255); where they overlap, the higher label wins.
```
# Cut silence, keep speech, and additionally speed up the loud parts
auto-editor example.mp4 --edit:2 audio:-12dB --when:2 speed:1.5
```
As a value (not a label), `--edit 1` keeps everything and `--edit 0` cuts everything. See the [actions docs](https://auto-editor.com/docs/actions) for more.

### See What Auto-Editor Cuts Out
To export what auto-editor normally cuts out. Set `--when-active` to `cut` and `--when-inactive` to `nil` (leave as is). This is the reverse of the usual default values.

```
auto-editor example.mp4 --when-active cut --when-inactive nil
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
- Kdenlive with `--export kdenlive`
- Individual media clips with `--export clip-sequence`

<h2 align="center">More Options</h2>

List all available options:

```
auto-editor --help
```

## Articles
 - [How to Install Auto-Editor](https://auto-editor.com/installing)
 - [All the Options (And What They Do)](https://auto-editor.com/ref/options)
 - [Docs](https://auto-editor.com/docs)
 - [Blog](https://basswood.io/blog/)

## Run Online and as an Application
You can [run auto-editor online](https://app.auto-editor.com/online) or [download the application](https://app.auto-editor.com/download). They use assets from this repository (Unlicense); their own unique assets are under a separate proprietary license.

## Copyright
Everything in this repository is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE). Binary artifacts in the "Releases" section may be under various open source licenses.
