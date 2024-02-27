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
Evaluates a palet expression that returns a bool-array?. The array is then used for
editing.

Editing Methods:
 - audio  ; Audio silence/loudness detection
    - threshold threshold? : 4%
    - stream (or/c nat? 'all) : 'all
    - mincut nat? : 6
    - minclip nat? : 3

 ; mincut is more significant, there it has a larger default value.
 ; minclip gets applied first, then mincut

 - motion  ; Motion detection specialized for noisy real-life videos
    - threshold threshold? : 2%
    - stream nat? : 0
    - blur nat? : 9
    - width nat1? : 400

 - subtitle  ; Detect when subtitle matches pattern as a RegEx string.
    - pattern string?
    - stream nat? : 0
    - ignore-case bool? : #f
    - max-count (or/c nat? void?) : (void)

 - none   ; Do not modify the media in anyway; mark all sections as "loud" (1).
 - all/e  ; Cut out everything out; mark all sections as "silent" (0).


Command-line Examples:
  --edit audio
  --edit audio:threshold=4%
  --edit audio:threshold=0.03
  --edit audio:stream=1
  --edit (or audio:4%,stream=0 audio:8%,stream=1) ; `threshold` is first
  --edit motion
  --edit motion:threshold=2%,blur=3
  --edit (or audio:4% motion:2%,blur=3)
  --edit none
  --edit all/e
""".strip(),
        "--export": """
This option controls how timelines are exported.

Export Methods:
 - default    ; Export as a regular media file

 - premiere   ; Export as an XML timeline file for Adobe Premiere Pro
    - name string? : "Auto-Editor Media Group"

 - resolve    ; Export as an XML timeline file for DaVinci Resolve
    - name string? : "Auto-Editor Media Group"

 - final-cut-pro  ; Export as an XML timeline file for Final Cut Pro
    - name string? : "Auto-Editor Media Group"

 - shotcut    ; Export as an XML timeline file for Shotcut

 - json       ; Export as an auto-editor JSON timeline file
    - api string? : "3"

 - timeline   ; Print the auto-editor timeline to stdout
    - api string? : "3"

 - audio      ; Export as a WAV audio file

 - clip-sequence  ; Export as multiple numbered media files

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

When working with media files, resolution will be based on the first input with a
fallback value of 1920x1080
""".strip(),
        "--frame-rate": """
Set the timeline's timebase and the output media's frame rate.

When working with media files, frame-rate will be the first input's frame rate
with a fallback value of 30

The format must be a string in the form:
 - frame_rate_num/frame_rate_den
 - an integer
 - an floating point number
 - a valid frame rate label

The following labels are recognized:
 - ntsc -> 30000/1001
 - ntsc_film -> 24000/1001
 - pal -> 25
 - film -> 24
""".strip(),
        "--temp-dir": """
If not set, tempdir will be set with Python's tempfile module
The directory doesn't have to exist beforehand, however, the root path must be valid.
Beware that the temp directory can get quite big.
""".strip(),
        "--ffmpeg-location": "This takes precedence over `--my-ffmpeg`.",
        "--my-ffmpeg": "This is equivalent to `--ffmpeg-location ffmpeg`.",
        "--audio-bitrate": """
`--audio-bitrate` sets the target bitrate for the audio encoder.
The value accepts a natural number and the units: ``, `k`, `K`, and `M`.
The special value `unset` may also be used, and means: Don't pass any value to ffmpeg, let it choose a default bitrate.
""".strip(),
        "--video-bitrate": """
`--video-bitrate` sets the target bitrate for the video encoder. It accepts the same format as `--audio-bitrate` and the special `unset` value is allowed.
""".strip(),
        "--margin": """
Default value: 0.2s,0.2s

`--margin` takes either one number of two numbers with a `,` in-between.
The numbers may be written in the 'time' format. Here is a quick recap:

  frames / timebase : `` (no units)
  seconds           : `s` `sec` `secs` `second` `seconds`
  minutes           : `min` `mins` `minute` `minutes`
  hours             : `hour`

  seconds, minutes  :    MM:SS.SS
  hours, mins, secs : HH:MM:SS.SS


Setting margin examples:
 - `--margin 6`
 - `--margin 4,10`
 - `--margin 0.3s,0.5s`
 - `--margin 1:12.5` ; 1 minute, 12.5 seconds

Behind the scenes, margin is a function that operates on boolean arrays
(where 1 represents "loud" and 0 represents "silence")

Here is a list of examples on how margin mutates boolean arrays

(margin 0 0 (bool-array 0 0 0 1 0 0 0))
> (array 'bool 0 0 0 1 0 0 0)

(margin 1 0 (bool-array 0 0 0 1 0 0 0))
> (array 'bool 0 0 1 1 0 0 0)

(margin 1 1 (bool-array 0 0 0 1 0 0 0))
> (array 'bool 0 0 1 1 1 0 0)

(margin 1 2 (bool-array 0 0 1 1 0 0 0 0 1 0))
> (array 'bool 0 1 1 1 1 1 0 1 1 1)

(margin -2 2 (bool-array 0 0 1 1 0 0 0))
> (array 'bool 0 0 0 0 1 1 0)
""".strip(),
        "--audio-normalize": """
Apply audio normalization after cutting.

Normalization Methods:
 - ebu  ; EBU R128 (double pass) loudness normalization
   ; Integrated loudness target
   - i (and/c (or/c int? float?) (between/c -70 -5)) : -24.0
   ; Loudness range target
   - lra (and/c (or/c int? float?) (between/c 1 50)) : 7.0
   ; Set maximum true peak
   - tp (and/c (or/c int? float?) (between/c -9 0)) : -2.0
   ; Set offset gain. Gain is applied before the true-peak limiter
   - gain (and/c (or/c int? float?) (between/c -99 99)) : 0.0

 - peak
  ; Loudness target
  - t (and/c (or/c int? float?) (between/c -99 0)) : -8.0

If `#f` is chosen, no audio-normalization will be applied.

Note that this option is a thin layer over the audio filter `loudnorm` for `ebu` and `astats`/`volume` for `peak` respectively.
Check out its docs for more info: https://ffmpeg.org/ffmpeg-filters.html#loudnorm

Examples:
--audio-normalize #f
--audio-normalize ebu:i=-5,lra=40,gain=5,tp=-1
""".strip(),
        "--silent-speed": "99999 is the 'cut speed' and values over that or <=0 are considered 'cut speeds' as well",
        "--video-speed": "99999 is the 'cut speed' and values over that or <=0 are considered 'cut speeds' as well",
    },
    "info": {"_": "Retrieve information and properties about media files"},
    "levels": {"_": "Display loudness over time"},
    "subdump": {
        "_": "Dump text-based subtitles to stdout with formatting stripped out"
    },
    "desc": {"_": "Display a media's description metadata"},
    "test": {"_": "Self-Hosted Unit and End-to-End tests"},
}
