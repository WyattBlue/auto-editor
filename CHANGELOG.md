# 31.0.0

## Major
 - `--edit` now supports up to 255 labels. Stack extra edit methods with `--edit:N` (N is 2–255) on top of the default `--edit` (label 1), and give each label its own action with `--when:N ACTION` (label 0 is silent, 1 is normal). Where masks overlap, the higher label wins. `-w:0`/`-w:1` alias `--when-inactive`/`--when-active`.
 - Remove deprecated value `all/e` for `--edit`, use `all` or `0`.
 - `-s` is now an alias for `--smoothing`.

## Features
 - Add the `blackdetect` edit method, which marks frames as loud when at least `threshold` of their pixels are black. Wrap in `(not ...)` to cut black fades/dead air.
 - Add the `duck` audio action (autoduck/sidechain), which lowers a clip's audio wherever the louder audio layers beneath it (higher track indices) are active — e.g. tuck a music/desktop track under a voice track. Applied when audio layers are mixed; a no-op on the bottom-most layer and on single-layer audio.
 - Add the `erosion` action (3x3 local-minimum filter, a gritty eaten-away look) and the `choke:[n]` action, which shrinks the alpha matte left by `colorkey`/`chromakey` inward by `n` pixels to cut off key-color spill fringe on overlay tracks.
 - Add the `aberration` action, which fakes chromatic aberration by shifting the color channels apart for a cheap-lens/glitch color-fringing look.
 - The `pos` action is now animatable: each of `x`, `y`, and `scale` takes a keyframe ramp (`pos:0..600:300:1..0.5`) with optional easing, so an overlay can slide and resize across a section. The `add:path:x:y:scale` placement fields accept the same ramps (`add:logo.png:0..1000:300:1..0.5`).
 - `premiere` export (fcp7) can now handle overlays.
 - `premiere-otio` export can now handle overlays, more actions, and animations.


## Performance
 - 

## Fixes
 - The `regex`, `subtitle`, and `word` edit methods now advance positional arguments, so `stream` and `ignore-case` work when passed by position (e.g. `(word "hi" 0 #f)`), not only as keywords.
 - The `levels` command now accepts the `ignore-case` parameter for the `word`/`regex`/`subtitle` methods and honors case-folding (`word` is case-insensitive by default), matching `--edit`.
 - URL inputs edited with only `subtitle`/`word`/`regex` no longer download the full video; these methods read the subtitle stream, so just audio is fetched.
 - `add:` overlays now follow the base layer's cuts by default, staying time-synced like a second camera angle, instead of restarting from frame 0 each kept section. Pass `follow-base=0` (e.g. `add:logo.gif:follow-base=0`) to restore the restart-per-section behavior for logos/gifs.
 - The render now copies the source's display-matrix rotation onto the output, so phone-shot portrait videos (stored landscape with a rotate flag) no longer play sideways.
 - The v3 timeline format gained a `templateFile` field (the first input), used as the source for stream rotation and attachment passthrough.
 - Re-enable the `qtrle` (QuickTime Animation) decoder, so legacy alpha-channel overlay `.mov` files composite onto a base track instead of failing with "Decoder not found".
