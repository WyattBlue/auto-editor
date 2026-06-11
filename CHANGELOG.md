# 30.5.1

## Major
 -

## Features
 - Add the `erosion` action (3x3 local-minimum filter, a gritty eaten-away look) and the `choke:[n]` action, which shrinks the alpha matte left by `colorkey`/`chromakey` inward by `n` pixels to cut off key-color spill fringe on overlay tracks.
 - Add the `blackdetect` edit method, which marks frames as loud when at least `threshold` of their pixels are black. Wrap in `(not ...)` to cut black fades/dead air.

## Performance
 - 

## Fixes
 - The `regex`, `subtitle`, and `word` edit methods now advance positional arguments, so `stream` and `ignore-case` work when passed by position (e.g. `(word "hi" 0 #f)`), not only as keywords.
 - The `levels` command now accepts the `ignore-case` parameter for the `word`/`regex`/`subtitle` methods and honors case-folding (`word` is case-insensitive by default), matching `--edit`.
 - The Edit Reference page is now generated from the source, so it documents `word`, `regex`, `xor`, and `not` (previously omitted), corrects `motion`'s argument order, and drops the unimplemented `max-count`.
 - URL inputs edited with only `subtitle`/`word`/`regex` no longer download the full video; these methods read the subtitle stream, so just audio is fetched.
