---
name: auto-editor
description: Record a microphone or edit video/audio with the auto-editor CLI — cut out dead space (silence, motionlessness, black frames), set the pace, make manual cuts, and render the result. Use when someone wants to capture and trim a microphone, remove silence, shorten a recording, speed through quiet parts, or otherwise edit media with auto-editor.
---

# Editing with auto-editor

auto-editor analyzes a media file, marks every timebase section as **active**
(e.g. loud) or **inactive** (e.g. silent), then applies an action to each. The
defaults: keep active sections unchanged, **cut** inactive ones.

```bash
auto-editor path/to/video.mp4          # writes video_ALTERED.mp4
auto-editor video.mp4 -o out.mp4       # choose the output name
```

Run the installed `auto-editor`, or `./auto-editor` from this repo. `auto-editor
info FILE` shows streams/codecs/duration; `--preview` prints what *would* be cut
and exits without rendering — use it to sanity-check before a long render.

## Record and edit a microphone

Use `:mic` as the input on macOS, Windows, or Linux. Stop capture gracefully
with Ctrl-C; auto-editor then analyzes and edits the recording normally.

```bash
auto-editor :mic                                      # → mic_ALTERED.wav
auto-editor :mic --sample-rate 44.1kHz -o trimmed.m4a
auto-editor :mic --edit audio:threshold=6%
```

All normal edit, action, and rendering options apply. Editor and timeline
exports preserve the source capture separately; use the **auto-editor-export**
skill for recording-codec and naming details.

## 1. Choose what counts as "active" — `--edit METHOD`

`audio:threshold=0.04,stream=all` is the default. Threshold takes a 0–1 fraction
or a `dB` value (case-sensitive).

| Method | Marks active when… | Key args (defaults) |
|---|---|---|
| `audio` | loudest sample ≥ threshold | `threshold=0.04`, `stream=all` |
| `motion` | frame-to-frame change ≥ threshold | `threshold=0.02`, `stream=0`, `width=400`, `blur=9` |
| `blackdetect` | frame is mostly black | `threshold=0.98`, `pixel-black=0.10` (wrap in `not` to cut black) |
| `subtitle`/`regex` | a subtitle line matches `pattern` | `pattern` (required), `ignore-case=#f` |
| `word` | a whole word appears in subtitles | `value` (required), `ignore-case=#t` |
| `1` / `0` | **every** / **no** moment is active (keep-all / cut-all) | aliases `none` / `all`; a base for manual ranges |

```bash
auto-editor video.mp4 --edit audio:threshold=0.04
auto-editor video.mp4 --edit audio:-19dB            # dB form
auto-editor video.mp4 --edit motion:threshold=0.02
auto-editor video.mp4 --edit blackdetect            # cut to remove black: --edit "(not blackdetect:0.98)"
```

Combine streams/methods with boolean operators `or`, `and`, `xor`, `not`. Inside
an operator, give the method an explicit arg in call form (`audio:0.04`, not bare
`audio`) — a bare method there errors with `Bad kind`:

```bash
auto-editor multi.mov --edit "(or audio:stream=0 audio:threshold=10%,stream=1)"
auto-editor video.mp4 --edit "(or audio:0.03 motion:0.06)"   # threshold is always positional arg 1
auto-editor video.mp4 --edit "(not audio:0.04)"              # invert: keep the quiet parts
```

### Labels — more than just silent vs. loud (`--edit:N`, `--when:N`)

Every moment is tagged with an integer **label** (0–255), and each label has an
action. Two labels are built in:

| Label | Meaning | Set the membership with | Set the action with (default) |
|---|---|---|---|
| `0` | silent / inactive | (whatever `--edit` does *not* match) | `--when-inactive` = `-w:0` = `--when:0` (`cut`) |
| `1` | normal / active | `--edit EXPR` (i.e. `--edit:1 EXPR`) | `--when-active` = `-w:1` = `--when:1` (`nil`) |

So plain `--edit audio` is shorthand for `--edit:1 audio`: matched moments become
label 1, the rest stay 0. `-w:0`/`-w:1` are just `--when:0`/`--when:1`.

Add **custom classes** with `--edit:N EXPR` (N = 2–255) and give each its own
action with `--when:N ACTION` (default `nil` = keep). Where classes overlap, the
**higher label wins**:

```bash
# Cut silence (0) and keep speech (1) as usual, but also zoom wherever there's motion (2)
auto-editor video.mp4 --edit:2 motion:0.02 --when:2 zoom:2
auto-editor video.mp4 -e:2 motion:0.1 -w:2 speed:2        # -e/-w short forms

# Three tiers: cut silence, keep quiet speech at 1x, speed up the loud parts
auto-editor talk.mp4 --edit audio:-30dB --edit:2 audio:-12dB --when:2 speed:1.5
```

`--edit:0` is rejected — label 0 is the implicit silent class; use `--when:0` to
act on silent moments. (The `--edit 1` / `--edit 0` *values* above are unrelated:
they set label 1's expression to the all-true / all-false constant.)

## 2. Set the pace — `--margin` and `--smooth`

```bash
auto-editor video.mp4 --margin 0.2sec        # default: pad each kept section by 0.2s both sides
auto-editor video.mp4 --margin 0.3s,1.5sec   # 0.3s before, 1.5s after (avoids clipped words)
auto-editor video.mp4 --smooth 0.2s,0.1s     # min-cut 0.2s, min-clip 0.1s (default); --smooth 0 = off
```

## 3. Manual edits — range syntax

`--cut`, `--keep`, `--set-speed`, `--set-action` take `START,STOP` ranges.
Start is inclusive, stop exclusive. Default unit is the **timebase**; add `sec`
(`s`/`second`) for seconds. Vars `start`/`end`; negatives count from the end.
Ranges combine with automatic edits, or use `--edit 0`/`--edit 1` for
manual-only editing.

```bash
auto-editor video.mp4 --cut 0,30 -10sec,end    # drop first 30 frames and last 10s
auto-editor video.mp4 --keep 0,30sec           # force-keep first 30s regardless of loudness
auto-editor video.mp4 --set-speed 2,0,30       # SPEED,START,STOP: 2x over frames 0–29
auto-editor video.mp4 --edit 1 --cut 0,5sec    # no auto cuts, just drop first 5s
auto-editor video.mp4 --edit 0 --keep 0,5sec   # keep only the first 5s
```

## 4. Reverse the edit — see what gets cut

```bash
auto-editor video.mp4 --when-active cut --when-inactive nil   # keep the silence, cut the loud parts
```

## 5. Render & file size

```bash
auto-editor video.mp4 -c:v hevc -b:v 0       # variable bitrate
auto-editor video.mp4 -b:v 230k              # target a bitrate to shrink the file
auto-editor video.mp4 -crf 23 -preset medium # quality-based encoding
auto-editor video.mp4 --scale 0.5            # halve the resolution
auto-editor video.mp4 -anorm ebu             # EBU R128 loudness normalize (or peak:-3)
```

Larger-than-expected files are usually a too-high auto bitrate — set `-b:v` or `-crf`. `auto-editor cache` lists/`cache clear`s the analysis cache.

## Going further

- Creative effects (speed/zoom/overlays/animations) → **auto-editor-effects** skill
- Export to Premiere/Resolve/Final Cut, clip-sequence, or `.v1/.v2/.v3` timelines → **auto-editor-export** skill
- Transcribe audio and cut by spoken words → **auto-editor-transcribe** skill
- Full option list: `auto-editor --help` or <https://auto-editor.com/ref/options.md>
