---
name: auto-editor-effects
description: Apply actions and animations to sections of a video/audio with auto-editor — change speed, duck or fade volume, de-ess, zoom/Ken Burns, rotate/spin, draw boxes, overlay logos or picture-in-picture, and animate any of these with ramps and easing. Use when someone wants creative effects or per-section behavior rather than plain silence-cutting.
---

# Actions & animations

Instead of just cutting, give each section an **action** with `--when-active`
(`-w:1`, loud) and `--when-inactive` (`-w:0`, silent). Defaults: `-w:1 nil`
(keep), `-w:0 cut`. Chain actions with commas; they apply in order.

```bash
auto-editor video.mp4 -w:0 speed:8            # fast-forward through silence (pitch preserved)
auto-editor video.mp4 -w:0 speed:3,volume:0.5 # speed up AND halve volume of silent parts
```

`-w:0`/`-w:1` are the silent (label 0) and active (label 1) classes. You can
define more classes with `--edit:N`/`-e:N` and act on them with `--when:N`/`-w:N`
(N = 2–255) — see the **auto-editor** skill's "Labels" section. Every action
below works as the value of any `-w:N`.

## Actions

| Action | What it does | Form / range |
|---|---|---|
| `nil` | keep unchanged | — |
| `cut` | remove section | — |
| `speed` | time-stretch, **pitch preserved** | `speed:8`, `speed:0.5` |
| `varispeed` | speed via pitch shift (tape/vinyl) | `varispeed:2` (0.2–100) |
| `volume` | scale volume (1=normal, 0.5=−6dB) | `volume:0.2` |
| `deesser` | reduce sibilance | `deesser:intensity[:max[:freq]]` (each 0–1) |
| `invert` | invert pixels | — |
| `zoom` | zoom factor (1=none) | `zoom:2`, `zoom:0.5` (>0–100) |
| `rotate` | fixed clockwise rotation, expands so nothing clips | `rotate:90` (pair with `--resolution`) |
| `spin` | continuous spin `deg/rate` (deg per sec) | `spin:0/120`, `spin:90/-45` |
| `drawbox` | filled rectangle | `drawbox:x:y:w:h:color` |
| `pos` | place an overlay clip `x:y[:scale]` | mainly used inside `add` / v3 |
| `add` | overlay an image/video layer | `add:path[:x:y:scale]` |

```bash
auto-editor video.mp4 -w:1 deesser:0.8:0.7:0.4
auto-editor video.mp4 -w:1 rotate:90 --resolution 1080,1920   # landscape → portrait
auto-editor video.mp4 -w:1 drawbox:0:0:1920:200:#000000       # redact a strip
```

### Overlays — `add`

`add` is **virtual**: it adds an overlay layer rather than a per-frame effect.
Still images hold for the whole section; PNG alpha is preserved. Omit placement
to scale-to-fit and center. Actions chained **after** an `add` apply to that new
overlay, not the base.

```bash
auto-editor video.mp4 -w:1 add:./logo.png             # centered, fit to canvas
auto-editor video.mp4 -w:1 add:./pip.mp4:900:60:0.25  # quarter-size PiP in the corner
auto-editor video.mp4 -w:1 add:./logo.png,spin:0/-30  # the logo spins, not the base video
auto-editor song.mp3 -bg white -w:1 add:./cover.png   # audio + image → video
```

Overlays appear only where their section is kept, so for silent sections use
`-w:0 nil,add:...` (keep + overlay). With `--set-action` the range is kept
automatically.

## Animations — ramps `from..to`

`zoom`, `opacity`, `blur`, `brightness`, `volume`, and each `pos` field accept a
ramp. The value interpolates across the section, reaching `to` on its last frame.
More than two points = keyframes, spread evenly.

```bash
auto-editor video.mp4 -w:1 zoom:1..1.5          # Ken Burns
auto-editor video.mp4 -w:1 opacity:0..1         # fade in
auto-editor video.mp4 -w:1 volume:0..1          # audio fade in
auto-editor video.mp4 -w:1 zoom:1..1.5..1       # zoom in then out (keyframes)
auto-editor video.mp4 -w:1 add:./logo.png,pos:0..1200:40:1..0.5  # slide + shrink overlay
```

Easing — `:ease=curve[:duration]`, curve ∈ `linear|in|out|inout`. A standalone
`ease:` token sets the curve for every animated action after it. `rotate`/`spin`
are **not** affected by easing.

```bash
auto-editor video.mp4 -w:1 zoom:1..1.5:ease=inout
auto-editor video.mp4 -w:1 opacity:0..1:ease=in:2sec        # ease over 2s, then hold
auto-editor video.mp4 -w:1 ease:out,zoom:1..1.3,brightness:0..0.3
```

## Target a time range — `--set-action`

`--set-action ACTION,START,END` overrides defaults for a range (range syntax;
`sec`, `start`/`end`, negatives all work). The range is force-kept.

```bash
auto-editor video.mp4 --set-action nil,0,5sec
auto-editor video.mp4 --set-action speed:1.5,varispeed:1.5,30sec,end
auto-editor video.mp4 --set-action add:./logo.png:600:300:1.0,1sec,2sec
```

## Recipes

```bash
auto-editor podcast.mp3 -w:0 cut -w:1 speed:1.15      # cut silence, tighten speech
auto-editor video.mp4 -w:0 volume:0.3                 # duck (not cut) the silence
auto-editor video.mp4 -w:1 varispeed:1.25             # nightcore (speed + pitch up)
auto-editor video.mp4 -w:0 speed:6,volume:0.4         # fast, quiet silent sections
```

Full reference: <https://auto-editor.com/ref/actions.md>. For plain cutting / pace /
edit methods, see the **auto-editor** skill.
