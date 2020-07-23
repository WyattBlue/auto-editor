# Auto-Editor Change Log

## Version 20w30a
* Fixed ffprobe bug that was effecting Windows users.
* Added support for audio tracks for `--export_to_premiere`
* Files in the media folder moved to resources. Changelog and credits moved to resources.

## Version 20w29b
* `--preview` how displays the correct duration for the new output.
* Auto-Editor now works even when running the script in a different working directory.
* The `--debug` and `--verbose` commands have been combined. Both now do the same thing.
* The macOS binaries have been compressed in the 7zip format and should be extracted with Archive Utility.

### Package Change
 * audiotsm removed.
 * audiotsm2 added.

## Version 20w29a [Yanked]
* ffmpeg binaries are included in auto-editor.
* desyncing issue when video speed is set is fixed.
* video cutting off prematurely is fixed.
* originalMethod changed so that it uses modern code and functions.
* `--frame_rate` flag has been removed.
* Changelog added.

> This build had ffmpeg binaries that had licenses that were incompatabile with this project. Those binaries have been removed from history. Please use 20w29b instead.


## Version 20w28a

* **Percentage** units are now supported.
* **Hz** (Hertz) or kHz can be used when setting the sample rate.
* The help screen has been overhauled to be simpler and cleaner.
* **New** dedicated script for handling audio files has been added.
* **Older** versions of Python can now handle hours long audio files without crashing.
* **Auto-Editor** won't crash anymore if your console does not support Unicode characters.


## [Version 20w27b Hotfix](https://github.com/WyattBlue/auto-editor/tree/3786b8b3815c3b0ccc5692fdffa5090aab3ece76)

[Issue #35 fixed.](https://github.com/WyattBlue/auto-editor/issues/35)


## [Version 20w27b](https://github.com/WyattBlue/auto-editor/tree/a876057b1dbfc97fbccb46e6eb780a165d8afa65)

* `--export_to_premiere` flag added.
* `fastVideoPlus.py` is no longer so RAM intensive.
* `preview.py` now uses Python's tempfile.
* The pip module, SciPy, is no longer needed.


## [Version 20w27a](https://github.com/WyattBlue/auto-editor/tree/dc40c66be0c7483840b100c7f58003e8583e0d26)

* **Videos** downloaded with youtube-dl are now named based on their URL.
* **fastVideo.py** and fastVideoPlus now use python's tempfile system.


## [Version 20w26b](https://github.com/WyattBlue/auto-editor/tree/f93313694e8d70f1bf2bccbc01be04baac2507de)

* `--preview` flag added.
* **fastVideo.py** and fastVideoPlus.py now supports multiple audio tracks.
* **Fixed** bug where fastVideoPlus.py did not give enough space for the new audio to take.
* `--frame_quality` has now been removed.
* `--get_frame_rate` aka, --get_auto_fps has been removed.


## [Version 20w26a](https://github.com/WyattBlue/auto-editor/tree/48c7864386b35c6cadc74e120ecf51b790e418af)

* **fastVideoPlus.py** supports more video speeds.
* **Default** sample rate changed from 44100 to 48000. (44.1 kHz -> 48.0 kHz)
* `--frame_quality` default set to highest and marked as depreciated.


## [Version 20w25b](https://github.com/WyattBlue/auto-editor/tree/d17529c13fdf86a8715c416ec2e9e08ab94aff95)

* `--combine_files` flag has been added. It combines them in order of date modified.
* `--prerun` flag has been removed.
* `--loudness_threshold` has been renamed to `--zoom_threshold`.
* **New flag added**, `--no_open`, which prevents the opening of the new file after rendering.
* **New option**, `--audio_bitrate`, which specifies the bitrate.
* Progress bar has been added in fastVideo.py. Thank you all who voted in the discord server.


## [Version 20w25a](https://github.com/WyattBlue/auto-editor/tree/adb78278ad1aa2fcb0aadbf0c3c9cad6155c40e7)

* **New Feature**: You can now use a folder with videos in there as an input type.
* **Lots** of bug fixes.


## [Version 20w24b](https://github.com/WyattBlue/auto-editor/tree/d26be702ce1f44a3bcb0f66ac8d80819fdee1d0b)

* Introduced a brand new method of editing videos that is 4x faster. In this version, it can't handle changes in sounded or silence speeds so it will default to the original method.
* Fixed rare audio bug that stopped new audio being generated.
* The main script has been split into more manageable parts to aid future collaborators. You can find them in the 'scripts' folder.


## [Version 20w24a](https://github.com/WyattBlue/auto-editor/tree/39a80b986fd986faeefffa16287e71653d325301)

* `m4a` audio files are now supported.
* Videos with variable frame rates are now supported.
* Small output bug now fixed


## [Version 20w23a](https://github.com/WyattBlue/auto-editor/tree/6687d115bd434eba8daf97f87df41b53e6b2e734)

* `--hardware_accel` option added.


----

<h1 align="center">Pre-Version Builds</h1>

## ["Auto-Editor caches your last video..." (May 4, 20w19a)](https://github.com/WyattBlue/auto-editor/tree/233b5bec5b0129986e9b5049f2930b23809ba439)

* Auto-Editor caches your last video. Making a repeated run of the same video much faster. This works even if you have different parameters.

## ["Made auto-editor a lot faster" (May 2, 20w18d)](https://github.com/WyattBlue/auto-editor/tree/51286ac00895740d4d0ca8d4103b7d9b5b3e3abb)

* Added more commands and print statements.

## ["added multi-processing capabilities" (May 1, 20w18c)](https://github.com/WyattBlue/auto-editor/tree/2a4a32a5bf9b5b318cac45f55e125e8d728e7bdd)

* Auto-Editor runs faster but needs more CPU processing.

## ["Update auto-editor.py" (Apr 30, 20w18b)](https://github.com/WyattBlue/auto-editor/tree/35307b5e2968c46fe84cb453d63bd605d135b12e)

* The verbose short `-v` was removed. Verbose checked more in code.
* `--sounded_speed` was changed to `--video_speed`
* Frame margin default was changed from 3 to 4.

## ["Add files via upload" (Apr 30, 20w18a)](https://github.com/WyattBlue/auto-editor/tree/714e5be499aa77afe3748a5ef62feb55f64d02f9)

The project was created.



