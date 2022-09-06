data = {
    "Auto-Editor": {
        "_": """
Auto-Editor is an automatic video/audio creator and editor. By default, it will detect silence and create a new video with those sections cut out. By changing some of the options, you can export to a traditional editor like Premiere Pro and adjust the edits there, adjust the pacing of the cuts, and change the method of editing like using audio loudness and video motion to judge making cuts.

Run:
    auto-editor --help

To get the list of options.
""".strip(),
        "--set-speed-for-range": """
This option takes 3 arguments delimited with commas and they are as follows:
 - speed:
  - How fast to play the media (number)
Start:
  - The time when speed first gets applied (time)
End:
  - The time when speed stops being applied (time)

example:

--set-range-for-speed 2.5,400,800

will set the speed from 400 ticks to 800 ticks to 2.5x
If timebase is 30, 400 ticks to 800 means 13.33 to 26.66 seconds
""".strip(),
        "--edit-based-on": """
Editing Methods:
 - audio: General audio detection
 - motion: Motion detection specialized for real life noisy video
 - pixeldiff: Detect when a certain amount of pixels have changed between frames
 - random: Set silent/loud randomly based on a random or preset seed
 - none: Do not modify the media in anyway (Mark all sections as "loud")
 - all: Cut out everything out (Mark all sections as "silent")

Attribute Defaults:
 - audio
    - threshold: 4% (number)
    - stream: 0 (natural | "all")
 - motion
    - threshold: 2% (number)
    - stream: 0 (natural | "all")
    - blur: 9 (natural)
    - width: 400 (natural)
 - pixeldiff
    - threshold: 1 (natural)
    - stream: 0 (natural | "all")
 - random
    - threshold: 0.5 (number)
    - seed: RANDOMLY-GENERATED (int)

Operators:
 - and
   - usage: $METHOD and $METHOD
 - or
   - usage: $METHOD or $METHOD
 - xor
   - usage: $METHOD xor $METHOD
 - not
   - usage: not $METHOD
Examples:
  --edit audio
  --edit audio:stream=1
  --edit audio:threshold=4%
  --edit audio:threshold=0.03
  --edit motion
  --edit motion:threshold=2%,blur=3
  --edit audio:threshold=4% or motion:threshold=2%,blur=3
  --edit none
  --edit all
""".strip(),
        "--export": """
Instead of exporting a video, export as one of these options instead.

default       : Export as usual
premiere      : Export as an XML timeline file for Adobe Premiere Pro
final-cut-pro : Export as an XML timeline file for Final Cut Pro
shotcut       : Export as an XML timeline file for Shotcut
json          : Export as an auto-editor JSON timeline file
audio         : Export as a WAV audio file
clip-sequence : Export as multiple numbered media files
""".strip(),
        "--player": """
This option uses shell-like syntax to support using a specific player:

  auto-editor in.mp4 --player mpv

Args for the player program can be added as well:

  auto-editor in.mp4 --player 'mpv --keep-open'

Absolute or relative paths can also be used in the event the player's
executable can not be resolved:

  auto-editor in.mp4 --player '/path/to/mpv'
  auto-editor in.mp4 --player './my-relative-path/mpv'

If --player is not set, auto-editor will use the system default.
If --no-open is used, --player will always be ignored.

on MacOS, QuickTime can be used as the default player this way:

  auto-editor in.mp4 --player 'open -a "quicktime player"'
""".strip(),
        "--resolution": """
If not set, the first input's resolution is used.
If the input does not have a resolution (audio files) or there is not first input,
the value '1920x1080' will be used.
""".strip(),
        "--frame-rate": """
Set (timeline's) timebase and output frame rate.
It must be a string in the format frame_rate_num/frame_rate_den,
an integer, a floating point number, or a valid frame rate label.

The following labels are recognized:

  ntsc -> 30000/1001
  ntsc_film -> 24000/1001
  pal -> 25
  film -> 24
""".strip(),
        "--temp-dir": """
If not set, tempdir will be set with Python's tempfile module
The directory doesn't have to exist beforehand, however, the root path must be valid.
Beware that the temp directory can get quite big.
""".strip(),
        "--ffmpeg-location": "This takes precedence over `--my-ffmpeg`.",
        "--my-ffmpeg": "This is equivalent to `--ffmpeg-location ffmpeg`.",
        "--silent-threshold": """
Silent threshold is a percentage where 0% represents absolute silence and 100% represents the highest volume in the media file.
Setting the threshold to `0%` will cut only out areas where area is absolutely silence.
""".strip(),
        "--frame-margin": """
Margin is measured in frames if no units are specified. Seconds can be used. e.g. `0.3secs`
The starting and ending margins can be set separately with the use of a comma. e.g. `2sec,3sec` `7,10` `-1,6`
""".strip(),
        "--silent-speed": "99999 is the 'cut speed' and values over that or <=0 are considered 'cut speeds' as well",
        "--video-speed": "99999 is the 'cut speed' and values over that or <=0 are considered 'cut speeds' as well",
        "--min-clip-length": "Range: 0 to Infinity",
        "--min-cut-length": "Range: 0 to Infinity",
    },
    "info": {
        "_": "Retrieve information and properties about media files",
        "--include-vfr": """
A typical output will look like this:

- VFR:0.583394 (3204/2288) min: 41 max: 42 avg: 41

'0.583394' is the ratio of how many VFR frames are there.
'3204' is the number of VFR frames, '2288' is the number of non-VFR frames.
 Adding '3204' and '2288' will result in how many frames the video has in total.
""".strip(),
    },
    "levels": {"_": "Display loudness over time"},
    "subdump": {
        "_": "Dump text-based subtitles to stdout with formatting stripped out"
    },
    "grep": {"_": "Read and match text-based subtitle tracks"},
    "desc": {"_": "Display a media's description metadata"},
    "test": {"_": "Self-Hosted Unit and End-to-End tests"},
}
