[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w23a
# Auto-Editor
Auto-Editor is a video editing tool that can automatically edit raw source video into a entertaining and polished video.
It works by analyzing the video's audio to detect when a section needs to be cut, kept in, or zoomed in, then auto-editor runs a subprocess called ffmpeg to create the new video.

## New in 20w23a!
You can now enable hardware acceleration with the `--hardware_accel` flag.

```terminal
 $ python3 auto-editor.py example.mp4 --hardware_accel SomeHardware
```

What APIs you have avaiable determines from machine to machine. To see what's avaiable for you run this command:

```terminal
 $ ffmpeg -hide_banner -hwaccel asdf -i example.mp4 out.mp4
```

and it will show the supported hwaccels. This is important because auto-editor will not show a warning for selecting a non-existant hardware setting, even with the `--verbose` flag.

### Other stuff

## Note:

This feature isn't new to this version but `--debug` flag with say if your version of python is running a 64-bit version or not.

# Usage
## Minimal Example

Create an edited version of example.mp4 with the default parameters.
```terminal
 $ python auto-editor.py example.mp4
```

## Change the Feel
You can change feel of the video by changing how much frames

```terminal
 $ python auto-editor.py example.mp4 --frame_margin 8 --silent_threshold 0.03
```

See [the docs](/github%20resources/docs.md) for more commands and usages.


# Installing Auto-Editor
[Installing for Windows](/github%20resources/install_win.md)

[Installing for Mac](/github%20resources/install_mac.md)

[Installing for Linux](/github%20resources/install_lin.md)

# Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).
