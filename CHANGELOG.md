# 30.1.2

## Major
 -

## Features
 -

## Fixes
 - Add task for building for wasm32 (for the web).
 - Add task for building auto-editor dynamically.
 - Fix expressions that only work when `int` is 8 bytes.
 - Merge similar functions into one, e.g. `tl.len` `initLayout`.
 - Avoid some allocations by using `av.openFormatCtx` instead of `av.open`.

