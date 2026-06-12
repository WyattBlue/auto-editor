# 30.5.1

## Major
 - Remove deprecated value `all/e` for `--edit`, use `all` or `0`.

## Features
 - Add the `erosion` action (3x3 local-minimum filter, a gritty eaten-away look) and the `choke:[n]` action, which shrinks the alpha matte left by `colorkey`/`chromakey` inward by `n` pixels to cut off key-color spill fringe on overlay tracks.
 - Add the `blackdetect` edit method, which marks frames as loud when at least `threshold` of their pixels are black. Wrap in `(not ...)` to cut black fades/dead air.
 - Add the `aberration` action, which fakes chromatic aberration by shifting the color channels apart for a cheap-lens/glitch color-fringing look. Use the shorthand `aberration[:h[:v[:edge]]]` for a symmetric red/blue split (horizontal `h`, vertical `v`, `edge` of `smear`/`wrap`), or `key=value` pairs (`rh rv gh gv bh bv edge`) for full per-channel control, e.g. `aberration:rh=8:bh=-8:gv=2:edge=wrap`.
 - The `pos` action is now animatable: each of `x`, `y`, and `scale` takes a keyframe ramp (`pos:0..600:300:1..0.5`) with optional easing, so an overlay can slide and resize across a section. The `add:path:x:y:scale` placement fields accept the same ramps (`add:logo.png:0..1000:300:1..0.5`). Overlays are placed at sub-pixel positions, so slow motion slides smoothly instead of stair-stepping.

## Performance
 - 

## Fixes
 - The `regex`, `subtitle`, and `word` edit methods now advance positional arguments, so `stream` and `ignore-case` work when passed by position (e.g. `(word "hi" 0 #f)`), not only as keywords.
 - The `levels` command now accepts the `ignore-case` parameter for the `word`/`regex`/`subtitle` methods and honors case-folding (`word` is case-insensitive by default), matching `--edit`.
 - The Edit Reference page is now generated from the source, so it documents `word`, `regex`, `xor`, and `not` (previously omitted), corrects `motion`'s argument order, and drops the unimplemented `max-count`.
 - URL inputs edited with only `subtitle`/`word`/`regex` no longer download the full video; these methods read the subtitle stream, so just audio is fetched.
