# Documentation

Here's the help screen auto-editor prints out.

```terminal
  (input): the path to a file, folder, or url you want edited.
  --help, -h: print this message and exit.
  --frame_margin, -m: set how many "silent" frames of on either side of "loud" sections be included.
  --silent_threshold, -t: set the volume that frames audio needs to surpass to be "loud".
  --video_speed, --sounded_speed, -v: set the speed that "loud" sections should be played at.
  --silent_speed, -s: set the speed that "silent" sections should be played at.
  --output_file, -o: set the name(s) of the new output.
  --no_open: do not open the file after editing is done.
  --min_clip_length, -mclip: set the minimum length a clip can be. If a clip is too short, cut it.
  --min_cut_length, -mcut: set the minimum length a cut can be. If a cut is too short, don't cut
  --combine_files: combine all input files into one before editing.
  --preview: show stats on how the input will be cut.
  --cut_by_this_audio, -ca: base cuts by this audio file instead of the video's audio.
  --cut_by_this_track, -ct: base cuts by a different audio track in the video.
  --cut_by_all_tracks, -cat: combine all audio tracks into one before basing cuts.
  --keep_tracks_seperate: don't combine audio tracks when exporting.
  --my_ffmpeg: use your ffmpeg and other binaries instead of the ones packaged.
  --version: show which auto-editor you have.
  --debug, --verbose: show helpful debugging values.
  --export_as_audio, -exa: export as a WAV audio file.
  --export_to_premiere, -exp: export as an XML file for Adobe Premiere Pro instead of outputting a media file.
  --export_to_resolve, -exr: export as an XML file for DaVinci Resolve instead of outputting a media file.
  --video_bitrate, -vb: set the number of bits per second for video.
  --audio_bitrate, -ab: set the number of bits per second for audio.
  --sample_rate, -r: set the sample rate of the input and output videos.
  --video_codec, -vcodec: set the video codec for the output file.
  --preset, -p: set the preset for ffmpeg to help save file size or increase quality.
  --tune, -t: set the tune for ffmpeg to help compress video better.
  --ignore: the range (in seconds) that shouldn't be edited at all. (uses range syntax)
  --cut_out: the range (in seconds) that should be cut out completely, regardless of anything else. (uses range syntax)
```