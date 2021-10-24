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
from auto_editor.utils.effects import Effect
from auto_editor.utils.func import fnone, append_filename, set_output_name
from auto_editor.utils.log import Log, Timer
from auto_editor.ffwrapper import FFmpeg

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

    # parser.add_argument('multiOps', nargs=0, action='grouping')
    # parser.add_argument('--multi_processing', action='store_true', group='multiOps',
    #     help='enable video rendering multi-processing.')

    parser.add_argument('metadataOps', nargs=0, action='grouping')
    parser.add_argument('--force_fps_to', type=float, group='metadataOps',
        help='manually set the fps value for the input video if detection fails.')

    parser.add_argument('motionOps', nargs=0, action='grouping')
    parser.add_argument('--dilates', '-d', type=int, default=2, range='0 to 5',
        group='motionOps',
        help='set how many times a frame is dilated before being compared.')
    parser.add_argument('--width', '-w', type=int, default=400, range='1 to Infinity',
        group='motionOps',
        help="scale the frame to this width before being compared.")
    parser.add_argument('--blur', '-b', type=int, default=21, range='0 to Infinity',
        group='motionOps',
        help='set the strength of the blur applied to a frame before being compared.')

    parser.add_argument('urlOps', nargs=0, action='grouping')
    parser.add_argument('--format', type=str, group='urlOps',
        default='bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4',
        help='the format youtube-dl uses to when downloading a url.')
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
    parser.add_argument('--video_bitrate', '-vb', default='unset', group='exportMediaOps',
        help='set the number of bits per second for video.')
    parser.add_argument('--audio_bitrate', '-ab', default='unset', group='exportMediaOps',
        help='set the number of bits per second for audio.')
    parser.add_argument('--sample_rate', '-r', type=sample_rate_type,
        group='exportMediaOps',
        help='set the sample rate of the input and output videos.')
    parser.add_argument('--video_codec', '-vcodec', default='uncompressed',
        group='exportMediaOps',
        help='set the video codec for the output media file.')
    parser.add_argument('--audio_codec', '-acodec', group='exportMediaOps',
        help='set the audio codec for the output media file.')
    parser.add_argument('--preset', '-p', default='unset', group='exportMediaOps',
        choices=['ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium',
            'slow', 'slower', 'veryslow', 'unset'],
        help='set the preset for ffmpeg to help save file size or increase quality.')
    parser.add_argument('--tune', '-t', default='unset', group='exportMediaOps',
        choices=['film', 'animation', 'grain', 'stillimage', 'fastdecode',
            'zerolatency', 'none', 'unset'],
        help='set the tune for ffmpeg to compress video better in certain circumstances.')
    parser.add_argument('--constant_rate_factor', '-crf', default='unset',
        group='exportMediaOps', range='0 to 51',
        help='set the quality for video using the crf method.')
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
    parser.add_argument('--render', default='auto', hidden=True,
        help="defunct option. doesn't do anything.")
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
    parser.add_argument('--debug', '--verbose', '-d', action='store_true',
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
        help='the path to a file, folder, or url you want edited.')
    return parser


def get_chunks(inp, speeds, segment, fps, args, log, audio_samples=None, sample_rate=None):
    from auto_editor.cutting import (combine_audio_motion, combine_segment,
        apply_spacing_rules, apply_mark_as, apply_frame_margin, seconds_to_frames, cook)

    frame_margin = seconds_to_frames(args.frame_margin, fps)
    min_clip = seconds_to_frames(args.min_clip_length, fps)
    min_cut = seconds_to_frames(args.min_cut_length, fps)

    def get_has_loud(inp, args, fps, audio_samples, sample_rate, log):
        import numpy as np
        from auto_editor.analyze import get_np_list, audio_detection, motion_detection
        if(args.edit_based_on == 'none'):
            return get_np_list(inp, audio_samples, sample_rate, fps, np.ones)
        if(args.edit_based_on == 'all'):
            return get_np_list(inp, audio_samples, sample_rate, fps, np.zeros)

        audio_list, motion_list = None, None

        if('audio' in args.edit_based_on):
            if(audio_samples is None):
                audio_list = get_np_list(inp, audio_samples, sample_rate, fps, np.ones)
            else:
                audio_list = audio_detection(audio_samples, sample_rate,
                    args.silent_threshold, fps, log)

        if('motion' in args.edit_based_on):
            if(len(inp.video_streams) == 0):
                motion_list = get_np_list(inp, audio_samples, sample_rate, fps, np.ones)
            else:
                motion_list = motion_detection(inp, args.motion_threshold, log,
                    width=args.width, dilates=args.dilates, blur=args.blur)

        if(audio_list is not None and motion_list is not None):
            if(len(audio_list) > len(motion_list)):
                audio_list = audio_list[:len(motion_list)]
            elif(len(motion_list) > len(audio_list)):
                motion_list = motion_list[:len(audio_list)]

        return combine_audio_motion(audio_list, motion_list, args.edit_based_on, log)

    has_loud = get_has_loud(inp, args, fps, audio_samples, sample_rate, log)
    has_loud_length = len(has_loud)
    has_loud = apply_mark_as(has_loud, has_loud_length, fps, args, log)
    has_loud = cook(has_loud, min_clip, min_cut)
    has_loud = apply_frame_margin(has_loud, has_loud_length, frame_margin)

    if(segment is not None):
        has_loud = combine_segment(has_loud, segment, fps)
    # Remove small clips/cuts created by applying other rules.
    has_loud = cook(has_loud, min_clip, min_cut)
    return apply_spacing_rules(has_loud, has_loud_length, min_clip, min_cut, speeds,
        fps, args, log)


def edit_media(i, inp, ffmpeg, args, progress, speeds, segment, exporting_to_editor,
    data_file, TEMP, log):
    chunks = None
    if(inp.ext == '.json'):
        from auto_editor.formats.make_json import read_json_cutlist

        input_path, chunks, speeds = read_json_cutlist(inp.path, auto_editor.version, log)
        inp = ffmpeg.file_info(input_path)

        output_path = set_output_name(inp.path, data_file, args)
    else:
        output_path = args.output_file[i]
        if(not os.path.isdir(inp.path) and '.' not in output_path):
            output_path = set_output_name(output_path, data_file, args)

    log.debug('{} -> {}'.format(inp.path, output_path))

    if(os.path.isfile(output_path) and inp.path != output_path):
        log.debug('Removing already existing file: {}'.format(output_path))
        os.remove(output_path)

    def user_sample_rate(args_sample, inp):
        # type: (int | str | None, Any) -> str | None
        if(args_sample is None):
            if(len(inp.audio_streams) > 0):
                return inp.audio_streams[0]['samplerate']
            return None
        return str(args_sample)


    sample_rate = user_sample_rate(args.sample_rate, inp)
    log.debug('Samplerate: {}'.format(sample_rate))

    audio_samples = None
    audio_file = len(inp.video_streams) == 0 and len(inp.audio_streams) > 0
    tracks = len(inp.audio_streams)

    if(audio_file):
        fps = 30 if args.force_fps_to is None else args.force_fps_to

        temp_file = os.path.join(TEMP, 'fastAud.wav')

        cmd = ['-i', inp.path]
        if(not fnone(args.audio_bitrate)):
            cmd.extend(['-b:a', args.audio_bitrate])
        cmd.extend(['-ac', '2', '-ar', sample_rate, '-vn', temp_file])
        ffmpeg.run(cmd)

        from auto_editor.scipy.wavfile import read
        sample_rate, audio_samples = read(temp_file)
    else:
        if(args.force_fps_to is not None):
            fps = args.force_fps_to
        else:
            fps = float(inp.fps)
            if(exporting_to_editor):
                fps = int(fps)

        if(fps < 1):
            log.error('{}: Frame rate cannot be below 1. fps: {}'.format(
                inp.basename, fps))

        if(args.cut_by_this_track >= tracks and 'cut_by_this_track' in args._set):
            message = "You choose a track that doesn't exist.\nThere "
            if(tracks == 1):
                message += 'is only {} track.\n'.format(tracks)
            else:
                message += 'are only {} tracks.\n'.format(tracks)
            for t in range(tracks):
                message += ' Track {}\n'.format(t)
            log.error(message)

        def number_of_VFR_frames(text, log):
            import re
            search = re.search(r'VFR:[\d.]+ \(\d+\/\d+\)', text, re.M)
            if(search is None):
                log.warning('Could not get number of VFR Frames.')
                return 0
            else:
                nums = re.search(r'\d+\/\d+', search.group()).group(0)
                log.debug('VFR Frames: {}'.format(nums))
                return int(nums.split('/')[0])

        def has_VFR(cmd, log):
            return number_of_VFR_frames(ffmpeg.pipe(cmd), log) != 0

        # Extract subtitles in their native format.
        if(len(inp.subtitle_streams) > 0):
            cmd = ['-i', inp.path, '-hide_banner']
            for s, sub in enumerate(inp.subtitle_streams):
                cmd.extend(['-map', '0:s:{}'.format(s)])
            for s, sub in enumerate(inp.subtitle_streams):
                cmd.extend([os.path.join(TEMP, '{}s.{}'.format(s, sub['ext']))])
            ffmpeg.run(cmd)

        # Split audio tracks into: 0.wav, 1.wav, etc.
        cmd = ['-i', inp.path, '-hide_banner']
        for t in range(tracks):
            cmd.extend(['-map', '0:a:{}'.format(t)])
            if(not fnone(args.audio_bitrate)):
                cmd.extend(['-ab', args.audio_bitrate])
            cmd.extend(['-ac', '2', '-ar', sample_rate,
                os.path.join(TEMP, '{}.wav'.format(t))])
        cmd.extend(['-map', '0:v:0'])
        if(args.has_vfr == 'unset'):
            log.conwrite('Extracting audio / detecting VFR')
            cmd.extend(['-vf', 'vfrdet', '-f', 'null', '-'])
            has_vfr = has_VFR(cmd, log)
        else:
            log.conwrite('Extracting audio')
            ffmpeg.run(cmd)
            has_vfr = args.has_vfr == 'yes'
        del cmd

        if(len(inp.video_streams) > 0 and tracks == 0):
            # Doesn't matter because we don't need to align to an audio track.
            has_vfr = False

        log.debug('Has VFR: {}'.format(has_vfr))

        if(tracks != 0):
            if(args.cut_by_all_tracks):
                temp_file = os.path.join(TEMP, 'combined.wav')
                cmd = ['-i', inp.path, '-filter_complex',
                    '[0:a]amix=inputs={}:duration=longest'.format(tracks), '-ar',
                    sample_rate, '-ac', '2', '-f', 'wav', temp_file]
                ffmpeg.run(cmd)
                del cmd
            else:
                temp_file = os.path.join(TEMP, '{}.wav'.format(args.cut_by_this_track))

            from auto_editor.scipy.wavfile import read
            sample_rate, audio_samples = read(temp_file)

    effects = Effect(args, log, _vars={
        'silent_threshold': args.silent_threshold
        })
    effects.audio_samples = audio_samples
    effects.sample_rate = sample_rate

    log.debug('Frame Rate: {}'.format(fps))
    if(chunks is None):
        chunks = get_chunks(inp, speeds, segment, fps, args, log, audio_samples,
            sample_rate)

    def is_clip(chunk):
        # type: (list) -> bool
        return speeds[chunk[2]] != 99999

    def number_of_cuts(chunks, speeds):
        # type: (list, list) -> int
        return len(list(filter(is_clip, chunks)))

    def get_clips(chunks, speeds):
        clips = []
        for chunk in chunks:
            if(is_clip(chunk)):
                clips.append([chunk[0], chunk[1], speeds[chunk[2]] * 100])
        return clips

    num_cuts = number_of_cuts(chunks, speeds)
    clips = get_clips(chunks, speeds)

    if(args.export_as_json):
        from auto_editor.formats.make_json import make_json_cutlist
        make_json_cutlist(inp.path, output_path, auto_editor.version, chunks, speeds,
            log)
        return num_cuts, output_path

    if(args.preview):
        from auto_editor.preview import preview
        preview(inp, chunks, speeds, log)
        return num_cuts, None

    if(args.export_to_premiere):
        from auto_editor.formats.premiere import premiere_xml
        premiere_xml(inp, TEMP, output_path, clips, chunks, sample_rate, audio_file,
            fps, log)
        return num_cuts, output_path

    if(args.export_to_final_cut_pro or args.export_to_resolve):
        from auto_editor.formats.final_cut_pro import fcp_xml

        total_frames = chunks[len(chunks) - 1][1]
        fcp_xml(inp, TEMP, output_path, clips, tracks, total_frames, audio_file, fps, log)
        return num_cuts, output_path

    if(args.export_to_shotcut):
        from auto_editor.formats.shotcut import shotcut_xml

        shotcut_xml(inp, TEMP, output_path, clips, chunks, fps, log)
        return num_cuts, output_path

    def make_audio(inp, chunks, output_path):
        from auto_editor.render.audio import make_new_audio, handle_audio, convert_audio
        the_file = handle_audio(ffmpeg, inp.path, args.audio_bitrate, str(sample_rate),
            TEMP, log)

        temp_file = os.path.join(TEMP, 'convert.wav')
        make_new_audio(the_file, temp_file, chunks, speeds, log, fps, progress)
        convert_audio(ffmpeg, temp_file, inp, output_path, args.audio_codec, log)

    if(audio_file):
        if(args.export_as_clip_sequence):
            i = 1
            for item in chunks:
                if(speeds[item[2]] == 99999):
                    continue
                make_audio(inp, [item], append_filename(output_path, '-{}'.format(i)))
                i += 1
        else:
            make_audio(inp, chunks, output_path)
        return num_cuts, output_path

    def make_video_file(inp, chunks, output_path):
        from auto_editor.utils.video import handle_audio_tracks, mux_rename_video

        if(len(inp.subtitle_streams) > 0):
            from auto_editor.render.subtitle import cut_subtitles
            cut_subtitles(ffmpeg, inp, chunks, speeds, fps, TEMP, log)

        continue_video = handle_audio_tracks(ffmpeg, output_path, args, tracks, chunks,
            speeds, fps, progress, TEMP, log)
        if(continue_video):
            from auto_editor.render.av import render_av
            spedup = render_av(ffmpeg, inp, args, chunks, speeds, fps, has_vfr,
                progress, effects, TEMP, log)

            if(log.is_debug):
                log.debug('Writing the output file.')
            else:
                log.conwrite('Writing the output file.')

            mux_rename_video(ffmpeg, spedup, output_path, args, inp, TEMP, log)
            if(output_path is not None and not os.path.isfile(output_path)):
                log.bug('The file {} was not created.'.format(output_path))

    if(args.export_as_clip_sequence):

        def pad_chunk(item, total_frames):
            start = None
            end = None
            if(item[0] != 0):
                start = [0, item[0], 2]
            if(item[1] != total_frames -1):
                end = [item[1], total_frames -1, 2]

            if(start is None):
                return [item] + [end]
            if(end is None):
                return [start] + [item]
            return [start] + [item] + [end]

        i = 1
        total_frames = chunks[len(chunks) - 1][1]
        speeds.append(99999) # guarantee we have a cut speed to work with.
        for chunk in chunks:
            if(speeds[chunk[2]] == 99999):
                continue

            make_video_file(inp, pad_chunk(chunk, total_frames),
                append_filename(output_path, '-{}'.format(i)))
            i += 1
    else:
        make_video_file(inp, chunks, output_path)
    return num_cuts, output_path


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
        print('Platform: {} {}'.format(platform.system(), platform.release()))
        print('Config File path: {}'.format(os.path.join(dirpath, 'config.txt')))
        print('FFmpeg path: {}'.format(ffmpeg.getPath()))
        print('FFmpeg version: {}'.format(ffmpeg.version()))
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

    if(making_data_file and (args.video_codec != 'uncompressed' or
        args.constant_rate_factor != 'unset' or args.tune != 'unset')):
        log.warning('exportMediaOps options are not used when making a data file.')

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

    from auto_editor.validateInput import valid_input
    input_list, segments = valid_input(args.input, ffmpeg, args, log)

    if(len(args.output_file) < len(input_list)):
        for i in range(len(input_list) - len(args.output_file)):
            args.output_file.append(set_output_name(input_list[i], making_data_file, args))

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
