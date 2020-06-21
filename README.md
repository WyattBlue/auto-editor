[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w25b
# Auto-Editor
Auto-Editor is a command line application program for automatically editing **video or audio**.
It works by analyzing the video's audio to detect when a section needs to be cut or kept in, then it runs a subprocess called ffmpeg to create the new video.

## New in 20w25b!
 * If you are using a **folder** as an input, you can now combine all files in a folder **before editing** with the `--combine_files` flag. It combines them in order of date modified.
 * The `--prerun` option has been **removed** due to the fact that all it does is create the cache folder which is less important because of both general speed increases and the fact that the most common method of editing videos (fastVideo.py) don't need to make a cache folder nor need every frame converted to a jpeg.
 * fastVideo.py now has a
 * `--loudness_threshold` has been **renamed** to `--zoom_threshold` sense it is a better description of what it does.
 * new option added `--no_open`, which prevents the opening of the new file after rendering. Useful when editing lots of videos.

## Usage
### Minimal Example

Create an edited version of example.mp4 with the default parameters.
```terminal
 $ python auto-editor.py example.mp4
```

### Change the Feel
You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```terminal
 $ python auto-editor.py example.mp4 --frame_margin 8
```

There are many more features in auto-editor, including **adding in background music** that automatically gets quieter, and **zooming in** the video when it gets especially loud.

[See the docs](/resources/docs.md) for more commands and usages.


## Installing Auto-Editor
[Installing for Windows](/resources/install_win.md)

[Installing for Mac](/resources/install_mac.md)

[Installing for Linux](/resources/install_lin.md)

## Contributing
The best way to contribute is to [fork auto-editor](https://github.com/WyattBlue/auto-editor/fork) and make changes there. Once you're happy with those changes, make a new pull request and type in a brief description on how you improved the code.

No change is too small whether that be a typo in the docs or a small improvement of code.

## Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).
