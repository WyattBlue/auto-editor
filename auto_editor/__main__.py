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
        frame_type, range_type, speed_range_type, block_type)

    parser.add_argument('progressOps', nargs=0, action='grouping')
    parser.add_argument('--machine_readable_progress', action='store_true',
        group='progressOps',
        help='set progress bar that is easier to parse.')
    parser.add_argument('--no_progress', action='store_true',
        group='progressOps',
        help='do not display any progress at all.')

    parser.add_argument('motionOps', nargs=0, action='grouping')
    parser.add_argument('--dilates', type=int, default=2, range='0 to 5',
        group='motionOps',
        help='set how many times a frame is dilated before being compared.')
    parser.add_argument('--width', type=int, default=400, range='1 to Infinity',
        group='motionOps',
        help="scale the frame to this width before being compared.")
    parser.add_argument('--blur', type=int, default=21, range='0 to Infinity',
        group='motionOps',
        help='set the strength of the blur applied to a frame before being compared.')

    parser.add_argument('urlOps', nargs=0, action='grouping')
    parser.add_argument('--output_dir', type=str, group='urlOps',
        default=None,
        help='the directory where the downloaded file is placed.')
    parser.add_argument('--limit_rate', '-rate', default='3m',
        help='maximum download rate in bytes per second (50k, 4.2m)')
    parser.add_argument('--id', type=str, default=None, group='urlOps',
        help='manually set the YouTube ID the video belongs to.')
    parser.add_argument('--block', type=block_type, group='urlOps',
        help='mark all sponsors sections as silent.',
        extra='Only for YouTube urls. This uses the SponsorBlock api.\n'
            'Choices can include: sponsor intro outro selfpromo interaction music_offtopic')
    parser.add_argument('--download_archive', type=file_type, default=None, group='urlOps',
        help='Download only videos not listed in the archive file. Record the IDs of'
             ' all downloaded videos in it')
    parser.add_argument('--cookies', type=file_type, default=None, group='urlOps',
        help='The file to read cookies from and dump the cookie jar in.')
    parser.add_argument('--check_certificate', action='store_true', group='urlOps',
        help='check the website certificate before downloading.')

    parser.add_argument('exportMediaOps', nargs=0, action='grouping')
    parser.add_argument('--video_bitrate', '-b:v', default='5m', group='exportMediaOps',
        help='set the number of bits per second for video.')
    parser.add_argument('--audio_bitrate', '-b:a', default='unset', group='exportMediaOps',
        help='set the number of bits per second for audio.')
    parser.add_argument('--sample_rate', '-ar', type=sample_rate_type,
        group='exportMediaOps',
        help='set the sample rate of the input and output videos.')
    parser.add_argument('--video_codec', '-vcodec', '-c:v', default='auto',
        group='exportMediaOps',
        help='set the video codec for the output media file.')
    parser.add_argument('--audio_codec', '-acodec', '-c:a', group='exportMediaOps',
        help='set the audio codec for the output media file.')
    parser.add_argument('--preset', '-preset', default='unset', group='exportMediaOps',
        choices=['ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium',
            'slow', 'slower', 'veryslow', 'unset'],
        help='set the preset for ffmpeg to help save file size or increase quality.')
    parser.add_argument('--tune', '-tune', default='unset', group='exportMediaOps',
        choices=['film', 'animation', 'grain', 'stillimage', 'fastdecode',
            'zerolatency', 'none', 'unset'],
        help='set the tune for ffmpeg to compress video better in certain circumstances.')
    parser.add_argument('--constant_rate_factor', '-crf', default='unset',
        group='exportMediaOps', range='0 to 51',
        help='set the quality for video using the crf method.')
    parser.add_argument('--video_quality_scale', '-qscale:v', '-q:v', default='unset',
        group='exportMediaOps', range='1 to 31',
        help='set a value to the ffmpeg option -qscale:v')
    parser.add_argument('--has_vfr', default='unset', group='exportMediaOps',
        choices=['unset', 'yes', 'no'],
        help='skip variable frame rate scan, saving time for big video files.')

    parser.add_argument('effectOps', nargs=0, action='grouping')
    parser.add_argument('--zoom', nargs='*', type=dict, group='effectOps',
        help='set when and how a zoom will occur.',
        keywords=[
            {'start': ''}, {'end': ''}, {'zoom': ''}, {'end_zoom': '{zoom}'},
            {'x': 'centerX'}, {'y': 'centerY'}, {'interpolate': 'linear'},
        ])
    parser.add_argument('--rectangle', nargs='*', type=dict, group='effectOps',
        keywords=[
            {'start': ''}, {'end': ''}, {'x1': ''}, {'y1': ''},
            {'x2': ''}, {'y2': ''}, {'fill': '#000'}, {'width': 0}, {'outline': 'blue'}
        ],
        help='overlay a rectangle shape on the video.')
    parser.add_argument('--circle', nargs='*', type=dict, group='effectOps',
        keywords=[
            {'start': ''}, {'end': ''}, {'x1': ''}, {'y1': ''},
            {'x2': ''}, {'y2': ''}, {'fill': '#000'}, {'width': 0}, {'outline': 'blue'}
        ],
        help='overlay a circle shape on the video.',
        extra='\n\nThe x and y coordinates specify a bounding box where the circle is '\
            'drawn.')

    parser.add_argument('--background', type=str, default='#000',
        help='set the color of the background that is visible when the video is moved.')
    parser.add_argument('--scale', type=float_type, default=1,
        help='scale the output media file by a certain factor.')
    parser.add_argument('--combine_files', action='store_true',
        help='combine all input files into one before editing.')

    parser.add_argument('--mark_as_loud', type=range_type, nargs='*',
        help='the range that will be marked as "loud".')
    parser.add_argument('--mark_as_silent', type=range_type, nargs='*',
        help='the range that will be marked as "silent".')
    parser.add_argument('--cut_out', type=range_type, nargs='*',
        help='the range of media that will be removed completely, regardless of the '
            'value of silent speed.')
    parser.add_argument('--add_in', type=range_type, nargs='*',
        help='the range of media that will be added in, opposite of --cut_out')
    parser.add_argument('--set_speed_for_range', type=speed_range_type, nargs='*',
        help='set an arbitrary speed for a given range.',
        extra='The arguments are: speed,start,end')

    parser.add_argument('--motion_threshold', type=float_type, default=0.02,
        range='0 to 1',
        help='how much motion is required to be considered "moving"')
    parser.add_argument('--edit_based_on', '--edit', default='audio',
        choices=['audio', 'motion', 'none', 'all', 'not_audio', 'not_motion',
            'audio_or_motion', 'audio_and_motion', 'audio_xor_motion',
            'audio_and_not_motion', 'not_audio_and_motion', 'not_audio_and_not_motion'],
        help='decide which method to use when making edits.')

    parser.add_argument('--cut_by_this_audio', '-ca', type=file_type,
        help="base cuts by this audio file instead of the video's audio.")
    parser.add_argument('--cut_by_this_track', '-ct', type=int, default=0,
        range='0 to the number of audio tracks minus one',
        help='base cuts by a different audio track in the video.')
    parser.add_argument('--cut_by_all_tracks', '-cat', action='store_true',
        help='combine all audio tracks into one before basing cuts.')
    parser.add_argument('--keep_tracks_seperate', action='store_true',
        help="don't combine audio tracks when exporting.")

    parser.add_argument('--export_as_audio', '-exa', action='store_true',
        help='export as a WAV audio file.')

    parser.add_argument('--export_to_premiere', '-exp', action='store_true',
        help='export as an XML file for Adobe Premiere Pro instead of making a media file.')
    parser.add_argument('--export_to_resolve', '-exr', action='store_true',
        help='export as an XML file for DaVinci Resolve instead of making a media file.')
    parser.add_argument('--export_to_final_cut_pro', '-exf', action='store_true',
        help='export as an XML file for Final Cut Pro instead of making a media file.')
    parser.add_argument('--export_to_shotcut', '-exs', action='store_true',
        help='export as an XML timeline file for Shotcut instead of making a media file.')
    parser.add_argument('--export_as_json', action='store_true',
        help='export as a JSON file that can be read by auto-editor later.')
    parser.add_argument('--export_as_clip_sequence', '-excs', action='store_true',
        help='export as multiple numbered media files.')

    parser.add_argument('--temp_dir', default=None,
        help='set where the temporary directory is located.',
        extra='If not set, tempdir will be set with Python\'s tempfile module\n'
            'For Windows users, this file will be in the C drive.\n'
            'The temp file can get quite big if you\'re generating a huge video, so '
            'make sure your location has enough space.')
    parser.add_argument('--ffmpeg_location', default=None,
        help='set a custom path to the ffmpeg location.',
        extra='This takes precedence over --my_ffmpeg.')
    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use the ffmpeg on your PATH instead of the one packaged.',
        extra='this is equivalent to --ffmpeg_location ffmpeg.')
    parser.add_argument('--version', action='store_true',
        help='show which auto-editor you have.')
    parser.add_argument('--debug', action='store_true',
        help='show debugging messages and values.')
    parser.add_argument('--show_ffmpeg_debug', action='store_true',
        help='show ffmpeg progress and output.')
    parser.add_argument('--quiet', '-q', action='store_true',
        help='display less output.')

    parser.add_argument('--preview', action='store_true',
        help='show stats on how the input will be cut.')
    parser.add_argument('--no_open', action='store_true',
        help='do not open the file after editing is done.')
    parser.add_argument('--min_clip_length', '-mclip', type=frame_type, default=3,
        range='0 to Infinity',
        help='set the minimum length a clip can be. If a clip is too short, cut it.')
    parser.add_argument('--min_cut_length', '-mcut', type=frame_type, default=6,
        range='0 to Infinity',
        help="set the minimum length a cut can be. If a cut is too short, don't cut")

    parser.add_argument('--output_file', '--output', '-o', nargs='*',
        help='set the name(s) of the new output.')
    parser.add_argument('--silent_threshold', '-t', type=float_type, default=0.04,
        range='0 to 1',
        help='set the volume that frames audio needs to surpass to be "loud".')
    parser.add_argument('--silent_speed', '-s', type=float_type, default=99999,
        range='Any number. Values <= 0 or >= 99999 will be cut out.',
        help='set the speed that "silent" sections should be played at.')
    parser.add_argument('--video_speed', '--sounded_speed', '-v', type=float_type,
        default=1.00,
        range='Any number. Values <= 0 or >= 99999 will be cut out.',
        help='set the speed that "loud" sections should be played at.')
    parser.add_argument('--frame_margin', '--margin', '-m', type=frame_type, default=6,
        range='0 to Infinity',
        help='set how many "silent" frames of on either side of "loud" sections '
            'be included.')

    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    parser.add_argument('(input)', nargs='*',
        help='file(s) or URL(s) that will be edited.')
    return parser


def main():
    parser = vanparse.ArgumentParser('Auto-Editor', auto_editor.version,
        description='\nAuto-Editor is an automatic video/audio creator and editor. '
            'By default, it will detect silence and create a new video with those '
            'sections cut out. By changing some of the options, you can export to a '
            'traditional editor like Premiere Pro and adjust the edits there, adjust '
            'the pacing of the cuts, and change the method of editing like using audio '
            'loudness and video motion to judge making cuts.\nRun:\n    auto-editor '
            '--help\n\nTo get the list of options.\n')

    subcommands = ['create', 'test', 'info', 'levels', 'grep', 'subdump', 'desc']

    if(len(sys.argv) > 1 and sys.argv[1] in subcommands):
        obj = __import__('auto_editor.subcommands.{}'.format(sys.argv[1]),
            fromlist=['subcommands'])
        obj.main(sys.argv[2:])
        sys.exit()
    else:
        parser = main_options(parser)
        args = parser.parse_args(sys.argv[1:], Log(), 'auto-editor')

    timer = Timer(args.quiet)

    exporting_to_editor = (args.export_to_premiere or args.export_to_resolve or
        args.export_to_final_cut_pro or args.export_to_shotcut)
    making_data_file = exporting_to_editor or args.export_as_json

    is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, args.show_ffmpeg_debug)

    if(args.debug and args.input == []):
        import platform

        dirpath = os.path.dirname(os.path.realpath(__file__))

        print('Python Version: {} {}'.format(platform.python_version(), is64bit))
        print('Platform: {} {} {}'.format(platform.system(), platform.release(), platform.machine().lower()))
        print('Config File path: {}'.format(os.path.join(dirpath, 'config.txt')))
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

    log = Log(args.debug, args.quiet, temp=TEMP)
    log.debug('Temp Directory: {}'.format(TEMP))

    if(args.input == []):
        log.error('You need to give auto-editor an input file or folder so it can '
            'do the work for you.')

    if([args.export_to_premiere, args.export_to_resolve,
        args.export_to_final_cut_pro, args.export_as_audio,
        args.export_to_shotcut, args.export_as_clip_sequence].count(True) > 1):
        log.error('You must choose only one export option.')

    if(isinstance(args.frame_margin, str)):
        try:
            if(float(args.frame_margin) < 0):
                log.error('Frame margin cannot be negative.')
        except ValueError:
            log.error('Frame margin {}, is not valid.'.format(args.frame_margin))
    elif(args.frame_margin < 0):
        log.error('Frame margin cannot be negative.')
    if(args.constant_rate_factor != 'unset'):
        if(int(args.constant_rate_factor) < 0 or int(args.constant_rate_factor) > 51):
            log.error('Constant rate factor (crf) must be between 0-51.')
    if(args.width < 1):
        log.error('motionOps --width cannot be less than 1.')
    if(args.dilates < 0):
        log.error('motionOps --dilates cannot be less than 0')

    def write_starting_message(args):
        if(args.export_to_premiere):
            return 'Exporting to Adobe Premiere Pro XML file.'
        if(args.export_to_final_cut_pro):
            return 'Exporting to Final Cut Pro XML file.'
        if(args.export_to_resolve):
            return 'Exporting to DaVinci Resolve XML file.'
        if(args.export_to_shotcut):
            return 'Exporting to Shotcut XML Timeline file.'
        if(args.export_as_audio):
            return 'Exporting as audio.'
        return 'Starting.'

    if(not args.preview):
        log.conwrite(write_starting_message(args))

    if(args.preview or args.export_as_clip_sequence or making_data_file):
        args.no_open = True

    if(args.blur < 0):
        args.blur = 0

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

    speeds = [args.silent_speed, args.video_speed]
    if(args.cut_out != [] and 99999 not in speeds):
        speeds.append(99999)

    for item in args.set_speed_for_range:
        if(item[0] not in speeds):
            speeds.append(float(item[0]))

    log.debug('Speeds: {}'.format(speeds))

    def main_loop(input_list, ffmpeg, args, speeds, segments, log):
        num_cuts = 0

        progress = ProgressBar(args.machine_readable_progress, args.no_progress)

        for i, input_path in enumerate(input_list):
            inp = ffmpeg.file_info(input_path)

            if(len(input_list) > 1):
                log.conwrite('Working on {}'.format(inp.basename))

            cuts, output_path = edit_media(i, inp, ffmpeg, args, progress, speeds,
                segments[i], exporting_to_editor, making_data_file, TEMP, log)
            num_cuts += cuts

        if(not args.preview and not making_data_file):
            timer.stop()

        if(not args.preview and making_data_file):
            # Assume making each cut takes about 30 seconds.
            time_save = usefulfunctions.human_readable_time(num_cuts * 30)
            s = 's' if num_cuts != 1 else ''

            log.print('Auto-Editor made {} cut{}, which would have taken about {} if '
                'edited manually.'.format(num_cuts, s, time_save))

        if(not args.no_open):
            usefulfunctions.open_with_system_default(output_path, log)

    try:
        main_loop(input_list, ffmpeg, args, speeds, segments, log)
    except KeyboardInterrupt:
        log.error('Keyboard Interrupt')
    log.cleanup()

if(__name__ == '__main__'):
    main()
