[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w24b
# Auto-Editor
Auto-Editor is a command line application program for automatically editing **video or audio**.
It works by analyzing the video's audio to detect when a section needs to be cut or kept in, then it runs a subprocess called ffmpeg to create the new video.

## New in 20w24b!
 * Introduced a brand new method of editing videos that is **4x faster**. Right now, it can't handle changes in sounded or silence speeds so it will default to the original method.
 * Fixed rare audio bug that stopped new audio being generated.
 * The main script has been split into more manageable parts to aid future collaborators. You can find them in the 'scripts' folder.

 For old users, remember to install cv2 for python.
 ``` $ pip3 install opencv-python```

# Usage
## Minimal Example

Create an edited version of example.mp4 with the default parameters.
```terminal
 $ python auto-editor.py example.mp4
```

## Change the Feel
You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```terminal
 $ python auto-editor.py example.mp4 --frame_margin 8
```

There are many more features in auto-editor, including **adding in background music** that automatically gets quieter, and **zooming in** the video when it gets especially loud.

[See the docs](/resources/docs.md) for more commands and usages.


# Installing Auto-Editor
[Installing for Windows](/resources/install_win.md)

[Installing for Mac](/resources/install_mac.md)

[Installing for Linux](/resources/install_lin.md)

# Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).
