---
name: auto-editor-export
description: Export auto-editor's edit to a video editor (Premiere, DaVinci Resolve, Final Cut Pro, ShotCut, Kdenlive), to individual clips, or to auto-editor timeline files (.v1/.v2/.v3); and import timeline/XML files to render them. Use when someone wants an editor-ready project (XML/MLT/kdenlive), split clips, or to read/write timeline files instead of a finished video.
---

# Exporting & importing

By default auto-editor renders a media file. `--export` (`-ex`) changes the
target. The output extension is chosen automatically per mode.

```bash
auto-editor video.mp4 --export premiere    # → video_ALTERED.xml for Premiere Pro
```

## Export targets

| `--export` | For | Output |
|---|---|---|
| `premiere` | Adobe Premiere Pro (fcp7 xml) | `.xml` |
| `resolve` | DaVinci Resolve (fcpxml) | `.fcpxml` |
| `resolve-fcp7` | Resolve via legacy fcp7 xml | `.xml` |
| `final-cut-pro` | Final Cut Pro | `.fcpxml` |
| `shotcut` | ShotCut | `.mlt` |
| `kdenlive` | Kdenlive | `.kdenlive` |
| `clip-sequence` | individual media clips, one per kept segment | media files |
| `v1` / `v2` / `v3` | auto-editor timeline files | `.v1` / `.v2` / `.v3` |
| (default) | rendered media file | per container |

```bash
auto-editor video.mp4 --export resolve
auto-editor video.mp4 --export final-cut-pro
auto-editor video.mp4 --export clip-sequence
auto-editor video.mp4 --export v3 -o timeline.v3
```

## Naming the timeline

`premiere`, `resolve`, and `final-cut-pro` accept a `name` attr (default
"Auto-Editor Media Group"). Pass extra attrs after a colon:

```bash
# POSIX shells
auto-editor example.mp4 --export 'premiere:name="Your name here"'
# PowerShell (double the inner quotes)
auto-editor example.mp4 --export 'premiere:name=""Your name here""'
```

## Split into clips without further editing

To split at the cut points but make no other edits, set both actions to `nil`:

```bash
auto-editor example.mp4 -w:0 nil -w:1 nil --export premiere
```

## Importing timelines

auto-editor reads timeline/XML files as inputs and renders them like any media:

```bash
auto-editor myFcp7File.xml -o render.mp4    # render an fcp7 xml (experimental)
auto-editor timeline.v3 -o render.mp4       # render an auto-editor timeline file
```

Importers: auto-editor timeline files (`.v1`, `.v2`, `.v3`) and FCP7 XML
(experimental). The input format is detected by extension. PRs for more importers
are welcome.

## Timeline format notes

`.v1`/`.v2`/`.v3` are auto-editor's own timeline formats; `.v3` is the current
layered format (supports stacked tracks / overlay compositing). See
<https://auto-editor.com/docs/v3> (and `/docs/v1`, `/docs/v2`). Export a timeline
to inspect or hand-tweak the edit, then re-import it to render.

For plain rendering, edit methods, and pace, see the **auto-editor** skill.
