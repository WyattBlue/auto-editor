---
title: Transitions
---

Transitions smooth over the cuts auto-editor makes. Instead of a hard jump
from one kept section to the next, the two sections blend into each other
with a cross-dissolve, and the timeline fades in at the start and fades out
at the end.

## Basic Syntax

```sh
# 1 second dissolves at eligible cuts, plus fades at the timeline ends
auto-editor video.mp4 --transition dissolve:1sec
```

The full form is `dissolve:DURATION[:MIN-CUT]`:

- `DURATION` — how long each transition lasts. Accepts the usual time units
  (`0.5sec`, `20` for a bare frame count, etc.).
- `MIN-CUT` — skip cuts whose *removed source interval* is shorter than this
  (default: `1sec`). Dissolving across a tiny silence trim reads as a stutter,
  so short cuts stay hard by default. Use `0` to dissolve at every cut:

```sh
auto-editor video.mp4 --transition dissolve:1sec:0
```

Dissolves are linked: video cross-dissolves and audio cross-fades cover the
same span. A dissolve needs source material on both sides of the cut
(the material that was cut out serves as the handle), so a transition may be
shortened or skipped when a clip is too short to support it.

## Where transitions survive

The native render and every editor export carry transitions:

| Export | Result |
|---|---|
| default (rendered media) | Rendered directly |
| `v3` | Stored in the `transitions` key |
| `premiere`, `resolve-fcp7` (FCP7 XML) | Cross Dissolve / Cross Fade transition items |
| `premiere-otio` | `SMPTE_Dissolve` transitions |
| `final-cut-pro`, `resolve` (FCPXML) | Cross Dissolve spine transitions |
| `shotcut` | Same-track transitions (luma + mix), fade filters at the ends |
| `kdenlive` | Same-track mixes, fade filters at the ends |

## Where transitions are dropped

- `v1` and `v2` timeline files have no way to represent transitions; exporting
  to them silently drops the transitions and keeps the cuts.
- `clip-sequence` does not carry transitions **by design**: it renders each
  kept section as an independent media file, and a cross-dissolve has no
  meaning between separate files.
