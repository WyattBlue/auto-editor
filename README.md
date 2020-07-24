[![Build Status](https://travis-ci.com/WyattBlue/auto-editor.svg?branch=master)](https://travis-ci.com/WyattBlue/auto-editor)
 &nbsp;&nbsp;<sup>version 20w30a

<p align="center">
  <img src="/resources/auto-editor_banner.png" width="700">
</p>


**Auto-Editor** is a command line application for automatically **editing video and audio** by removing the silent parts.

## New in 20w30a
 * Fixed ffprobe bug that was effecting Windows users.
 * Added support for audio tracks for `--export_to_premiere`
 * Files in the media folder moved to resources. Changelog and credits moved to resources.

[See the Changelog](/resources/CHANGELOG.md) for all the differences between releases.

## Usage
Create an edited version of example.mp4 with the default parameters.
```terminal
 $ python auto-editor.py example.mp4
```

You can change the **pace** of a video by changing by including frames that are silent but are next to loud parts. A frame margin of 8 will add up to 8 frames before and 8 frames after the loud part.

```terminal
 $ python auto-editor.py example.mp4 --frame_margin 8
```

There are many more features in auto-editor, including **adding in background music** that automatically gets quieter, and **zooming in** the video when it gets especially loud.


## Installing Auto-Editor
 1. Download and Install the Latest Version of [Python 3](https://www.python.org/downloads/).

 2. Download [Auto-Editor.](https://github.com/WyattBlue/auto-editor/archive/master.zip)

 3. Open the ZIP file.

 4. Open Your Console. (Command Prompt on Windows, Terminal on MacOS)

 5. Type in the Console, `cd` and space.

 6. Drag the folder, "auto-editor-master", to your Console. Let go of the mouse button, then hit enter. You are now in the auto-editor-master directory.

 7. Run `pip3 install -r requirements.txt`

The binaries you'll need are already installed, unless you're using Linux.
Linux users need to run this command. `sudo apt-get install libavformat-dev libavfilter-dev libavdevice-dev ffmpeg`

Now run it with the example video to make sure it is working.

```terminal
python3 auto-editor.py example.mp4
```

If that works then congratulations, you have successfully installed auto-editor. You can use now use this with any other type of video or audio that you have.

```terminal
python3 auto-editor.py C:path\to\your\video
```

[See the docs](/resources/docs.md) for more commands and usages.


## Contributing
The best way to contribute is to [fork auto-editor](https://github.com/WyattBlue/auto-editor/fork) and make changes there. Once you're happy with those changes, make a new pull request and type in a brief description on how you improved the code.

No change is too small whether that be a typo in the docs or a small improvement of code.

## Licensing
The FFmpeg binaries are under the [LGPL License](/scripts/win-ffmpeg/LICENSE.txt)

wavfile.py is under the [BSD 3-Clause "New" or "Revised" License](https://github.com/scipy/scipy/blob/master/LICENSE.txt)

Everything else in auto-editor is under the [MIT License](/LICENSE)

## Help or Issues
If you have a bug or a code suggestion, you can [create a new issue](https://github.com/WyattBlue/auto-editor/issues/new) on this github page. If you'll like to discuss this project, suggest new features, or chat with other users, do that in [the discord server](https://discord.com/invite/kMHAWJJ).
