# 23w04a

## What's New

### New Features
 - Added `subtitle` edit method. `subtitle` analyzes subtitle streams and adds sections when any subtitle shown on screen matches the given regex pattern.
 - Added new attribute: `name` for the `premiere` and `final-cut-pro` export object. 

### Breaking Changes
 - Removed `--min-clip` `--min-cut` cmd options. Use `minclip` and `mincut` procedures in the `--edit` option or the new `mincut` `minclip` attributes on the `audio` edit method: `--edit audio:mincut=4,minclip=3`
 - Removed `--show-ffmpeg-debug`. Instead use `--show-ffmpeg-commands` or `--show-ffmpeg-output`
 - Removed the `grep` subcommand. The new `subtitle` edit method does all of its functionality

### Palet
"Palet" is auto-editor's scripting language used in the `--edit` option and `repl` subcommand. It is similar to the racket language but has a few differences. Palet existed in earlier versions but it wasn't worth mentioning in the release notes until now.  The biggest change is that you can now define your own procedures:

```racket
(define circle-area (lambda (r) (* pi (* r r)))) 
(circle-area 5)
> 78.53981633974483

```


### Dependencies
 - Upgrade Pillow `9.3.0 -> 9.4.0`

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w52a...23w04a

