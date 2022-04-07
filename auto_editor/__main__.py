#!/usr/bin/env python3

# Internal Libraries
import os
import sys
import tempfile

# Typing
from typing import List

# Included Libraries
import auto_editor
import auto_editor.vanparse as vanparse
import auto_editor.utils.func as usefulfunctions

from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.log import Log, Timer
from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.edit import edit_media

def main_options(parser):
    from auto_editor.objects import (TextObject, RectangleObject, EllipseObject,
        ImageObject)
    from auto_editor.utils.types import (file_type, float_type, sample_rate_type,
        frame_type, range_type, speed_range_type, margin_type, color_type)

    parser.add_text('Object Options')
    parser.add_argument('--add-text', nargs='*', dataclass=TextObject,
        help='Add a text object to the timeline.')
    parser.add_argument('--add-rectangle', nargs='*', dataclass=RectangleObject,
        help='Add a rectangle object to the timeline.')
    parser.add_argument('--add-ellipse', nargs='*', dataclass=EllipseObject,
        help='Add an ellipse object to the timeline.',
        manual='The x and y coordinates specify a bounding box where the ellipse is '
            'drawn.')
    parser.add_argument('--add-image', nargs='*', dataclass=ImageObject,
        help='Add an image object onto the timeline.',
        manual='Opacity is how transparent or solid the image is. A transparency of '
            '1 or 100% is completely solid. A transparency of 0 or 0% is completely '
            'transparent.\n'
            'The anchor point tells how the image is placed relative to its x y coordinates.')

    parser.add_text('URL Download Options')
    parser.add_argument('--yt-dlp-location', default='yt-dlp',
        help='Set a custom path to yt-dlp.')
    parser.add_argument('--download-format', default=None,
        help='Set the yt-dlp download format. (--format, -f)')
    parser.add_argument('--output-format', default=None,
        help='Set the yt-dlp output file template. (--output, -o)')
    parser.add_argument('--yt-dlp-extras', default=None,
        help='Add extra options for yt-dlp. Must be in quotes')

    parser.add_text('Exporting as Media Options')
    parser.add_argument('--video-codec', '-vcodec', '-c:v', default='auto',
        help='Set the video codec for the output media file.')
    parser.add_argument('--audio-codec', '-acodec', '-c:a', default='auto',
        help='Set the audio codec for the output media file.')
    parser.add_argument('--video-bitrate', '-b:v', default='10m',
        help='Set the number of bits per second for video.')
    parser.add_argument('--audio-bitrate', '-b:a', default='unset',
        help='Set the number of bits per second for audio.')
    parser.add_argument('--sample-rate', '-ar', type=sample_rate_type,
        help='Set the sample rate of the input and output videos.')
    parser.add_argument('--video-quality-scale', '-qscale:v', '-q:v', default='unset',
        range='1 to 31',
        help='Set a value to the ffmpeg option -qscale:v')
    parser.add_argument('--scale', type=float_type, default=1,
        help='Scale the output video by a certain factor.')
    parser.add_argument('--extras',
        help='Add extra options for ffmpeg for video rendering. Must be in quotes.')

    parser.add_text('Miscellaneous Options')
    parser.add_argument('--background', type=color_type, default='#000',
        help='Set the color of the background that is visible when the video is moved.')
    parser.add_argument('--combine-files', action='store_true',
        help='Combine all input files into one before editing.')
    parser.add_argument('--progress', default='modern',
        choices=['modern', 'classic', 'ascii', 'machine', 'none'],
        help='Set what type of progress bar to use.')

    parser.add_text('Manual Editing Options')
    parser.add_argument('--cut-out', type=range_type, nargs='*',
        help='The range of media that will be removed completely, regardless of the '
            'value of silent speed.')
    parser.add_argument('--add-in', type=range_type, nargs='*',
        help='The range of media that will be added in, opposite of --cut-out')
    parser.add_blank()
    parser.add_argument('--mark-as-loud', type=range_type, nargs='*',
        help='The range that will be marked as "loud".')
    parser.add_argument('--mark-as-silent', type=range_type, nargs='*',
        help='The range that will be marked as "silent".')
    parser.add_argument('--set-speed-for-range', type=speed_range_type, nargs='*',
        help='Set an arbitrary speed for a given range.',
        manual='This option takes 3 arguments delimited with commas and they are as follows:\n'
            ' Speed\n'
            ' - How fast the media plays. Speeds 0 or below and 99999 or above will be cut completely.\n'
            ' Start\n'
            ' - When the speed first gets applied. The default unit is in frames, but second units can also be used.\n'
            ' End\n'
            ' - When the speed stops being applied. It can use both frame and second units.\n')

    parser.add_text('Select Editing Source Options')
    parser.add_argument('--edit-based-on', '--edit', default='audio',
        help='Decide which method to use when making edits.',
        manual='''Editing Methods:
 - audio:
    General audio detection.
 - motion:
    Motion detection specialized for real life noisy video.
 - pixeldiff:
    Detect when a certain amount of pixels have changed between frames.
 - none:
    Do not modify the media in anyway. (Mark all sections as "loud")
 - all:
    Cut out everything out. (Mark all sections as "silent")

Editing Methods Attributes:
 - audio: 2
    - stream: 0 : Union[int, 'all']
    - threshold: args.silent_threshold : float_type
 - motion: 3
    - threshold: 2% : float_type
    - blur: 9 : int
    - width: 400 : int
 - pixeldiff: 2
    - threshold: 1 : int
 - none: 0
 - all: 0

Logical Operators:
 - and
 - or
 - xor

Examples:
  --edit audio
  --edit audio:stream=1
  --edit audio:threshold=4%
  --edit audio:threshold=0.03
  --edit motion
  --edit motion:threshold=2%,blur=3
  --edit audio:threshold=4% or motion:threshold=2%,blur=3
  --edit none
  --edit all''')

    parser.add_argument('--keep-tracks-seperate', action='store_true',
        help="Don't combine audio tracks when exporting.")
    parser.add_argument('--export', default='default',
        choices=['default', 'premiere', 'final-cut-pro', 'shotcut', 'json', 'audio', 'clip-sequence'],
        help='Choice the export mode.',
        manual='Instead of exporting a video, export as one of these options instead.\n\n'
            'default       : Export as usual\n'
            'premiere      : Export as an XML timeline file for Adobe Premiere Pro\n'
            'final-cut-pro : Export as an XML timeline file for Final Cut Pro\n'
            'shotcut       : Export as an XML timeline file for Shotcut\n'
            'json          : Export as an auto-editor JSON timeline file\n'
            'audio         : Export as a WAV audio file\n'
            'clip-sequence : Export as multiple numbered media files'
    )
    parser.add_text('Utility Options')
    parser.add_argument('--no-open', action='store_true',
        help='Do not open the file after editing is done.')
    parser.add_argument('--temp-dir', default=None,
        help='Set where the temporary directory is located.',
        manual='If not set, tempdir will be set with Python\'s tempfile module\n'
            'The directory doesn\'t have to exist beforehand, however, the root path '
            'must be valid. For Windows users, this file will be in the C drive.\n'
            'The temp file can get quite big if you\'re generating a huge video, so '
            'make sure your location has enough space.')
    parser.add_argument('--ffmpeg-location', default=None,
        help='Set a custom path to the ffmpeg location.',
        manual='This takes precedence over `--my-ffmpeg`.')
    parser.add_argument('--my-ffmpeg', action='store_true',
        help='Use the ffmpeg on your PATH instead of the one packaged.',
        manual='This is equivalent to `--ffmpeg-location ffmpeg`.')

    parser.add_text('Display Options')
    parser.add_argument('--version', action='store_true',
        help="Display the program's version and halt.")
    parser.add_argument('--debug', action='store_true',
        help='Show debugging messages and values.')
    parser.add_argument('--show-ffmpeg-debug', action='store_true',
        help='Show ffmpeg progress and output.')
    parser.add_argument('--quiet', '-q', action='store_true',
        help='Display less output.')
    parser.add_argument('--preview', action='store_true',
        help='Show stats on how the input will be cut and halt.')
    parser.add_argument('--timeline', action='store_true',
        help='Show auto-editor JSON timeline file and halt.')
    parser.add_argument('--api', default='0.2.0',
        help='Set what version of the JSON timeline to output.')

    parser.add_text('Editing Options')

    parser.add_argument('--silent-threshold', '-t', type=float_type, default=0.04,
        range='0 to 1',
        help='Set the volume that frames audio needs to surpass to be "loud".',
        manual='Silent threshold is a percentage where 0% represents absolute silence and '
            '100% represents the highest volume in the media file.\n'
            'Setting the threshold to `0%` will cut only out areas where area is '
            'absolutely silence while a value of 4% will cut ')
    parser.add_argument('--frame-margin', '--margin', '-m', type=margin_type, default='6',
        range='-Infinity to Infinity',
        help='Set how many "silent" frames on either side on the "loud" sections to be '
            'included.',
        manual='Margin is measured in frames, however, seconds can be used. e.g. `0.3secs`\n'
            'The starting and ending margins can be set separately with the use of '
            'a comma. e.g. `2sec,3sec` `7,10` `-1,6`')
    parser.add_argument('--silent-speed', '-s', type=float_type, default=99999,
        range='Any number. Values <= 0 or >= 99999 will be cut out.',
        help='Set the speed that "silent" sections should be played at.')
    parser.add_argument('--video-speed', '--sounded-speed', '-v', type=float_type,
        default=1,
        range='Any number. Values <= 0 or >= 99999 will be cut out.',
        help='Set the speed that "loud" sections should be played at.')
    parser.add_argument('--min-clip-length', '-mclip', type=frame_type, default=3,
        range='0 to Infinity',
        help='Set the minimum length a clip can be. If a clip is too short, cut it.')
    parser.add_argument('--min-cut-length', '-mcut', type=frame_type, default=6,
        range='0 to Infinity',
        help="Set the minimum length a cut can be. If a cut is too short, don't cut.")

    parser.add_blank()
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')

    parser.add_argument('--output-file', '--output', '-o', nargs='*',
        help='Set the name(s) of the new output.')
    parser.add_blank()
    parser.add_required('input', nargs='*',
        help='File(s) or URL(s) that will be edited.')

    return parser


def main():
    desc = ('Auto-Editor is an automatic video/audio creator and editor. '
        'By default, it will detect silence and create a new video with those '
        'sections cut out. By changing some of the options, you can export to a '
        'traditional editor like Premiere Pro and adjust the edits there, adjust '
        'the pacing of the cuts, and change the method of editing like using audio '
        'loudness and video motion to judge making cuts.\nRun:\n    auto-editor '
        '--help\n\nTo get the list of options.\n')

    parser = vanparse.ArgumentParser('Auto-Editor', auto_editor.version, description=desc)

    subcommands = ['test', 'info', 'levels', 'grep', 'subdump', 'desc']

    if len(sys.argv) > 1 and sys.argv[1] in subcommands:
        obj = __import__(f'auto_editor.subcommands.{sys.argv[1]}', fromlist=['subcommands'])
        obj.main(sys.argv[2:])
        sys.exit()
    else:
        parser = main_options(parser)

        # Preserve backwards compatibility

        sys_a = sys.argv[1:]

        def c(sys_a, options, new):
            for option in options:
                if option in sys_a:
                    pos = sys_a.index(option)
                    sys_a[pos:pos+1] = new
            return sys_a

        sys_a = c(sys_a,
            ['--export_to_premiere', '--export-to-premiere', '-exp'],
            ['--export', 'premiere']
        )
        sys_a = c(sys_a,
            ['--export_to_final_cut_pro', '--export-to-final-cut-pro', '-exf'],
            ['--export', 'final-cut-pro']
        )
        sys_a = c(sys_a,
            ['--export_to_shotcut', '--export-to-shotcut', '-exs'],
            ['--export', 'shotcut']
        )
        sys_a = c(sys_a,
            ['--export_as_json', '--export-as-json'],
            ['--export', 'json']
        )
        sys_a = c(sys_a,
            ['--export_as_clip_sequence', '--export-as-clip-sequence', '-excs'],
            ['--export', 'clip-sequence']
        )

        try:
            args = parser.parse_args(sys_a)
        except vanparse.ParserError as e:
            Log().error(str(e))

    timer = Timer(args.quiet)

    exporting_to_editor = args.export in ('premiere', 'final-cut-pro', 'shotcut')
    making_data_file = exporting_to_editor or args.export == 'json'

    is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, args.show_ffmpeg_debug)

    if args.debug and args.input == []:
        import platform

        print(f'Python Version: {platform.python_version()} {is64bit}')
        print(f'Platform: {platform.system()} {platform.release()} {platform.machine().lower()}')
        print(f'FFmpeg Version: {ffmpeg.version}')
        print(f'FFmpeg Path: {ffmpeg.path}')
        print(f'Auto-Editor Version: {auto_editor.version}')
        sys.exit()

    if is64bit == '32-bit':
        Log().warning('You have the 32-bit version of Python, which may lead to '
            'memory crashes.')

    if args.version:
        print(f'Auto-Editor version {auto_editor.version}')
        sys.exit()

    if args.temp_dir is None:
        TEMP = tempfile.mkdtemp()
    else:
        TEMP = args.temp_dir
        if os.path.isfile(TEMP):
            Log().error('Temp directory cannot be an already existing file.')
        if os.path.isdir(TEMP):
            if len(os.listdir(TEMP)) != 0:
                Log().error('Temp directory should be empty!')
        else:
            os.mkdir(TEMP)

    if args.timeline:
        args.quiet = True

    log = Log(args.debug, args.quiet, temp=TEMP)
    log.debug(f'Temp Directory: {TEMP}')

    if args.input == []:
        log.error('You need to give auto-editor an input file or folder so it can '
            'do the work for you.')

    def write_starting_message(export: str) -> str:
        if export == 'premiere':
            return 'Exporting to Adobe Premiere Pro XML file'
        if export == 'final-cut-pro':
            return 'Exporting to Final Cut Pro XML file'
        if export == 'shotcut':
            return 'Exporting to Shotcut XML Timeline file'
        if export == 'audio':
            return 'Exporting as audio'
        return 'Starting'

    if not args.preview and not args.timeline:
        log.conwrite(write_starting_message(args.export))

    if args.preview or args.export not in ('audio', 'default'):
        args.no_open = True

    if args.silent_speed <= 0 or args.silent_speed > 99999:
        args.silent_speed = 99999

    if args.video_speed <= 0 or args.video_speed > 99999:
        args.video_speed = 99999

    if args.output_file is None:
        args.output_file = []

    from auto_editor.validate_input import valid_input
    input_list = valid_input(args.input, ffmpeg, args, log)

    if args.combine_files:
        if exporting_to_editor:
            temp_file = 'combined.mp4'
        else:
            temp_file = os.path.join(TEMP, 'combined.mp4')

        cmd = []
        for fileref in input_list:
            cmd.extend(['-i', fileref])
        cmd.extend([
            '-filter_complex', f'[0:v]concat=n={len(input_list)}:v=1:a=1',
            '-codec:v', 'h264',
            '-pix_fmt', 'yuv420p',
            '-strict', '-2',
            temp_file,
        ])

        ffmpeg.run(cmd)
        del cmd
        input_list = [temp_file]

    def main_loop(input_list: List[str], ffmpeg: FFmpeg, args, log: Log) -> None:
        num_cuts = 0

        progress = ProgressBar(args.progress)

        for i, input_path in enumerate(input_list):
            inp = FileInfo(input_path, ffmpeg)

            if len(input_list) > 1:
                log.conwrite(f'Working on {inp.basename}')

            cuts, output_path = edit_media(i, inp, ffmpeg, args, progress, TEMP, log)
            num_cuts += cuts

        if not args.preview and not args.timeline and not making_data_file:
            timer.stop()

        if not args.preview and not args.timeline and making_data_file:
            # Assume making each cut takes about 30 seconds.
            time_save = usefulfunctions.human_readable_time(num_cuts * 30)
            s = 's' if num_cuts != 1 else ''

            log.print(
                f'Auto-Editor made {num_cuts} cut{s}, which would have taken '
                f'about {time_save} if edited manually.'
            )

        if not args.no_open:
            usefulfunctions.open_with_system_default(output_path, log)

    try:
        main_loop(input_list, ffmpeg, args, log)
    except KeyboardInterrupt:
        log.error('Keyboard Interrupt')
    log.cleanup()

if __name__ == '__main__':
    main()
