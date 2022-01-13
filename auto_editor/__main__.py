#!/usr/bin/env python3
'''__main__.py'''

# Internal Libraries
import os
import sys
import tempfile

# Included Libraries
import auto_editor
import auto_editor.vanparse as vanparse
import auto_editor.utils.func as usefulfunctions

from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.func import set_output_name
from auto_editor.utils.log import Log, Timer
from auto_editor.ffwrapper import FFmpeg
from auto_editor.edit import edit_media

def main_options(parser):
    from auto_editor.utils.types import (file_type, float_type, sample_rate_type,
        frame_type, range_type, speed_range_type, block_type, margin_type)

    parser.add_text('Progress Options')
    parser.add_argument('--machine_readable_progress', action='store_true',
        help='Set progress bar that is easier to parse.')
    parser.add_argument('--no_progress', action='store_true',
        help='Do not display any progress at all.')

    parser.add_text('Object Options')

    basic_obj_keywords = [
        {'start': (int, ''),},
        {'dur': (int, ''),},
        {'x1': (int, ''),},
        {'y1': (int, ''),},
        {'x2': (int, ''),},
        {'y2': (int, ''),},
        {'fill': (str, '#000'),},
        {'width': (int, 0),},
        {'outline': (str,'blue'),},
    ]

    rect = basic_obj_keywords[:]
    rect.append({'type': 'rectangle'})

    ellipse = basic_obj_keywords[:]
    ellipse.append({'type': 'ellipse'})

    parser.add_argument('--add_text', nargs='*', type=dict,
        keywords=[
            {'start': (int, ''),},
            {'dur': (int, ''),},
            {'content': (str, ''),},
            {'x': (int, 'centerX'),},
            {'y': (int, 'centerY'),},
            {'size': (int, 30),},
            {'font': (str, 'default'),},
            {'align': (str, 'left'),},
            {'fill': (str, '#FFF'),},
            {'type': 'text'},
        ],
        help='Add a text object to the timeline.'
    )
    parser.add_argument('--add_rectangle', nargs='*', type=dict,
        keywords=rect,
        help='Add a rectangle object to the timeline.')
    parser.add_argument('--add_ellipse', nargs='*', type=dict,
        keywords=ellipse,
        help='Add an ellipse object to the timeline.',
        manual='The x and y coordinates specify a bounding box where the ellipse is '\
            'drawn.')

    parser.add_argument('--add_image', nargs='*', type=dict,
        keywords=[
            {'start': (int, ''),},
            {'dur': (int, ''),},
            {'source': (str, ''),},
            {'x': (int, 'centerX'),},
            {'y': (int, 'centerY'),},
            {'opacity': (float_type, 1),},
            {'anchor': (str, 'ce'),},
            {'type': 'image'},
        ],
        help='Add an image object onto the timeline.',
        manual='Opacity is how transparent or solid the image is. A transparency of '\
            '1 or 100% is completely solid. A transparency of 0 or 0% is completely '\
            'transparent.\n' \
            'The anchor point tells how the image is placed relative to its x y coordinates.')

    parser.add_text('URL Download Options')
    parser.add_argument('--download_dir', type=str, default=None,
        help='The directory where the downloaded file is placed.')
    parser.add_argument('--limit_rate', '-rate', default='3m',
        help='The maximum download rate in bytes per second (50k, 4.2m)')
    parser.add_argument('--id', type=str, default=None,
        help='Manually set the YouTube ID the video belongs to.')
    parser.add_argument('--block', type=block_type,
        help='Mark all sponsors sections as silent.',
        manual='Only for YouTube URLs. This uses the SponsorBlock API.\n'
            'Choices can include: sponsor intro outro selfpromo interaction music_offtopic')

    parser.add_argument('--download_archive', type=file_type, default=None,
        help='Download only videos not listed in archive file. Record the IDs of'
             ' all downloads.')
    parser.add_argument('--cookies', type=file_type, default=None,
        help='The file to read cookies from and dump the cookie jar in.')
    parser.add_argument('--check_certificate', action='store_true',
        help='Check the website certificate before downloading.')

    parser.add_text('Motion Detection Options')
    parser.add_argument('--motion_threshold', type=float_type, default=0.02,
        range='0 to 1',
        help='How much motion is required to be considered "moving"')
    parser.add_blank()
    parser.add_argument('--md_dilates', type=int, default=2, range='0 to 5',
        help='Set how many times a frame is dilated before being compared.')
    parser.add_argument('--md_width', type=int, default=400, range='1 to Infinity',
        help="Scale the frame to this width before being compared.")
    parser.add_argument('--md_blur', type=int, default=21, range='0 to Infinity',
        help='Set the strength of the blur applied to a frame before being compared.')

    parser.add_text('Exporting as Media Options')
    parser.add_argument('--video_bitrate', '-b:v', default='10m',
        help='Set the number of bits per second for video.')
    parser.add_argument('--audio_bitrate', '-b:a', default='unset',
        help='Set the number of bits per second for audio.')
    parser.add_argument('--sample_rate', '-ar', type=sample_rate_type,
        help='Set the sample rate of the input and output videos.')
    parser.add_argument('--video_codec', '-vcodec', '-c:v', default='auto',
        help='Set the video codec for the output media file.')
    parser.add_argument('--audio_codec', '-acodec', '-c:a', default='auto',
        help='Set the audio codec for the output media file.')
    parser.add_argument('--preset', '-preset', default='unset',
        choices=['ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium',
            'slow', 'slower', 'veryslow', 'unset'],
        help='Set the preset for ffmpeg to help save file size or increase quality.')
    parser.add_argument('--tune', '-tune', default='unset',
        choices=['film', 'animation', 'grain', 'stillimage', 'fastdecode',
            'zerolatency', 'none', 'unset'],
        help='Set the tune for ffmpeg to compress video better in certain circumstances.')
    parser.add_argument('--constant_rate_factor', '-crf', default='unset', range='0 to 51',
        help='Set the quality for video using the crf method.')
    parser.add_argument('--video_quality_scale', '-qscale:v', '-q:v', default='unset',
        range='1 to 31',
        help='Set a value to the ffmpeg option -qscale:v')
    parser.add_argument('--scale', type=float_type, default=1,
        help='Scale the output media file by a certain factor.')

    parser.add_text('Miscellaneous Options')
    parser.add_argument('--background', type=str, default='#000',
        help='Set the color of the background that is visible when the video is moved.')
    parser.add_argument('--combine_files', action='store_true',
        help='Combine all input files into one before editing.')

    parser.add_text('Manual Editing Options')
    parser.add_argument('--cut_out', type=range_type, nargs='*',
        help='The range of media that will be removed completely, regardless of the '
            'value of silent speed.')
    parser.add_argument('--add_in', type=range_type, nargs='*',
        help='The range of media that will be added in, opposite of --cut_out')
    parser.add_blank()
    parser.add_argument('--mark_as_loud', type=range_type, nargs='*',
        help='The range that will be marked as "loud".')
    parser.add_argument('--mark_as_silent', type=range_type, nargs='*',
        help='The range that will be marked as "silent".')
    parser.add_argument('--set_speed_for_range', type=speed_range_type, nargs='*',
        help='Set an arbitrary speed for a given range.',
        manual='This option takes 3 arguments delimited with commas and they are as follows:\n'
            ' Speed\n'
            ' - How fast the media plays. Speeds 0 or below and 99999 or above will be cut completely.\n'
            ' Start\n'
            ' - When the speed first gets applied. The default unit is in frames, but second units can also be used.\n'
            ' End\n'
            ' - When the speed stops being applied. It can use both frame and second units.\n')

    parser.add_text('Select Editing Source Options')
    parser.add_argument('--edit_based_on', '--edit', default='audio',
        choices=['audio', 'motion', 'none', 'all', 'not_audio', 'not_motion',
            'audio_or_motion', 'audio_and_motion', 'audio_xor_motion',
            'audio_and_not_motion', 'not_audio_and_motion', 'not_audio_and_not_motion'],
        help='Decide which method to use when making edits.')
    parser.add_argument('--keep_tracks_seperate', action='store_true',
        help="Don't combine audio tracks when exporting.")
    parser.add_blank()
    parser.add_argument('--cut_by_this_audio', '-ca', type=file_type,
        help="Base cuts by this audio file instead of the video's audio.")
    parser.add_argument('--cut_by_this_track', '-ct', type=int, default=0,
        range='0 to the number of audio tracks minus one',
        help='Base cuts by a different audio track in the video.')
    parser.add_argument('--cut_by_all_tracks', '-cat', action='store_true',
        help='Combine all audio tracks into one before basing cuts.')

    parser.add_text('Export Mode Options')
    parser.add_argument('--export_to_premiere', '-exp', action='store_true',
        help='Export as an XML file for Adobe Premiere Pro instead of making a media file.')
    parser.add_argument('--export_to_final_cut_pro', '-exf', action='store_true',
        help='Export as an XML file for Final Cut Pro instead of making a media file.')
    parser.add_argument('--export_to_shotcut', '-exs', action='store_true',
        help='Export as an XML timeline file for Shotcut instead of making a media file.')
    parser.add_argument('--export_as_json', action='store_true',
        help='Export as a JSON file that can be read by auto-editor later.')
    parser.add_argument('--export_as_audio', '-exa', action='store_true',
        help='Export as a WAV audio file.')
    parser.add_argument('--export_as_clip_sequence', '-excs', action='store_true',
        help='Export as multiple numbered media files.')
    parser.add_argument('--timeline', action='store_true',
        help='Display timeline JSON file and halt.',
        manual='This option is like `--export_as_json` except that it outputs directly '
            'to stdout instead of to a file.')

    parser.add_text('Utility Options')
    parser.add_argument('--no_open', action='store_true',
        help='Do not open the file after editing is done.')
    parser.add_argument('--temp_dir', default=None,
        help='Set where the temporary directory is located.',
        manual='If not set, tempdir will be set with Python\'s tempfile module\n'
            'The directory doesn\'t have to exist beforehand, however, the root path must be valid.'
            'For Windows users, this file will be in the C drive.\n'
            'The temp file can get quite big if you\'re generating a huge video, so '
            'make sure your location has enough space.')
    parser.add_argument('--ffmpeg_location', default=None,
        help='Set a custom path to the ffmpeg location.',
        manual='This takes precedence over `--my_ffmpeg`.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='Use the ffmpeg on your PATH instead of the one packaged.',
        manual='This is equivalent to `--ffmpeg_location ffmpeg`.')

    parser.add_text('Display Options')
    parser.add_argument('--version', action='store_true',
        help="Display the program's version and halt.")
    parser.add_argument('--debug', action='store_true',
        help='Show debugging messages and values.')
    parser.add_argument('--show_ffmpeg_debug', action='store_true',
        help='Show ffmpeg progress and output.')
    parser.add_argument('--quiet', '-q', action='store_true',
        help='Display less output.')
    parser.add_argument('--preview', action='store_true',
        help='Show stats on how the input will be cut and halt.')

    parser.add_text('Editing Options')

    parser.add_argument('--silent_threshold', '-t', type=float_type, default=0.04,
        range='0 to 1',
        help='Set the volume that frames audio needs to surpass to be "loud".',
        manual='Silent threshold is a percentage where 0% represents absolute silence and '
            '100% represents the highest volume in the media file.\n'
            'Setting the threshold to `0%` will cut only out areas where area is '
            'absolutely silence while a value of 4% will cut ')
    parser.add_argument('--frame_margin', '--margin', '-m', type=margin_type, default='6',
        range='0 to Infinity',
        help='Set how many "silent" frames on either side on the "loud" sections to be '
            'included.')
    parser.add_argument('--silent_speed', '-s', type=float_type, default=99999,
        range='Any number. Values <= 0 or >= 99999 will be cut out.',
        help='Set the speed that "silent" sections should be played at.')
    parser.add_argument('--video_speed', '--sounded_speed', '-v', type=float_type,
        default=1,
        range='Any number. Values <= 0 or >= 99999 will be cut out.',
        help='Set the speed that "loud" sections should be played at.')
    parser.add_argument('--min_clip_length', '-mclip', type=frame_type, default=3,
        range='0 to Infinity',
        help='Set the minimum length a clip can be. If a clip is too short, cut it.')
    parser.add_argument('--min_cut_length', '-mcut', type=frame_type, default=6,
        range='0 to Infinity',
        help="Set the minimum length a cut can be. If a cut is too short, don't cut")

    parser.add_blank()
    parser.add_argument('--help', '-h', action='store_true',
        help='Print info about the program or an option and exit.')

    parser.add_argument('--output_file', '--output', '-o', nargs='*',
        help='Set the name(s) of the new output.')
    parser.add_argument('input', nargs='*',
        help='File(s) or URL(s) that will be edited.')

    parser.add_blank()
    parser.add_text('  Have an issue? Make an issue. Visit '
            'https://github.com/wyattblue/auto-editor/issues\n\n  The help option '
            'can also be used on a specific option:\n     auto-editor '
            '--frame_margin --help\n')
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

    subcommands = ['create', 'test', 'info', 'levels', 'grep', 'subdump', 'desc']

    if(len(sys.argv) > 1 and sys.argv[1] in subcommands):
        obj = __import__('auto_editor.subcommands.{}'.format(sys.argv[1]),
            fromlist=['subcommands'])
        obj.main(sys.argv[2:])
        sys.exit()
    else:
        parser = main_options(parser)
        try:
            args = parser.parse_args(sys.argv[1:])
        except vanparse.ParserError as e:
            Log().error(str(e))

    timer = Timer(args.quiet)

    exporting_to_editor = (args.export_to_premiere or args.export_to_final_cut_pro or
        args.export_to_shotcut)
    making_data_file = exporting_to_editor or args.export_as_json

    is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, args.show_ffmpeg_debug)

    if(args.debug and args.input == []):
        import platform

        print('Python Version: {} {}'.format(platform.python_version(), is64bit))
        print('Platform: {} {} {}'.format(platform.system(), platform.release(), platform.machine().lower()))
        print('FFmpeg path: {}'.format(ffmpeg.path))
        print('FFmpeg version: {}'.format(ffmpeg.version))
        print('Auto-Editor version {}'.format(auto_editor.version))
        sys.exit()

    if(is64bit == '32-bit'):
        Log().warning('You have the 32-bit version of Python, which may lead to '
            'memory crashes.')

    if(args.version):
        print('Auto-Editor version {}'.format(auto_editor.version))
        sys.exit()

    if(args.temp_dir is None):
        TEMP = tempfile.mkdtemp()
    else:
        TEMP = args.temp_dir
        if(os.path.isfile(TEMP)):
            Log().error('Temp directory cannot be an already existing file.')
        if(os.path.isdir(TEMP)):
            if(len(os.listdir(TEMP)) != 0):
                Log().error('Temp directory should be empty!')
        else:
            os.mkdir(TEMP)

    if(args.timeline):
        args.quiet = True

    log = Log(args.debug, args.quiet, temp=TEMP)
    log.debug('Temp Directory: {}'.format(TEMP))

    if(args.input == []):
        log.error('You need to give auto-editor an input file or folder so it can '
            'do the work for you.')

    if([args.export_to_premiere, args.export_to_final_cut_pro, args.export_as_audio,
        args.export_to_shotcut, args.export_as_clip_sequence].count(True) > 1):
        log.error('You must choose only one export option.')

    if(args.constant_rate_factor != 'unset'):
        if(int(args.constant_rate_factor) < 0 or int(args.constant_rate_factor) > 51):
            log.error('Constant rate factor (crf) must be between 0-51.')
    if(args.md_width < 1):
        log.error('--md_width cannot be less than 1.')
    if(args.md_dilates < 0):
        log.error('--md_dilates cannot be less than 0')

    def write_starting_message(args):
        if(args.export_to_premiere):
            return 'Exporting to Adobe Premiere Pro XML file.'
        if(args.export_to_final_cut_pro):
            return 'Exporting to Final Cut Pro XML file.'
        if(args.export_to_shotcut):
            return 'Exporting to Shotcut XML Timeline file.'
        if(args.export_as_audio):
            return 'Exporting as audio.'
        return 'Starting.'

    if(not args.preview and not args.timeline):
        log.conwrite(write_starting_message(args))

    if(args.preview or args.timeline or args.export_as_clip_sequence or making_data_file):
        args.no_open = True

    if(args.md_blur < 0):
        args.md_blur = 0

    if(args.silent_speed <= 0 or args.silent_speed > 99999):
        args.silent_speed = 99999

    if(args.video_speed <= 0 or args.video_speed > 99999):
        args.video_speed = 99999

    if(args.output_file is None):
        args.output_file = []

    from auto_editor.validate_input import valid_input
    input_list, segments = valid_input(args.input, ffmpeg, args, log)

    if(len(args.output_file) < len(input_list)):
        for i in range(len(input_list) - len(args.output_file)):
            args.output_file.append(set_output_name(input_list[i], None,
                making_data_file, args))

    if(args.combine_files):
        if(exporting_to_editor):
            temp_file = 'combined.mp4'
        else:
            temp_file = os.path.join(TEMP, 'combined.mp4')

        cmd = []
        for fileref in input_list:
            cmd.extend(['-i', fileref])
        cmd.extend(['-filter_complex', '[0:v]concat=n={}:v=1:a=1'.format(len(input_list)),
            '-codec:v', 'h264', '-pix_fmt', 'yuv420p', '-strict', '-2', temp_file])
        ffmpeg.run(cmd)
        del cmd
        input_list = [temp_file]

    def main_loop(input_list, ffmpeg, args, segments, log):
        num_cuts = 0

        progress = ProgressBar(args.machine_readable_progress, args.no_progress)

        for i, input_path in enumerate(input_list):
            inp = ffmpeg.file_info(input_path)

            if(len(input_list) > 1):
                log.conwrite('Working on {}'.format(inp.basename))

            cuts, output_path = edit_media(i, inp, ffmpeg, args, progress,
                segments[i], exporting_to_editor, making_data_file, TEMP, log)
            num_cuts += cuts

        if(not args.preview and not args.timeline and not making_data_file):
            timer.stop()

        if(not args.preview and not args.timeline and making_data_file):
            # Assume making each cut takes about 30 seconds.
            time_save = usefulfunctions.human_readable_time(num_cuts * 30)
            s = 's' if num_cuts != 1 else ''

            log.print('Auto-Editor made {} cut{}, which would have taken about {} if '
                'edited manually.'.format(num_cuts, s, time_save))

        if(not args.no_open):
            usefulfunctions.open_with_system_default(output_path, log)

    try:
        main_loop(input_list, ffmpeg, args, segments, log)
    except KeyboardInterrupt:
        log.error('Keyboard Interrupt')
    log.cleanup()

if(__name__ == '__main__'):
    main()
