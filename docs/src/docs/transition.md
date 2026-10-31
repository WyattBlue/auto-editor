---
title: Transitions
---

Transitions smooth over the cuts auto-editor makes. Instead of a hard jump
from one kept section to the next, the two sections blend into each other,
and the timeline transitions in at the start and out at the end.

## Basic Syntax

```sh
# 1 second dissolves at eligible cuts, plus fades at the timeline ends
auto-editor video.mp4 --transition dissolve:1sec
```

The full form is `KIND:DURATION[:MIN-CUT]`:

- `KIND` — `dissolve`, or any of the kinds below.
- `DURATION` — how long each transition lasts. Accepts the usual time units
  (`0.5sec`, `20` for a bare frame count, etc.).
- `MIN-CUT` — skip cuts whose *removed source interval* is shorter than this
  (default: `1sec`). Dissolving across a tiny silence trim reads as a stutter,
  so short cuts stay hard by default. Use `0` to dissolve at every cut:

```sh
auto-editor video.mp4 --transition dissolve:1sec:0
```

Transitions are linked: video transitions and audio crossfades cover the
same span. A dissolve needs source material on both sides of the cut
(the material that was cut out serves as the handle), so a transition may be
shortened or skipped when a clip is too short to support it.

## Kinds

Every kind of transition Premiere Pro has is available under its Premiere
name, lowercased with dashes; those in its Legacy folder that share a name with
a newer one end in `-legacy`. They play at Premiere's default settings;
`dip-to-color` dips to the timeline's background color (`-bg`). The Obsolete
ones are those Premiere no longer lists; of them, it only still reads
`page-turn` and `page-peel-obsolete`, so `premiere-otio` gives it the others
as a dissolve.

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
| Obsolete | `band-slide`, `checker-wipe`, `cube-spin`, `flip-over`, `gradient-wipe`, `page-peel-obsolete`, `page-turn`, `venetian-blinds` |

```sh
auto-editor video.mp4 --transition push:0.5sec
auto-editor video.mp4 --transition clock-wipe:1sec:0
```

A video kind gives the audio a plain crossfade. Audio has three kinds of its
own: `dissolve` (Premiere's Constant Gain), `constant-power` and
`exponential-fade`. Naming one of those keeps the video a cross-dissolve:

```sh
auto-editor video.mp4 --transition constant-power:1sec
```

In a v3 timeline, each transition names its kind, so video and audio can
differ.

## Where transitions survive

The native render and every editor export carry transitions:

| Export | Result |
|---|---|
| default (rendered media) | Rendered directly |
| `v3` | Stored in the `transitions` key |
| `premiere-otio` | Every kind, as Premiere's own transitions |
| `premiere`, `resolve-fcp7` (FCP7 XML) | Cross Dissolve, Dip to Color Dissolve, Edge Wipe, and Cross Fade (0dB) or (+3dB) |
| `final-cut-pro`, `resolve` (FCPXML) | Cross Dissolve spine transitions |
| `shotcut` | Same-track transitions (luma + mix), fade filters at the ends |
| `kdenlive` | Same-track mixes, fade filters at the ends |

FCP7 XML, FCPXML, Shotcut and Kdenlive have no way to name most of Premiere's
transitions, so those exports dissolve where the timeline has another kind.
From FCP7 XML, Premiere brings in the dips (as its legacy Dip to Black or
White) and `wipe`, and reads everything else as a dissolve; to bring every
kind into Premiere, export with `premiere-otio`. Importing FCP7 XML or FCPXML reads the
kinds those formats can name, like Additive Dissolve or Cross Fade (+3dB).

## Where transitions are dropped

- `v1` and `v2` timeline files have no way to represent transitions; exporting
  to them silently drops the transitions and keeps the cuts.
- `clip-sequence` does not carry transitions **by design**: it renders each
  kept section as an independent media file, and a cross-dissolve has no
  meaning between separate files.
