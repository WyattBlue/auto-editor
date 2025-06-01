# 28.0.0

## Major
- Remove deprecated `--keep-tracks-separate`.
- Remove the "audio" export format. Set the output extension to an audio format instead.
- Replace JSON timeline export with explicit v1/v3 versions

## Features
- Set `--output/-o` to `-` to print to stdout. Supported with JSON/XML timeline formats.

## Fixes
- Use better way to calculate timeline length.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/27.1.1...28.0.0


# 27.1.1

## Fixes
 - Avoid making empty `*_tracks` directories.
 - Require `--output` if no suitable name can be auto-selected.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/27.1.0...27.1.1


# 27.1.0

## Features
 - Stream the input source's audio samples, instead of memory mapping an entire wav file.
 - Add `--audio-layout`, which allows changing the number of channels (`mono`, `stereo`, etc.).

## Fixes
 - Print an error message instead of raising an exception if `--export premiere` is used with an empty timeline.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/27.0.0...27.1.0


# 27.0.0

## Major
 - Deprecate `--keep-tracks-separate`, it's behavior is now the default. Use `--mix-audio-streams` for the old behavior.
 - Remove deprecated "copy" codec (auto-editor never does remuxing).
 - Require NumPy >= 2.
 - Switch from PyAV to [BasswoodAV](https://github.com/basswood-io/BasswoodAV)

## Features
 - Make video rendering 11% faster, rendering should be 19% faster overall.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.3.3...27.0.0


# 26.3.3

## Fixes
 - Suppress warnings if movflags do not apply.
 - Add `--faststart` and `--no-faststart` to enable/disable ffmpeg's `-movflags +faststart`.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.3.2...26.3.3


# 26.3.2

## Fixes
  - Fix regression in 26.3.0 that caused audio-only exports to have no data.
  - Support outputting fragmented mp4/mov files with `--fragmented`.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.3.1...26.3.2


# 26.3.1

## Fixes
 - Mux frames in the correct order, this fixes problems with media player's seeking in large files.
 - Lay out the video stream first.
 - Fix bug with progress bar being too small (escape characters were being counted in the length).
 - Fix problem with experimental encoders/decoders (by removing them).

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.3.0...26.3.1


# 26.3.0

## Features
 - Show codecs used in the progress bar.
 - Support the prores encoder.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.2.0...26.3.0


# 26.2.0

## Features
 - Allow all hardware encoders PyAV knows about (h264\_videotoolbox, libsvtav1, hevc\_nvenc, etc.).
 - New option `-vprofile`. Allows setting the video profile.

## Misc.
 - Deprecate the `copy` codec (auto-editor always re-encoders no matter what).

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.1.1...26.2.0


# 26.1.1

## Fixes
 - Allow storing multiple cache entries.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.1.0...26.1.1


# 26.1.0

## Features
 - Use PyAV 14.

## Fixes
 - Remove `--ffmpeg-location` arg.
 - Remove help text for recently removed args.
 - Fix unicode error on Windows for the info command.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.0.1...26.1.0


# 26.0.1

## Fixes
 - Fix `ssa` not being a known format.
 - Catch exception when parsing invalid bitrate.
 - Remove the `--my-ffmpeg` `--show-ffmpeg-commands` `--show-ffmpeg-debug` cli options.
 - Remove the `ae-ffmpeg` package dependency.
 - Remove unused args, functions.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/26.0.0...26.0.1


# 26.0.0

## Major
 - You can now preview videos before rendering is complete. (see footnote 1).
 - `unset` is now never a valid codec. Use `auto` instead.
 - `unset` is now not a valid bitrate value. Use `auto` instead.
 - Removed the `--extras` and `-qscale:v` cli options.
 - The `ae-ffmpeg` pypi package is deprecated and will be removed in a future release. Future versions of auto-editor will not ship ffmpeg cli binaries.
 - The `--my-ffmpeg` `--ffmpeg-location` `--show-ffmpeg-commands` and `--show-ffmpeg-debug` cli options are now deprecated and can be removed in a future `26.x` release.

## Features
 - Auto-Editor is consistency twice as fast as `25.x` if `-c:a pcm_s16le` is set.
 - Auto-Editor is now 20% faster to 50% slower with default options. (see footnotes 2 and 3).
 - Remove all uses of ffmpeg-cli in auto-editor, with the exception of a few holdouts (EBU norm, audio mixing, yt-dlp).
   * using GPL vs LGPL builds of PyAV now determine if the `libx264` or `libopen264` encoder is used.

## Fixes
 - Never write a "null frame" if the timeline is known to be linear. Fixes #468

## Footnotes
 - [1] You can preview media files if they are in the Matroska format (`.mkv`). Although `.mp4` hybrid could theoretically work, ffmpeg does not appear to have sufficient support yet. YMMV with other formats.
 - [2] Smaller files perform better. Larger files perform worse compared to `25.x` when using a solid state drive/fast storage.
 - [3] It should be possible to eventually recover this lost performance. Either with multiprocessing, or multi-threading with GIL-free builds of Python.

## Known Regressions
 - Data Streams, Attachment Streams, and Embedded Image (video) streams are now always dropped due to some limitations with the current version of PyAV. This should be fixed in a future version of `26.x`

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/25.3.1...26.0.0


# 25.3.1

## Features
 - Use PyAV 13.1

## Fixes
 - Make correct webvtt files, fixes #531
 - Don't open player when exporting as clip-sequence

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/25.3.0...25.3.1


# 25.3.0

## Features
 - Add `-dn` option. Allows data streams to be dropped from final output.
 - Allow using older version of final cut pro. Example: `--export final-cut-pro:version=10`

## Fixes
 - Add file "last modified time" to cache string. Fixes #536
 - Fix `motion` returning lower values than it should.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/25.2.0...25.3.0


# 25.2.0

## Features
 - Use PyAV 13
 - Add stacktraces to the Palet Programming Language
 - Add `input-port?` type and more procedures. Helpful for writing custom edit procedures in `config.pal`.

## Fixes
 - Prevent colon form from evaluating arguments eagerly
 - Set upper bounds on dependencies

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/25.1.0...25.2.0


# 25.1.0

## Features
 - Add the DaVinci Resolve FCP7 backend. It's not the default since there are known issues, but it is available if you're having other issues with the FCP11 backend.
 - Add `--config` flag option. When set, it will look for `./config.pal`. If found, it allows extending auto-editor by adding new editing methods by defining new procedures.

## Fixes
 - Fix "divide by zero error" when editing subtitle streams when a speed is exactly 0.
 - Removed the "speed" warning for the DaVinci Resolve FCP11 backend because it appears to not be true anymore for DaVinci Resolve 19 (maybe 18?) and newer.
 - Allow including/excluding the Palet standard environment for applications like pyinstaller.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/25.0.1...25.1.0


# 25.0.1

## Fixes
 - Hardcode that `.mp4` files support `srt` subtitles. Fixes #493
 - Info: display audio layout
 - Add PyAV License to the `--debug` screen
 - Improve argument parsing error messages

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/25.0.0...25.0.1


# 25.0.0

## Major
 - Switch versioning system from "CalVer weeks of the year" to SemVar.

## Features
 - Make temp directories lazily. This will mean a temp directory is not created at all in some cases.
 - Add the `--no-cache` option. When set, will prevent auto-editor from reading from or writing to a cache file.

## Fixes
 - Step around PyAV bug when getting pix_fmt. Fixes #489
 - Add `hevc_nevc` as a known encoder. Fixes #490
 - The cache is twice as small as the equivalent 24w31a would write.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w31a...25.0.0


# 24w31a

## What's Changed
 - Bug fix: never set the color primary if the value is 0
 - Palet: add `max-seq` and `min-seq` procedures

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w30a...24w31a


# 24w30a

## What's Changed
 - Upgrade to PyAV 12.3
 - Use PyAV to get encoder information instead of maintaining a big list
 - Audio analysis no longer writes a temporary WAV file

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w29a...24w30a


# 24w29a

## What's Changed
 - Use numpy's `.npz` for smaller and faster caching
 - Add `audio-levels` `motion-levels` to Palet
 - In general, remove lines of code

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w25a...24w29a


# 24w25a

## What's Changed
 - Only extract subtitle files when needed
 - Analyze subtitles robustly, don't rely on hacky methods
 - Assert generated timeline is monotonic (fixes #470)
 - Errors are now colored, will be disabled if NO_COLOR or AV_LOG_FORCE_NOCOLOR environment variable is set

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w24a...24w25a


# 24w24a

## What's Changed
 - Use `pyav` 12.1.0, the first release that is compatible with `av`
 - Handle import v1 timelines better

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w19a...24w24a


# 24w19a

## What's Changed
 - Round timebase to two-digits, which should fix a Premiere Pro issue
 - v3 format: offset is no longer implicitly multiplied by clip speed
 - Consider `libopus` a valid encoder

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w13a...24w19a


# 24w13a

## What's Changed
 - Color space handling has been improved
 - Having ffprobe is no longer required
 - `auto-editor subdump` now only uses/requires PyAV

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w09a...24w13a


# 24w09a

## What's Changed
 - By default, all tracks will now be considered when editing audio
 - Premiere Export: Fix 24w07a regression where only a single audio channel would play
 - Auto-Editor will now never attempt to copy attachments unless subtitle streams are present
 - `audio` `motion` `subtitle` are now no longer special lexer constructs

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w07a...24w09a


# 24w07a

## What's Changed
 - Fix crash on certain resolutions for legacy macs
 - Final Cut Export: always set "start" attribute even when value is 0
 - Premiere Export: additional tracks no longer need external wavs
 - Fix crash for all `.ts` media files

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/24w03a...24w07a


# 24w03a

## What's Changed
 - Analyzing motion is now 1.3x faster.
 - Changing the aspect ratio (adding padding) is now 2.7x faster.
 - Better support for the `yuv444p` `yuvj444p` pix_fmt's
 - Dropped the Pillow dependency
 - Upgrade pyav to 12.0.2

## Breaking Changes
 - Removed `--mark-as-loud` and `--mark-as-silent`. Use `--add-in`, `--cut-out` instead.
 - Removed `pixeldiff` as an option for `--edit`. Use `motion` instead.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w51a...24w03a


# 23w51

## What's Changed
 - Upgrade pyav to 12.0.0
 - Sources are now directly linked in the v3 format.
 - Removed the `--source` and `--add` option
 - Switch from setup.py to pyproject.toml

Remember to upgrade setuptools! `pip install -U setuptools`

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w46a...23w51a


# 23w43a

## What's Changed
 - Bump pyav from `11.0.1` to `11.2.0`
 - Bump Pillow from `10.0.1` to `10.1.0`
 - Palet: added `append class eval for-items list list?`, and fixed many bugs
 - Removed the ability to draw text and ellipse shapes.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w40a...23w43a


# 23w38a

## What's Changed
 - Auto-Editor now knows all h264, hevc, av1, and prores encoders
 - Bump `pillow` from 10.0.0 to 10.0.1
 - Palet: Rename `string-append` to `&`, add `&=`
 - Palet: `/` will now return a float, unless all numbers are frac? or any number is complex.
 - Palet: Add keyword datatype, allow keyword parameters for `define`

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w35a...23w38a


# 23w35a

## What's Changed
 - Removed support for Python 3.9, use 3.10 or 3.11
 - DaVinci Resolve: Use fcp10 format instead of fcp7
 - Palet: Add `incf` `decf` `case`
 - Palet: Add dot syntax and lang pragma

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w32a...23w35a


# 23w32a

## What's Changed
 - Final Cut Pro XML: Fix desync issue / Use modern APIs
 - Palet: Add `hash-ref` `hash-set!` `hash-update!` `hash-remove!`
 - Palet: Fix `hash` incorrectly erroring when its arity is 0
 - Palet: `ref` no longer accepts hashes


# 23w31a

## What's Changed
 * ShotCut: support exporting multiple videos
 * Palet: Implement lexical scoping
 * Palet: Add `let` `let*` `system` `cond` `sleep` `error`
 * Palet: Improve variable error messages

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w28a...23w31a


# 23w28a

## What's Changed
 - Fix ShotCut export producing wrong cuts
 - Translate README to Chinese by @flt6 in https://github.com/WyattBlue/auto-editor/pull/361
 - Add back `var-exists?` procedure, add `rename` and `delete` syntax
 - Info subcommand: remove `--include-vfr`
 - Bump pillow version to 10.0.0

## New Contributors
* @flt6 made their first contribution in https://github.com/WyattBlue/auto-editor/pull/361

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w24a...23w28a


# 23w24a

## What's Changed
- Added the following procedures: `assert` `array-copy` `between/c` `div` `maxclip` `maxcut`
  - `maxcut` and `maxclip` were added to address #348
- Fix displaying vectors
- Updated `--audio-normalize ebu`'s contracts so they match the ranges for ffmpeg >=6

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w21a...23w24a


# 23w21a

## What's Changed
 - wavfile: immediately return when data chunk is read (fixes #351)
 - fcp7: fix reading pathurl

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w20b...23w21a


# 23w20b

## What's Changed
 - Work around DaVinci Resolve bug where timeline will break strangely if `<duration>` tag in `<file>` is not present even though the value is not used

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w20a...23w20b


# 23w20a

## What's Changed
- fcp7 backend (Premiere and DaVinci Resolve)
  - You can now export multiple video files into one xml
  - The xml now respects the number of channels the audio has and no longer assumes it's always 2
- v3 timeline backend
  - the `"timeline"` key has been flatten and removed
  - `"version"` value has been changed `"unstable:3.0"` -> `"3"`
  - the `"dur"` attribute for all timeline objects is now always the "real" duration even if the speed is != 1. This makes many internal operations simpler and imitates how fcp7 represents timing.
 - v1 timeline importing and exporting is back
 - All v(NUMBER) timelines now no longer use or accept semantic versioning

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w15a...23w20a


# 23w15a

## What's Changed
 - Only allow valid bitrate units  `k` `K` `M`
 - Handle previously unhandled exceptions when parsing certain options with invalid values
 - Pin pillow to `9.5.0`

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w12a...23w15a


# 23w12a

## What's Changed
 * Support for DaVinci Resolve is now added back in. Added the `--export resolve` `-exr` and `--export-to-resolve`

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w11a...23w12a


# 23w11a

## What's Changed
* Add new option `--audio-normalize` that can apply EBU R128 or Peak audio normalizing methods
* Change default video bitrate from 10m to 10M by @hunterhogan in https://github.com/WyattBlue/auto-editor/pull/337

## New Contributors
* @hunterhogan made their first contribution in https://github.com/WyattBlue/auto-editor/pull/337

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w10c...23w11a


# 23w10c

## Breaking
- `--edit all` is now `--edit all/e`

## What's Changed
- **Bug Fix** Premiere can now find the source file in Premiere XMLs
- Levels subcommand
  - Levels now has start tag to ensure no dropped data
  - Levels can now use `none` and `all/e` edit methods

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w08a...23w10c


# 23w08a

## What's Changed
- `auto-editor info` now displays the audio stream's channel count
- `--add` now uses palet for parsing instead of having a little parsing language for each attribute.
```shell
#  old way, adding special characters like newline and tab was terrible
auto-editor --add 'text:0,60,This is my text!
Wow,font=Arial'

#  new clean and explicit way
auto-editor --add 'text:0,60,"This is my text!\nWow",font="Arial"'
```
- The palet scripting language, and its [associated docs](https://auto-editor.com/ref/23w08a/palet), has been greatly improved. For a normal auto-editor, palet doesn't matter right now, but allow for new and exciting auto-editor functionally in the future.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/23w04a...23w08a


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


# 22w52a

## What's New
- Fix capital file extensions confusing auto-editor

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w48a...22w52a


# 22w48a

### Bug Fixes
 - Fixed all of the subcommands not working when auto-editor is installed with pip
 - Make having the `readline` module optional for `repl`. This allows Windows to use it without immediately causing a traceback.

### Features
Auto-Editor can now read use its own v2 json timelines. v2 timelines are still undocumented and unstable[1] but is a step in the right direction and opens up the way for more powerful Premiere, ShotCut and FinalCutPro exports.

[1] In the sense that how it works can change from version to version.

### Breaking Changes
Exporting v1 json timelines has been removed due to in part to format being entirely undocumented. Auto-Editor still uses a v1-format like structure for "Editor" exports and

### What to Expect in the Future
Besides making 'Premiere and friends' exports better, Auto-Editor will not work on new features till at least mid-Jan, 2023. Instead improving documentation will be the primary focus.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w46a...22w48a


# 22w48a

### Bug Fixes
 - Fixed all of the subcommands not working when auto-editor is installed with pip
 - Make having the `readline` module optional for `repl`. This allows Windows to use it without immediately causing a traceback.

### Features
Auto-Editor can now read use its own v2 json timelines. v2 timelines are still undocumented and unstable[1] but is a step in the right direction and opens up the way for more powerful Premiere, ShotCut and FinalCutPro exports.

[1] In the sense that how it works can change from version to version.

### Breaking Changes
Exporting v1 json timelines has been removed due to in part to format being entirely undocumented. Auto-Editor still uses a v1-format like structure for "Editor" exports and

### What to Expect in the Future
Besides making 'Premiere and friends' exports better, Auto-Editor will not work on new features till at least mid-Jan, 2023. Instead improving documentation will be the primary focus.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w46a...22w48a


# 22w46a

## What's Changed
- ffmpeg colorspace won't be set if applied value is `reserved`
- Fixed premiere xml export setting `channelcount` to `10` instead of `2`
- Bug Fix: Handle PyAV reporting `stream.duration` as `None` instead of crashing #313

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w43a...22w46a


# 22w43a

## Changes
Add Python 3.11 support, drop Python 3.8 support
Improve Premiere Pro and ShotCut XML reading

## New Features
--edit now has direct access to the `margin` `mincut` `minclip` `cook` functions. Along with `or` `and` `xor` `not`

```
--edit '(or (margin 5 motion:4%) (cook 6 3 audio:threshold=4%))
```

## Bug Fixes
Fix `or` `and` `xor` length resizing. Old behavior added random data instead of just filling zeros.

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w39a...22w43a


# 22w39a

## Changes
 * Auto-Editor can now read Premiere xml files, provided that it follows a very strict subset of features
 * Timeline files now have `_ALTERED` part added
 * Premiere XML and ShotCut MLT timeline files have been improved

## Bug Fixes
 * Fixed bug on Windows that caused sound to not render right when speed was changed

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w37a...22w39a


# 22w37a

## New Features

You can now add audio to the timeline and change its volume.
```
auto-editor movie.mp4 \
--source my-background:/Users/wyattblue/Downloads/music.mp3 \
--add audio:0,500,my-background,volume=0.7
```

Auto-Editor renders volume using FFmpeg's [volume audio filter](https://www.ffmpeg.org/ffmpeg-filters.html#volume) and accepts both raw floats and decibels.

### dB units for audio threshold

dB is now a supported unit.

```
auto-editor --edit audio:threshold=-24dB  # equivalent to 0.063
```

## Minor Improvements
 * ZipSafe is now set to True, which makes auto-editor slightly faster
 * You can now add background music/audio


## Breaking Changes
 * Removed `--timeline` and `--api` options. Instead, use the export option as so: `--export timeline:api=$VAL`

## Bug Fixes
* Final Cut Pro: Use numerator and denominator of timebase fraction by @marcelohenrique in https://github.com/WyattBlue/auto-editor/pull/302

## New Contributors
* @marcelohenrique made their first contribution in https://github.com/WyattBlue/auto-editor/pull/302

**Full Changelog**: https://github.com/WyattBlue/auto-editor/compare/22w35c...22w37a

