# 31.8.1

## Major
 -

## Features
 - Import Final Cut Pro XML: `.fcpxml` files and `.fcpxmld` bundles, with connected clips, transitions, speed, and volume. What a timeline can't hold, such as compound clips, is left out with a warning.
 - Every transition in Premiere Pro, from `push` and `clock-wipe` to `glitch` and `page-peel`, plus its Legacy folder (`iris-round`, `barn-doors`, `push-legacy`, …) and the `constant-power` and `exponential-fade` audio crossfades: `--transition push:0.5sec`. They render natively, and `premiere-otio` exports them as Premiere's own transitions. FCP7 XML carries the dips and `wipe`; other editor exports dissolve instead.
 - Speed ramps: `speed` and `varispeed` take keyframes spread across a section's source, such as `speed:1..8:ease=in` or `speed:1@0%..6@50%..1`. Final Cut Pro and DaVinci Resolve (FCPXML) keep the ramp both ways, including ramps made with Final Cut Pro's Retime menu. Premiere, Shotcut and Kdenlive play the section at the ramp's mean speed.
 - FCP7 XML import brings in Color mattes and Slugs as solid clips, and reads a time remap graph as a speed ramp.
 - Captions in v3 timelines: a `c` field holds caption tracks with their own timing and text, rendered as a text subtitle stream per track (`mov_text` in MP4/MOV, ASS in Matroska, WebVTT in WebM). `final-cut-pro` and `resolve` exports write them as FCPXML captions and import reads them back; other editor exports leave them out with a warning. A `sidecar` field carries a source's embedded subtitle streams through the cuts, including across concatenated inputs.
 - Import and export CMX 3600 EDLs (`--export edl`): one video track and up to four audio channels, as Premiere Pro and DaVinci Resolve write them, with cuts, dissolves, wipes, fades to black and `M2` speed changes. Clip names, source files and transition kinds ride along in the EDL's comments, so a round trip keeps them. An EDL names no frame rate, so the import takes it from the first video file it names; `--frame-rate` overrides. At 29.97 and 59.94 fps the export writes drop-frame timecode, as Premiere and Resolve do.
 - Audio cleanup actions: `highpass` takes out rumble and wind (`highpass` cuts below 80 Hz, `highpass:120` below 120), `lowpass` takes out hiss, and `dehum` notches out mains hum and its harmonics (`dehum` for 60 Hz, `dehum:50` for 50 Hz).
 - Cross Dissolve eases as Premiere Pro 26's does, and v3 timelines keep its Ease In and Ease Out (0 to 100, default 34). Cross Dissolve (Legacy) stays linear.

## Performance
 - A source that plays in two places at once, as across a dissolve or as a picture-in-picture or `loop` overlay of the same file, gets its own decoder for each instead of seeking back to a keyframe every frame. An edit with 1-second dissolves renders 2.5× faster, and a same-file overlay up to 40× faster.
 - Rendering no longer slows down quadratically with the number of clips: 160,000 one-frame clips render in 1.6 seconds instead of 58.
 - Importing FCP7 XML uses about 10% less memory.
 - Importing FCP7 XML is about 30% faster, and FCPXML about 12%.
 - EDL import and export, and FCPXML export, no longer slow down quadratically with the number of clips or captions: a 40,000-clip EDL imports in 0.3 seconds instead of 9, and FCPXML export is up to 20× faster.
 - Rendering at a resolution other than the source's is about 4× faster: the scaler is set up once instead of every frame, and backgrounds are filled a row at a time.
 - Partial-lossless rendering copies H.264 from MPEG-TS sources instead of re-encoding them; cutting a 30-second 720p TS is 3× faster.
 - `blackdetect` is 3.2× faster and `motion` 1.6× faster. Both now read a frame's true luma instead of a gray recomputed through RGB, so `motion` values run about 8% lower and `blackdetect` can shift a few frames at the end of a fade.

## Fixes
 - FCP7 XML import plays each audio track from the right stream of a multi-stream source, instead of the first stream for all of them, and keeps a mono source mono.
 - FCP7 XML import skips disabled clips, no longer turns Premiere's untouched opacity into an effect on every clip, and warns about the titles and nested sequences it leaves out. It is no longer experimental.
 - FCP7 XML export writes Premiere's exact source times (`pproTicksIn`/`pproTicksOut`), and import reads them, so clips at fractional speeds keep their in points. Reversed and freeze-frame clips are reported instead of silently playing forward.
 - A transition out of a clip that ends on its file's last frame holds that frame instead of blending with the background.
 - Rendering and transcribing follow an AAC stream that changes its channel layout part way through.
 - Interlaced video is deinterlaced when rendered. VideoToolbox's H.264 and HEVC encoders can't code fields and no encoder was asked to, so interlaced input came out combed, and partial-lossless mixed field-coded and progressive pictures in one stream.
 - Interlaced video, such as DV and interlaced H.264, no longer fails with "Failed to scale frame" when its pixel format is converted.
 - An `add:` overlay of another video no longer changes the output's color tags from one run to the next; they come from the base layer.
 - MPEG-TS sources no longer freeze, with silent audio, for their first 1.4 seconds and lose as much at the end. Source times count from the file's start, as in ffmpeg, which also drops the silence an MP3's encoder delay added at the end.
 - Subtitle matching (`--edit subtitle`, `word`) reads `\{` and `\}` as literal braces, as libass draws them.
 - `-c:v h264_videotoolbox` no longer fails with "Could not write packet" when cutting an H.264 source.
 - Partial-lossless rendering no longer drops the first frame of a video that starts just after its audio, and no longer corrupts a copied GOP whose keyframe is between 256 and 511 bytes, which lost frames up to the next keyframe.
 - FFmpeg 9.0.2 is patched with 16 upstream crash fixes in the H.264 and AAC decoders, the MOV, Matroska and CAF demuxers, the MOV and Ogg muxers, and the VideoToolbox encoders.
 - `whisper :mic` on macOS no longer loses audio when reading stalls, as while the model loads. A gap that does occur is filled with silence and reported, so timestamps stay aligned.

# Misc.
 - A mistyped edit method, keyword, or encoder gets a suggestion: `--edit audo`, `audio:thresh=4%`, `-c:a acc`. A keyword with no near match lists the ones the method takes.
 - The macOS Apple Silicon binary is 4.6 MB smaller, and another 640 KB smaller from compiling each loop over a clip's actions once.
 - An unknown `--transition` kind gets a suggestion.
 - Upgrade SVT-AV1 to 4.3.0, HarfBuzz to 15.1.0, zlib to 1.4 and FriBidi to 1.0.18.
