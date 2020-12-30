# How to Edit Videos Using Auto-Editor

## Frame Margin

Frame margin is the most basic and useful tool you have. It adds X amount of frames of silence between each clip.
For example, `--frame_margin 15` will add 15 frames of silence to the front of the clip **and** 15 frames of silence to the back too.

A frame margin of 6 (the default), will edit the video leaving just a bit of silence between each cut.

A frame margin of 15 will leave more silence and sound more laid back, ideal for longer media like live-streams, or podcasts.

A frame margin of 3 will sound very "jumpcutty" and is only appropriate for videos less than a minute.

A frame margin of 0 will leave no space, and will sound manic and like you're talking over yourself.


Frame margin is framerate (fps) dependent, so a frame margin of 6 on a 30fps video is the equivalent of a frame margin of 12 on a 60fps video.

> Audio files which don't have framerates, will be treated as if they have 30fps.

## Removing small clips.

Sometimes, you'll have very short loud noises that would look weird of left in. (for example, bumping something, or a short 'uhh') You can filter these annoyances, and other short clips by using `--min_clip_length`.

`3` is the default value, and means and clip that is less than 3 frames long will be removed.