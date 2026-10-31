---
name: auto-editor-transitions
description: Add transitions at auto-editor's cuts — cross-dissolves, Premiere Pro's transitions (push, clock-wipe, glitch, page-peel, iris-round, and the rest, including its Legacy folder), and audio crossfades — and carry them into Premiere, DaVinci Resolve, Final Cut Pro, Shotcut or Kdenlive. Use when someone wants smoother cuts, fades at the start and end, a particular transition, or transitions that survive an editor export or import.
---

# Transitions

`--transition KIND:DURATION[:MIN-CUT]` puts a transition at each cut auto-editor
makes, and at the start and end of the timeline. The video and audio
transitions are linked: they cover the same span.

```bash
auto-editor video.mp4 --transition dissolve:1sec        # cross-dissolves, fades at the ends
auto-editor video.mp4 --transition push:0.5sec          # a Premiere Pro transition
auto-editor video.mp4 --transition clock-wipe:1sec:0    # at every cut, however short
auto-editor video.mp4 --transition constant-power:1sec  # audio crossfade kind; video dissolves
```

- `DURATION`: how long each transition lasts (`0.5sec`, or a bare frame count).
- `MIN-CUT` (default `1sec`): skip cuts whose **removed** source is shorter
  than this, so trimming a short pause stays a hard cut instead of a stutter.
  `0` transitions at every cut.

A transition draws on the footage that was cut out (its handles), so:

- it may be shortened, or skipped, when a clip or the removed stretch is too
  short to support it;
- whatever was in the removed stretch shows mid-transition. If that's filler
  you don't want seen, keep transitions short or raise `MIN-CUT`.

## Kinds

Every transition Premiere Pro has, under its Premiere name in lowercase with
dashes. Those in its Legacy folder that share a name with a newer one end in
`-legacy`. They play at Premiere's default settings.

| Group | Kinds |
|---|---|
| Dissolve | `dissolve`, `additive-dissolve`, `blur-dissolve`, `burn-alpha`, `dip-to-black`, `dip-to-color`, `dip-to-white`, `film-dissolve`, `luma-fade`, `morph-cut`, `mosaic` |
| Animation | `block-motion`, `flip-motion`, `fold-motion`, `pop-motion`, `pull-motion`, `spin-motion`, `spring-motion`, `travel-motion` |
| Grunge & Distort | `chaos`, `earthquake`, `flicker`, `glass`, `glitch`, `grunge`, `kaleidoscope`, `liquid-distortion`, `tv-power`, `vhs-damage` |
| Lights & Blurs | `burn-chroma`, `chroma-leak`, `cross-zoom`, `directional-blur`, `flare`, `flash`, `glow`, `lens-blur`, `light-leak`, `light-sweep`, `phosphor`, `radial-blur`, `ray`, `solarize`, `stripe`, `zoom-blur` |
| Slide | `3d-roll`, `film-roll`, `push`, `roll`, `slide`, `split`, `stretch`, `whip` |
| Smart Tools | `motion-camera`, `motion-tween`, `shape-dissolve`, `shape-flow` |
| Text | `text-animator`, `typewriter` |
| Transformers | `3d-spin`, `3d-spinback`, `frame`, `louver`, `mirror`, `page-peel`, `slice`, `wave` |
| Wipe | `clock-wipe`, `linear-wipe`, `neon-wipe`, `panel-wipe`, `plateau-wipe`, `radial-wipe`, `soft-wipe`, `star-wipe`, `stretch-wipe` |
| Immersive Video | `vr-chroma-leaks`, `vr-gradient-wipe`, `vr-iris-wipe`, `vr-light-leaks`, `vr-light-rays`, `vr-mobius-zoom`, `vr-random-blocks`, `vr-spherical-blur` |
| Legacy | `additive-dissolve-legacy`, `barn-doors`, `center-split`, `clock-wipe-legacy`, `cross-dissolve-legacy`, `cross-zoom-legacy`, `dip-to-black-legacy`, `dip-to-white-legacy`, `film-dissolve-legacy`, `inset`, `iris-box`, `iris-cross`, `iris-diamond`, `iris-round`, `non-additive-dissolve`, `push-legacy`, `radial-wipe-legacy`, `slide-legacy`, `split-legacy`, `whip-legacy`, `wipe` |
| Obsolete (no longer listed in Premiere) | `band-slide`, `checker-wipe`, `cube-spin`, `flip-over`, `gradient-wipe`, `page-peel-obsolete`, `page-turn`, `venetian-blinds` |

`dip-to-color` dips to the timeline's background color (`-bg`).

**Audio.** A video kind gives the audio a plain crossfade. Audio has three
kinds of its own: `dissolve` (Premiere's Constant Gain; `constant-gain` is
accepted too), `constant-power` and `exponential-fade`. Naming one of those
keeps the video a cross-dissolve.

**How close to Premiere.** auto-editor renders every kind itself. Compared
frame by frame with Premiere's own renders, `push`, `clock-wipe` and
`barn-doors` match to within encoding noise and `page-peel` is close; the
others haven't been measured. Expect simple dissolves and wipes to be near, and
effects like `glitch` or `light-leak`, which draw their own noise and colors,
to differ. For Premiere's exact look, export with `premiere-otio` and let
Premiere render them.

## Per-transition control: v3 timelines

`--transition` uses one kind everywhere. For a different kind or length at
each cut, export a v3 timeline, edit its `transitions` key, and render it:

```bash
auto-editor video.mp4 --transition dissolve:0.5sec --export v3 -o edit.v3
# edit edit.v3, then:
auto-editor edit.v3 -o out.mp4
```

```json
"transitions": {
  "v": [[{"kind": "push", "at": 300, "dur": 15, "alignment": "center"}]],
  "a": [[{"kind": "constant-power", "at": 300, "dur": 15, "alignment": "center"}]]
}
```

`at` is the edit point in timeline frames, `dur` the length in frames, and
`alignment` is `start` (a fade in from a clip's start), `center` (across a cut
between adjacent clips) or `end` (a fade out at a clip's end). Video tracks take
video kinds; audio tracks take `dissolve`, `constant-power` or
`exponential-fade`. See <https://auto-editor.com/docs/v3>.

## In editor exports

| Export | What arrives |
|---|---|
| `premiere-otio` | Every kind, as Premiere's own transitions. Of the obsolete kinds, Premiere still reads `page-turn` and `page-peel-obsolete`; the others are sent as a dissolve, since Premiere would drop them and leave a cut. |
| `premiere`, `resolve-fcp7` (FCP7 XML) | Cross Dissolve; the dips (as Dip to Color Dissolve, which Premiere reads as its Dip to Black or White); `wipe` (as Edge Wipe); Cross Fade (0dB) or (+3dB) for audio. Every other kind becomes a dissolve. |
| `final-cut-pro`, `resolve` (FCPXML) | Cross Dissolve spine transitions. |
| `shotcut`, `kdenlive` | Same-track dissolves and crossfades, fade filters at the ends. |
| `v3` | Every kind, unchanged. |

To bring the kinds into Premiere, use `premiere-otio`. `v1`, `v2` and
`clip-sequence` exports drop transitions; a clip sequence's files are separate,
so a transition between them has no meaning.

## Importing

FCP7 XML and FCPXML imports read the transitions those formats name: Cross
Dissolve, Additive Dissolve, Dip to Color Dissolve (black or white by its
color), Edge Wipe, the Irises, Page Curl, Star, Cross Fade (0dB/+3dB), and
Premiere's names generally. A name it doesn't know plays as a dissolve.

## Recipes

```bash
auto-editor talk.mp4 --transition dissolve:0.3sec           # soft cuts in a talking-head video
auto-editor vlog.mp4 --transition whip:0.4sec:2sec          # whips, only where 2s+ was removed
auto-editor podcast.mp3 --transition constant-power:0.2sec  # audio-only: smooth crossfades
auto-editor video.mp4 --transition push:0.5sec --export premiere-otio   # finish in Premiere
```

For cutting itself (edit methods, margins, pace), see the **auto-editor**
skill. For editor exports in general, see the **auto-editor-export** skill.
