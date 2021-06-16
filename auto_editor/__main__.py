#!/usr/bin/env python3
'''__main__.py'''

# Python 2 Compatibility
from __future__ import print_function, absolute_import

# Internal Libraries
import os
import sys
import tempfile

# Included Libraries
import auto_editor
import auto_editor.vanparse as vanparse
import auto_editor.utils.func as usefulfunctions

from auto_editor.utils.func import fnone, append_filename
from auto_editor.utils.log import Log, Timer
from auto_editor.ffwrapper import FFmpeg

def set_output_name(path, making_data_file, args):
    dot_index = path.rfind('.')

    if(dot_index == -1):
        root = path
    else:
        root = path[:dot_index]

    if(args.export_as_json):
        return root + '.json'
    if(args.export_to_final_cut_pro):
        return root + '.fcpxml'
    if(args.export_to_shotcut):
        return root + '.mlt'
    if(making_data_file):
        return root + '.xml'
    if(args.export_as_audio):
        return root + '_ALTERED.wav'

    ext = path[dot_index:]
    return root + '_ALTERED' + ext


def main_options(parser):
    from auto_editor.utils.types import (file_type, float_type, sample_rate_type,
        frame_type, zoom_type, rect_type, range_type, speed_range_type)

    parser.add_argument('urlOps', nargs=0, action='grouping')
    parser.add_argument('--format', type=str, group='urlOps',
        default='bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4',
        help='the format youtube-dl uses to when downloading a url.')
    parser.add_argument('--output_dir', type=str, group='urlOps',
        default=None,
        help='the directory where the downloaded file is placed.')
    parser.add_argument('--check_certificate', action='store_true', group='urlOps',
        help='check the website certificate before downloading.')

    parser.add_argument('progressOps', nargs=0, action='grouping')
    parser.add_argument('--machine_readable_progress', action='store_true',
        group='progressOps',
        help='set progress bar that is easier to parse.')
    parser.add_argument('--no_progress', action='store_true',
        group='progressOps',
        help='do not display any progress at all.')

    parser.add_argument('metadataOps', nargs=0, action='grouping')
    parser.add_argument('--force_fps_to', type=float, group='metadataOps',
        help='manually set the fps value for the input video if detection fails.')

    parser.add_argument('exportMediaOps', nargs=0, action='grouping')
    parser.add_argument('--video_bitrate', '-vb', default='unset', group='exportMediaOps',
        help='set the number of bits per second for video.')
    parser.add_argument('--audio_bitrate', '-ab', default='unset', group='exportMediaOps',
        help='set the number of bits per second for audio.')
    # parser.add_argument('--video_quality', '-')
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

    parser.add_argument('--render', default='auto', choices=['av', 'opencv', 'auto'],
        help='choice which method to render video.')
    parser.add_argument('--scale', type=float_type, default=1,
        help='scale the output media file by a certian factor.')

    parser.add_argument('--zoom', type=zoom_type, nargs='*',
        help='set when and how a zoom will occur.',
        extra='The arguments are: start,end,start_zoom,end_zoom,x,y,inter,hold' \
            '\nThere must be at least 3 comma args. x and y default to centerX and centerY' \
            '\nThe default interpolation is linear.')
    parser.add_argument('--rectangle', type=rect_type, nargs='*',
        help='overlay a rectangle shape on the video.',
        extra='The arguments are: start,end,x1,y1,x2,y2,color,thickness' \
            '\nThere must be at least 6 comma args. The rectangle is solid if' \
            ' thickness is not defined.\n The default color is #000.')

    parser.add_argument('--background', type=str, default='#000',
        help='set the color of the background that is visible when the video is moved.')

    parser.add_argument('--mark_as_loud', type=range_type, nargs='*',
        help='the range that will be marked as "loud".')
    parser.add_argument('--mark_as_silent', type=range_type, nargs='*',
        help='the range that will be marked as "silent".')
    parser.add_argument('--cut_out', type=range_type, nargs='*',
        help='the range of media that will be removed completely, regardless of the '\
            'value of silent speed.')
    parser.add_argument('--set_speed_for_range', type=speed_range_type, nargs='*',
        help='set an arbitrary speed for a given range.',
        extra='The arguments are: speed,start,end')

    parser.add_argument('--motion_threshold', type=float_type, default=0.02,
        range='0 to 1',
        help='how much motion is required to be considered "moving"')
    parser.add_argument('--edit_based_on', default='audio',
        choices=['audio', 'motion', 'not_audio', 'not_motion', 'audio_or_motion',
            'audio_and_motion', 'audio_xor_motion', 'audio_and_not_motion',
            'not_audio_and_motion', 'not_audio_and_not_motion'],
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

    parser.add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    parser.add_argument('--version', action='store_true',
        help='show which auto-editor you have.')
    parser.add_argument('--debug', '--verbose', '-d', action='store_true',
        help='show debugging messages and values.')
    parser.add_argument('--show_ffmpeg_debug', action='store_true',
        help='show ffmpeg progress and output.')
    parser.add_argument('--quiet', '-q', action='store_true',
        help='display less output.')

    parser.add_argument('--combine_files', action='store_true',
        help='combine all input files into one before editing.')
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
    parser.add_argument('--frame_margin', '-m', type=frame_type, default=6,
        range='0 to Infinity',
        help='set how many "silent" frames of on either side of "loud" sections '\
            'be included.')

    parser.add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    parser.add_argument('(input)', nargs='*',
        help='the path to a file, folder, or url you want edited.')
    return parser


def edit_media(i, inp, ffmpeg, args, speeds, exporting_to_editor, data_file, TEMP, log):
    chunks = None
    if(inp.ext == '.json'):
        from auto_editor.formats.make_json import read_json_cutlist

        INPUT_FILE, chunks, speeds = read_json_cutlist(inp.path, auto_editor.version, log)

        inp = ffmpeg.file_info(INPUT_FILE)

        newOutput = set_output_name(inp.path, data_file, args)
    else:
        newOutput = args.output_file[i]
        if(not os.path.isdir(inp.path) and '.' not in newOutput):
            newOutput = set_output_name(newOutput, data_file, args)

    log.debug('Input File: {}'.format(inp.path))
    log.debug('Output File: {}'.format(newOutput))

    if(os.path.isfile(newOutput) and inp.path != newOutput):
        log.debug('Removing already existing file: {}'.format(newOutput))
        os.remove(newOutput)

    if(args.sample_rate is None):
        sampleRate = inp.audio_streams[0]['samplerate']
        if(sampleRate is None):
            sampleRate = '48000'
    else:
        sampleRate = str(args.sample_rate)
    log.debug('Samplerate: {}'.format(sampleRate))

    audioData = None
    audioExtensions = ['.wav', '.mp3', '.m4a', '.aiff', '.flac', '.ogg', '.oga',
        '.acc', '.nfa', '.mka']
    audioFile = inp.ext in audioExtensions
    if(audioFile):
        fps = 30 if args.force_fps_to is None else args.force_fps_to
        tracks = 1

        temp_file = os.path.join(TEMP, 'fastAud.wav')

        cmd = ['-i', inp.path]
        if(not fnone(args.audio_bitrate)):
            cmd.extend(['-b:a', args.audio_bitrate])
        cmd.extend(['-ac', '2', '-ar', sampleRate, '-vn', temp_file])
        ffmpeg.run(cmd)

        from auto_editor.scipy.wavfile import read
        sampleRate, audioData = read(temp_file)
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

        tracks = len(inp.audio_streams)

        if(args.cut_by_this_track >= tracks):
            message = "You choose a track that doesn't exist.\nThere "
            if(tracks == 1):
                message += 'is only {} track.\n'.format(tracks)
            else:
                message += 'are only {} tracks.\n'.format(tracks)
            for t in range(tracks):
                message += ' Track {}\n'.format(t)
            log.error(message)

        def NumberOfVrfFrames(text, log):
            import re
            search = re.search(r'VFR:[\d.]+ \(\d+\/\d+\)', text, re.M)
            if(search is None):
                log.warning('Could not get number of VFR Frames.')
                return 0
            else:
                nums = re.search(r'\d+\/\d+', search.group()).group(0)
                log.debug(nums)
                return int(nums.split('/')[0])

        def hasVFR(cmd, log):
            return NumberOfVrfFrames(ffmpeg.pipe(cmd), log) != 0

        # Split audio tracks into: 0.wav, 1.wav, etc.
        cmd = ['-i', inp.path, '-hide_banner']
        for t in range(tracks):
            cmd.extend(['-map', '0:a:{}'.format(t)])
            if(not fnone(args.audio_bitrate)):
                cmd.extend(['-ab', args.audio_bitrate])
            cmd.extend(['-ac', '2', '-ar', sampleRate,
                os.path.join(TEMP, '{}.wav'.format(t))])
        cmd.extend(['-map', '0:v:0', '-vf', 'vfrdet', '-f', 'null', '-'])
        has_vfr = hasVFR(cmd, log)
        del cmd

        if(args.cut_by_all_tracks):
            temp_file = os.path.join(TEMP, 'combined.wav')
            cmd = ['-i', inp.path, '-filter_complex',
                '[0:a]amix=inputs={}:duration=longest'.format(tracks), '-ar',
                sampleRate, '-ac', '2', '-f', 'wav', temp_file]
            ffmpeg.run(cmd)
            del cmd
        else:
            temp_file = os.path.join(TEMP, '{}.wav'.format(args.cut_by_this_track))

        from auto_editor.scipy.wavfile import read
        sampleRate, audioData = read(temp_file)

    log.debug('Frame Rate: {}'.format(fps))
    if(chunks is None):
        from auto_editor.cutting import audioToHasLoud, motionDetection
        from auto_editor.cutting import combineArrs, applySpacingRules

        audioList = None
        motionList = None
        if('audio' in args.edit_based_on):
            log.debug('Analyzing audio volume.')
            audioList = audioToHasLoud(audioData, sampleRate,
                args.silent_threshold,  fps, log)

        if('motion' in args.edit_based_on):
            log.debug('Analyzing video motion.')
            motionList = motionDetection(inp, args.motion_threshold, log,
                width=args.width, dilates=args.dilates, blur=args.blur)

            if(audioList is not None):
                if(len(audioList) != len(motionList)):
                    log.debug('audioList Length:  {}'.format(len(audioList)))
                    log.debug('motionList Length: {}'.format(len(motionList)))
                if(len(audioList) > len(motionList)):
                    log.debug('Reducing the size of audioList to match motionList.')
                    audioList = audioList[:len(motionList)]
                elif(len(motionList) > len(audioList)):
                    log.debug('Reducing the size of motionList to match audioList.')
                    motionList = motionList[:len(audioList)]

        hasLoud = combineArrs(audioList, motionList, args.edit_based_on, log)
        del audioList, motionList

        effects = []
        if(args.zoom != []):
            from auto_editor.cutting import applyZooms
            effects += applyZooms(args.zoom, audioData, sampleRate, fps, log)
        if(args.rectangle != []):
            from auto_editor.cutting import applyRects
            effects += applyRects(args.rectangle, audioData, sampleRate, fps, log)

        chunks = applySpacingRules(hasLoud, speeds, fps, args, log)
        del hasLoud

    def isClip(chunk):
        return speeds[chunk[2]] != 99999

    def getNumberOfCuts(chunks, speeds):
        return len(list(filter(isClip, chunks)))

    def getClips(chunks, speeds):
        clips = []
        for chunk in chunks:
            if(isClip(chunk)):
                clips.append([chunk[0], chunk[1], speeds[chunk[2]] * 100])
        return clips

    num_cuts = getNumberOfCuts(chunks, speeds)
    clips = getClips(chunks, speeds)

    if(args.export_as_json):
        from auto_editor.formats.make_json import make_json_cutlist
        make_json_cutlist(inp.path, newOutput, auto_editor.version, chunks, speeds,
            log)
        return num_cuts, newOutput

    if(args.preview):
        from auto_editor.preview import preview
        preview(inp, chunks, speeds, log)
        return num_cuts, None

    if(args.export_to_premiere):
        from auto_editor.formats.premiere import premiere_xml
        premiere_xml(inp, TEMP, newOutput, clips, chunks, sampleRate, audioFile,
            fps, log)
        return num_cuts, newOutput

    if(args.export_to_final_cut_pro or args.export_to_resolve):
        from auto_editor.formats.final_cut_pro import fcp_xml

        totalFrames = chunks[len(chunks) - 1][1]
        fcp_xml(inp, TEMP, newOutput, clips, tracks, totalFrames, audioFile, fps, log)
        return num_cuts, newOutput

    if(args.export_to_shotcut):
        from auto_editor.formats.shotcut import shotcut_xml

        shotcut_xml(inp, TEMP, newOutput, clips, chunks, fps, log)
        return num_cuts, newOutput

    def makeAudioFile(inp, chunks, output):
        from auto_editor.render.audio import fastAudio, handleAudio, convertAudio
        theFile = handleAudio(ffmpeg, inp.path, args.audio_bitrate, str(sampleRate),
            TEMP, log)

        temp_file = os.path.join(TEMP, 'convert.wav')
        fastAudio(theFile, temp_file, chunks, speeds, log, fps,
            args.machine_readable_progress, args.no_progress)
        convertAudio(ffmpeg, temp_file, inp, output, args.audio_codec, log)

    if(audioFile):
        if(args.export_as_clip_sequence):
            i = 1
            for item in chunks:
                if(speeds[item[2]] == 99999):
                    continue
                makeAudioFile(inp, [item], append_filename(newOutput, '-{}'.format(i)))
                i += 1
        else:
            makeAudioFile(inp, chunks, newOutput)
        return num_cuts, newOutput

    def makeVideoFile(inp, chunks, output):
        from auto_editor.utils.video import handleAudioTracks, muxVideo
        continueVid = handleAudioTracks(ffmpeg, output, args, tracks, chunks,
            speeds, fps, TEMP, log)
        if(continueVid):
            if(args.render == 'auto'):
                if(args.zoom != [] or args.rectangle != []):
                    args.render = 'opencv'
                else:
                    try:
                        import av
                        args.render = 'av'
                    except ImportError:
                        args.render = 'opencv'

            log.debug('Using {} method'.format(args.render))
            if(args.render == 'av'):
                if(args.zoom != []):
                    log.error('Zoom effect is not supported on the '\
                        'av render method.')

                if(args.rectangle != []):
                    log.error('Rectangle effect is not supported on the '\
                        'av render method.')

                from auto_editor.render.av import render_av
                render_av(ffmpeg, inp, args, chunks, speeds, fps, has_vfr, TEMP, log)

            if(args.render == 'opencv'):
                from auto_editor.render.opencv import render_opencv
                render_opencv(ffmpeg, inp, args, chunks, speeds, fps, has_vfr,
                    effects, TEMP, log)

            if(log.is_debug):
                log.debug('Writing the output file.')
            else:
                log.conwrite('Writing the output file.')

            muxVideo(ffmpeg, output, args, tracks, TEMP, log)
            if(output is not None and not os.path.isfile(output)):
                log.bug('The file {} was not created.'.format(output))

    if(args.export_as_clip_sequence):

        def pad_chunk(item, totalFrames):
            start = None
            end = None
            if(item[0] != 0):
                start = [0, item[0], 2]
            if(item[1] != totalFrames -1):
                end = [item[1], totalFrames -1, 2]

            if(start is None):
                return [item] + [end]
            if(end is None):
                return [start] + [item]
            return [start] + [item] + [end]

        i = 1
        totalFrames = chunks[len(chunks) - 1][1]
        speeds.append(99999) # guarantee we have a cut speed to work with.
        for chunk in chunks:
            if(speeds[chunk[2]] == 99999):
                continue

            makeVideoFile(inp, pad_chunk(chunk, totalFrames),
                append_filename(newOutput, '-{}'.format(i)))
            i += 1
    else:
        makeVideoFile(inp, chunks, newOutput)
    return num_cuts, newOutput


def main():
    dir_path = os.path.dirname(os.path.realpath(__file__))

    parser = vanparse.ArgumentParser('Auto-Editor', auto_editor.version,
        description='\nAuto-Editor is an automatic video/audio creator and editor. '\
            'By default, it will detect silence and create a new video with those '\
            'sections cut out. By changing some of the options, you can export to a '\
            'traditional editor like Premiere Pro and adjust the edits there, adjust '\
            'the pacing of the cuts, and change the method of editing like using audio '\
            'loudness and video motion to judge making cuts.\nRun:\n    auto-editor '\
            '--help\n\nTo get the list of options.\n')

    subcommands = ['create', 'test', 'info', 'levels', 'grep']

    if(len(sys.argv) > 1 and sys.argv[1] in subcommands):
        if(sys.argv[1] == 'create'):
            from auto_editor.subcommands.create import create as sub
        if(sys.argv[1] == 'test'):
            from auto_editor.subcommands.test import test as sub
        if(sys.argv[1] == 'info'):
            from auto_editor.subcommands.info import info as sub
        if(sys.argv[1] == 'levels'):
            from auto_editor.subcommands.levels import levels as sub
        if(sys.argv[1] == 'grep'):
            from auto_editor.subcommands.grep import grep as sub

        sub(sys.argv[2:])

        sys.exit()
    else:
        parser = main_options(parser)
        args = parser.parse_args(sys.argv[1:], Log(), 'auto-editor')

    timer = Timer(args.quiet)

    exporting_to_editor = (args.export_to_premiere or args.export_to_resolve or
        args.export_to_final_cut_pro or args.export_to_shotcut)
    making_data_file = exporting_to_editor or args.export_as_json

    is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'

    if(args.debug and args.input == []):
        import platform
        log = Log()
        ffmpeg = FFmpeg(dir_path, args.my_ffmpeg, args.show_ffmpeg_debug, log)

        print('Python Version: {} {}'.format(platform.python_version(), is64bit))
        print('Platform: {} {}'.format(platform.system(), platform.release()))
        print('Config File path: {}'.format(os.path.join(dir_path, 'config.txt')))
        print('FFmpeg path: {}'.format(ffmpeg.getPath()))
        print('FFmpeg version: {}'.format(ffmpeg.getVersion()))
        print('Auto-Editor version {}'.format(auto_editor.version))
        sys.exit()

    if(is64bit == '32-bit'):
        log.warning('You have the 32-bit version of Python, which may lead to '\
            'memory crashes.')

    if(args.version):
        print('Auto-Editor version {}'.format(auto_editor.version))
        sys.exit()

    TEMP = tempfile.mkdtemp()
    log = Log(args.debug, args.quiet, temp=TEMP)
    ffmpeg = FFmpeg(dir_path, args.my_ffmpeg, args.show_ffmpeg_debug, log)

    log.debug('Temp Directory: {}'.format(TEMP))

    if(args.input == []):
        log.error('You need to give auto-editor an input file or folder so it can ' \
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


    def write_starting_message(args, log):
        if(args.preview):
            pass
        elif(args.export_to_premiere):
            log.conwrite('Exporting to Adobe Premiere Pro XML file.')
        elif(args.export_to_final_cut_pro):
            log.conwrite('Exporting to Final Cut Pro XML file.')
        elif(args.export_to_resolve):
            log.conwrite('Exporting to DaVinci Resolve XML file.')
        elif(args.export_to_shotcut):
            log.conwrite('Exporting to Shotcut XML Timeline file.')
        elif(args.export_as_audio):
            log.conwrite('Exporting as audio.')
        else:
            log.conwrite('Starting.')

    write_starting_message(args, log)

    if(args.preview or args.export_as_clip_sequence or making_data_file):
        args.no_open = True

    args.background = usefulfunctions.hex_to_bgr(args.background, log)
    if(args.blur < 0):
        args.blur = 0

    if(args.silent_speed <= 0 or args.silent_speed > 99999):
        args.silent_speed = 99999

    if(args.video_speed <= 0 or args.video_speed > 99999):
        args.video_speed = 99999

    if(args.output_file is None):
        args.output_file = []

    from auto_editor.validateInput import validInput
    inputList = validInput(args.input, ffmpeg, args, log)

    if(len(args.output_file) < len(inputList)):
        for i in range(len(inputList) - len(args.output_file)):
            args.output_file.append(set_output_name(inputList[i], making_data_file, args))

    if(args.combine_files):
        temp_file = os.path.join(TEMP, 'combined.mp4')
        cmd = []
        for fileref in inputList:
            cmd.extend(['-i', fileref])
        cmd.extend(['-filter_complex', '[0:v]concat=n={}:v=1:a=1'.format(len(inputList)),
            '-codec:v', 'h264', '-pix_fmt', 'yuv420p', '-strict', '-2', temp_file])
        ffmpeg.run(cmd)
        del cmd
        inputList = [temp_file]

    speeds = [args.silent_speed, args.video_speed]
    if(args.cut_out != [] and 99999 not in speeds):
        speeds.append(99999)

    for item in args.set_speed_for_range:
        if(item[0] not in speeds):
            speeds.append(float(item[0]))

    log.debug('Speeds: {}'.format(speeds))

    def main_loop(inputList, ffmpeg, args, speeds, log):
        num_cuts = 0

        for i, INPUT_FILE in enumerate(inputList):
            inp = ffmpeg.file_info(INPUT_FILE)

            if(len(inputList) > 1):
                log.conwrite('Working on {}'.format(inp.basename))

            cuts, newOutput = edit_media(i, inp, ffmpeg, args, speeds,
                exporting_to_editor, making_data_file, TEMP, log)
            num_cuts += cuts

        if(not args.preview and not making_data_file):
            timer.stop()

        if(not args.preview and making_data_file):
            # Assume making each cut takes about 30 seconds.
            time_save = usefulfunctions.human_readable_time(num_cuts * 30)
            s = 's' if num_cuts != 1 else ''

            log.print('Auto-Editor made {} cut{}, which would have taken about {} if '\
                'edited manually.'.format(num_cuts, s, time_save))

        if(not args.no_open):
            usefulfunctions.open_with_system_default(newOutput, log)

    try:
        main_loop(inputList, ffmpeg, args, speeds, log)
    except KeyboardInterrupt:
        log.error('Keyboard Interrupt')
    log.cleanup()

if(__name__ == '__main__'):
    main()
