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

## One-command 9:16 short pipeline

This repository includes a small PowerShell wrapper that removes silence, renders the result on a 720x1280 canvas, and writes a short Markdown report:

```powershell
.\shorts.cmd .\example.mp4
```

Outputs are written to `outputs/`. The wrapper uses `tools/auto-editor.exe`, keeps all paths inside the repository, and disables Auto-Editor's cache. Tune the cut with `-Threshold` and `-Margin` when needed.

## SmartCut Compare

Render Conservative, Balanced, and Aggressive 9:16 edits of the same source, plus per-version reports, a side-by-side preview, a JSON summary, and an automatic best-preset recommendation:

```powershell
.\smartcut-compare.cmd .\example.mp4
```

The preview is ordered left-to-right as Conservative, Balanced, and Aggressive. Green, blue, and red top markers identify the three versions; shorter edits hold on their final frame. All generated files stay under `outputs/`, and media-analysis caching is disabled.

### Real talking-head demo

The included local demo uses a short NASA interview with real English speech and natural pauses. Run the complete comparison with one command:

```powershell
.\smartcut-compare.cmd .\demo\smartcut-demo-original.mp4 -OutputDirectory .\outputs\smartcut-demo
```

Source and license:

- **Title:** *Interview with Antti Pulkkinen 3*
- **Author:** NASA/Goddard Space Flight Center
- **Source:** [Wikimedia Commons file page](https://commons.wikimedia.org/wiki/File:Interview_with_Antti_Pulkkinen_3.ogv) ([original media download](https://commons.wikimedia.org/wiki/Special:Redirect/file/Interview_with_Antti_Pulkkinen_3.ogv))
- **License:** U.S. public domain because the file was solely created by NASA. The Commons page notes that NASA logos and insignia have separate legal restrictions.
- **Local files:** `demo/commons-antti-pulkkinen-original.ogv` is the downloaded source; `demo/smartcut-demo-original.mp4` is a 28.4-second H.264/AAC presentation derivative with normalized speech audio.

Verification performed on the local files:

- The Commons source contains 1280x720 Theora video and a 48 kHz stereo Vorbis audio stream.
- Local speech recognition recovered a coherent English explanation of the event's expected technological and auroral effects.
- FFmpeg silence detection at -30 dB found 30 natural pauses of at least 0.18 seconds; the longest was 1.228 seconds.

Latest verified demo result:

| Version | Score | Final | Removed | Cuts/min | Avg. segment | Under 1s | Speech retained |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Conservative | 70.0 | 27.776s | 0.624s | 2.11 | 27.761s | 0 | 24.034s |
| **Balanced** | **75.2** | 27.370s | 1.030s | 2.11 | 27.361s | 0 | 24.019s |
| Aggressive | 66.0 | 25.600s | 2.800s | 16.90 | 3.199s | 0 | 23.184s |

**Recommendation: Balanced.** It removes more time than Conservative while keeping the same cut density, no very short segments, and nearly identical detected speech. Aggressive saves the most time but creates substantially more cuts and much shorter retained segments.

Scoring is deterministic and relative to the three outputs: 30% duration removal, 20% lower cut density, 15% longer average segments, 15% fewer segments under one second, and 20% retained speech. Speech duration uses FFmpeg silence detection at -30 dB with a 0.05-second minimum silence. The full component scores, thresholds, weights, explanation, and tie-break order are stored in the JSON report.

## Run Online and as an Application
You can [run auto-editor online](https://app.auto-editor.com/online) or [download the application](https://app.auto-editor.com/download). They use assets from this repository (Unlicense); their own unique assets are under a separate proprietary license.

## Copyright
Everything in this repository is under the [Public Domain](https://github.com/WyattBlue/auto-editor/blob/master/LICENSE). Binary artifacts in the "Releases" section may be under various open source licenses.
