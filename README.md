[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w24a
# Auto-Editor
Auto-Editor is a command line application program for automatically editing video/audio into a entertaining and polished output.
It works by analyzing the video's audio to detect when a section needs to be cut, kept in, or zoomed in, then it runs a subprocess called ffmpeg to create the new video.

## New in 20w24a!
 * You can now use m4a audio files as an input type
 * Small output bug now fixed

# Usage
## Minimal Example

Create an edited version of example.mp4 with the default parameters.
```terminal
 $ python auto-editor.py example.mp4
```

## Change the Feel
You can change the pace of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```terminal
 $ python auto-editor.py example.mp4 --frame_margin 8
```

There are many more features in auto-editor, including adding in background music that automatically gets quieter and zooming in the video when it gets especially loud.

[See the docs](/resources/docs.md) for more commands and usages.


# Installing Auto-Editor
[Installing for Windows](/resources/install_win.md)

[Installing for Mac](/resources/install_mac.md)

[Installing for Linux](/resources/install_lin.md)

# Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).
