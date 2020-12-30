## How to Use Motion Detection in Auto-Editor

Use the `--edit_based_on` option and pick the choice `motion`. Auto-Editor will then look at each frame and determine the percentage of how many pixels have changed. You can choose what percentage motion is considered "active" by using `--motion_threshold`.

To remove the effect of random noise, each frame gets shrunken down and blurred before being compared.

Run `auto-editor --edit_based_on --help` to see all the options, and you should see the following.

```
audio,
motion,
not_audio,
not_motion,
audio_or_motion,
audio_and_motion,
audio_xor_motion,
audio_and_not_motion,
not_audio_and_motion,
not_audio_and_not_motion,
```

All of these choices are ones you can choice to change how Auto-Editor edits videos. For example `auto-editor my_video.mp4 --edit_based_on audio_or_motion` would tell auto-editor to create a new video, my_video_ALTERED.mp4, that has only non-silent sections or parts where the video moves a lot.

Some of the options may seem a bit arcane at first, so here are some visuals to help see better what each choice does.

<img src="example.png" width="500">

Think of audio and motion like a Venn diagram where the intercept is where the program detects both loudness and motion.

Audio by itself, (the default) would mean only leave in the parts where it is not silent. It's just a circle on the diagram.

<img src="audio.png" width="500">

and Not Audio would mean leave in the parts only where it is silent. Everywhere is colored except the audio circle.

<img src="not_audio.png" width="500">

Motion works the same way.

<img src="motion.png" width="500">

<img src="not_motion.png" width="500">

And if you want to leave in the parts with only loud parts and moving parts.

<img src="audio_and_motion.png" width="500">

And the or operator.

<img src="audio_or_motion.png" width="500">

Here are other choices that may or may not be useful.

<img src="audio_xor_motion.png" width="500">

<img src="audio_and_not_motion.png" width="500">

<img src="not_audio_and_motion.png" width="500">

<img src="not_audio_and_not_motion.png" width="500">

This feature is still very new so expect some new features/changes down the line.
