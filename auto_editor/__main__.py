#!/usr/bin/env python3
'''__main__.py'''

# Internal python libraries
import os
import sys
import platform
import tempfile
import subprocess
from shutil import rmtree

version = '20w51a'

def file_type(file: str) -> str:
    if(not os.path.isfile(file)):
        print('Auto-Editor could not find the file: ' + file, file=sys.stderr)
        sys.exit(1)
    return file

def float_type(num: str) -> float:
    if(num.endswith('%')):
        return float(num[:-1]) / 100
    return float(num)

def sample_rate_type(num: str) -> int:
    if(num.endswith(' Hz')):
        return int(num[:-3])
    if(num.endswith(' kHz')):
        return int(float(num[:-4]) * 1000)
    return int(num)

def options():
    option_data = []

    def add_argument(*names, nargs=1, type=str, default=None, action='default',
        range=None, choices=None, parent='auto-editor', help='', extra=''):
        nonlocal option_data

        newDic = {}
        newDic['names'] = names
        newDic['nargs'] = nargs
        newDic['type'] = type
        newDic['default'] = default
        newDic['action'] = action
        newDic['help'] = help
        newDic['extra'] = extra
        newDic['range'] = range
        newDic['choices'] = choices
        newDic['grouping'] = parent
        option_data.append(newDic)


    add_argument('progressOps', nargs=0, action='grouping')
    add_argument('--machine_readable_progress', action='store_true', parent='progressOps',
        help='set progress bar that is easier to parse.')
    add_argument('--no_progress', action='store_true', parent='progressOps',
        help='do not display any progress at all.')

    add_argument('metadataOps', nargs=0, action='grouping')
    add_argument('--force_fps_to', type=float, parent='metadataOps',
        help='manually set the fps value for the input video if detection fails.')
    add_argument('--force_tracks_to', type=int, parent='metadataOps',
        help='manually set the number of tracks auto-editor thinks there are.')

    add_argument('exportMediaOps', nargs=0, action='grouping')
    add_argument('--video_bitrate', '-vb', parent='exportMediaOps',
        help='set the number of bits per second for video.')
    add_argument('--audio_bitrate', '-ab', parent='exportMediaOps',
        help='set the number of bits per second for audio.')
    add_argument('--sample_rate', '-r', type=sample_rate_type, parent='exportMediaOps',
        help='set the sample rate of the input and output videos.')
    add_argument('--video_codec', '-vcodec', default='uncompressed',
        parent='exportMediaOps',
        help='set the video codec for the output media file.')
    add_argument('--preset', '-p', default='medium', parent='exportMediaOps',
        choices=['ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium',
            'slow', 'slower', 'veryslow'],
        help='set the preset for ffmpeg to help save file size or increase quality.')
    add_argument('--tune', '-t', default='none', parent='exportMediaOps',
        choices=['film', 'animation', 'grain', 'stillimage', 'fastdecode',
            'zerolatency', 'none'],
        help='set the tune for ffmpeg to compress video better in certain circumstances.')
    add_argument('--constant_rate_factor', '-crf', type=int, default=15,
        parent='exportMediaOps', range='0 to 51',
        help='set the quality for video using the crf method.')

    add_argument('motionOps', nargs=0, action='grouping')
    add_argument('--dilates', '-d', type=int, default=2, range='0 to 5', parent='motionOps',
        help='set how many times a frame is dilated before being compared.')
    add_argument('--width', '-w', type=int, default=400, range='1 to Infinity', parent='motionOps',
        help="set the frame's new width (in pixels) before being compared.")
    add_argument('--blur', '-b', type=int, default=21, range='0 to Infinity', parent='motionOps',
        help='set the strength of the blur applied to a frame before being compared.')

    # TODO: add export_as_video
    add_argument('--export_as_audio', '-exa', action='store_true',
        help='export as a WAV audio file.')
    add_argument('--export_to_premiere', '-exp', action='store_true',
        help='export as an XML file for Adobe Premiere Pro instead of outputting a media file.')
    add_argument('--export_to_resolve', '-exr', action='store_true',
        help='export as an XML file for DaVinci Resolve instead of outputting a media file.')
    add_argument('--export_as_json', action='store_true',
        help='export as a JSON file that can be read by auto-editor later. (experimental)')

    add_argument('--ignore', nargs='*',
        help='the range that will be marked as "loud"')
    add_argument('--cut_out', nargs='*',
        help='the range that will be marked as "silent"')
    add_argument('--motion_threshold', type=float_type, default=0.02, range='0 to 1',
        help='how much motion is required to be considered "moving"')
    add_argument('--edit_based_on', default='audio',
        choices=['audio', 'motion', 'not_audio', 'not_motion', 'audio_or_motion',
            'audio_and_motion', 'audio_xor_motion', 'audio_and_not_motion',
            'not_audio_and_motion', 'not_audio_and_not_motion'],
        help='decide which method to use when making edits.')

    add_argument('--cut_by_this_audio', '-ca', type=file_type,
        help="base cuts by this audio file instead of the video's audio.")
    add_argument('--cut_by_this_track', '-ct', type=int, default=0,
        range='0 to the number of audio tracks minus one',
        help='base cuts by a different audio track in the video.')
    add_argument('--cut_by_all_tracks', '-cat', action='store_true',
        help='combine all audio tracks into one before basing cuts.')
    add_argument('--keep_tracks_seperate', action='store_true',
        help="don't combine audio tracks when exporting.")

    add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    add_argument('--version', action='store_true',
        help='show which auto-editor you have.')
    add_argument('--debug', '--verbose', '-d', action='store_true',
        help='show debugging messages and values.')
    add_argument('--show_ffmpeg_debug', action='store_true',
        help='show ffmpeg progress and output.')
    add_argument('--quiet', '-q', action='store_true',
        help='display less output.')

    add_argument('--no_open', action='store_true',
        help='do not open the file after editing is done.')
    add_argument('--min_clip_length', '-mclip', type=int, default=3, range='0 to Infinity',
        help='set the minimum length a clip can be. If a clip is too short, cut it.')
    add_argument('--min_cut_length', '-mcut', type=int, default=6, range='0 to Infinity',
        help="set the minimum length a cut can be. If a cut is too short, don't cut")
    add_argument('--combine_files', action='store_true',
        help='combine all input files into one before editing.')
    add_argument('--preview', action='store_true',
        help='show stats on how the input will be cut.')

    add_argument('--frame_margin', '-m', type=int, default=6, range='0 to Infinity',
        help='set how many "silent" frames of on either side of "loud" sections be included.')
    add_argument('--silent_threshold', '-t', type=float_type, default=0.04, range='0 to 1',
        help='set the volume that frames audio needs to surpass to be "loud".')
    add_argument('--video_speed', '--sounded_speed', '-v', type=float_type, default=1.00,
        range='0 to 999999',
        help='set the speed that "loud" sections should be played at.')
    add_argument('--silent_speed', '-s', type=float_type, default=99999, range='0 to 99999',
        help='set the speed that "silent" sections should be played at.')
    add_argument('--output_file', '--output', '-o', nargs='*',
        help='set the name(s) of the new output.')

    add_argument('--help', '-h', action='store_true',
        help='print info about the program or an option and exit.')
    add_argument('(input)', nargs='*',
        help='the path to a file, folder, or url you want edited.')

    return option_data

def main():
    dirPath = os.path.dirname(os.path.realpath(__file__))
    # Fixes pip not able to find other included modules.
    sys.path.append(os.path.abspath(dirPath))

    from usefulFunctions import Log, Timer

    option_data = options()

    # Print the version if only the -v option is added.
    if(sys.argv[1:] == ['-v'] or sys.argv[1:] == ['-V']):
        print(f'Auto-Editor version {version}\nPlease use --version instead.')
        sys.exit()

    # If the users just runs: $ auto-editor
    if(sys.argv[1:] == []):
        # Print
        print('\nAuto-Editor is an automatic video/audio creator and editor.\n')
        print('By default, it will detect silence and create a new video with ')
        print('those sections cut out. By changing some of the options, you can')
        print('export to a traditional editor like Premiere Pro and adjust the')
        print('edits there, adjust the pacing of the cuts, and change the method')
        print('of editing like using audio loudness and video motion to judge')
        print('making cuts.')
        print('\nRun:\n    auto-editor --help\n\nTo get the list of options.\n')
        sys.exit()

    from vanparse import ParseOptions
    args = ParseOptions(sys.argv[1:], Log(), option_data)

    log = Log(args.debug, args.show_ffmpeg_debug, args.quiet)
    log.debug('')

    # Print the help screen for the entire program.
    if(args.help):
        print('\n  Have an issue? Make an issue. '\
            'Visit https://github.com/wyattblue/auto-editor/issues\n')
        print('  The help option can also be used on a specific option:')
        print('      auto-editor --frame_margin --help\n')
        for option in option_data:
            if(option['grouping'] == 'auto-editor'):
                print(' ', ', '.join(option['names']) + ':', option['help'])
                if(option['action'] == 'grouping'):
                    print('     ...')
        print('')
        sys.exit()

    del option_data

    if(args.version):
        print('Auto-Editor version', version)
        sys.exit()

    from usefulFunctions import getBinaries, pipeToConsole, ffAddDebug
    from mediaMetadata import vidTracks, getSampleRate, getAudioBitrate
    from mediaMetadata import getVideoCodec, ffmpegFPS
    from wavfile import read

    ffmpeg, ffprobe = getBinaries(platform.system(), dirPath, args.my_ffmpeg)
    makingDataFile = (args.export_to_premiere or args.export_to_resolve or
        args.export_as_json)
    is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'

    if(args.debug and args.input == []):
        print('Python Version:', platform.python_version(), is64bit)
        print('Platform:', platform.system(), platform.release())
        # Platform can be 'Linux', 'Darwin' (macOS), 'Java', 'Windows'
        ffmpegVersion = pipeToConsole([ffmpeg, '-version']).split('\n')[0]
        ffmpegVersion = ffmpegVersion.replace('ffmpeg version', '').strip()
        ffmpegVersion = ffmpegVersion.split(' ')[0]
        print('FFmpeg path:', ffmpeg)
        print('FFmpeg version:', ffmpegVersion)
        print('Auto-Editor version', version)
        sys.exit()

    if(is64bit == '32-bit'):
        log.warning('You have the 32-bit version of Python, which may lead to' \
            'memory crashes.')

    from usefulFunctions import isLatestVersion
    if(not args.quiet and isLatestVersion(version, log)):
        log.print('\nAuto-Editor is out of date. Run:\n')
        log.print('    pip3 install -U auto-editor')
        log.print('\nto upgrade to the latest version.\n')

    from argsCheck import hardArgsCheck, softArgsCheck
    hardArgsCheck(args, log)
    args = softArgsCheck(args, log)

    from validateInput import validInput
    inputList = validInput(args.input, ffmpeg, log)

    timer = Timer(args.quiet)

    # Figure out the output file names.

    def newOutputName(oldFile: str, exa=False, data=False, exc=False) -> str:
        dotIndex = oldFile.rfind('.')
        if(exc):
            return oldFile[:dotIndex] + '.json'
        elif(data):
            return oldFile[:dotIndex] + '.xml'
        ext = oldFile[dotIndex:]
        if(exa):
            ext = '.wav'
        return oldFile[:dotIndex] + '_ALTERED' + ext

    if(len(args.output_file) < len(inputList)):
        for i in range(len(inputList) - len(args.output_file)):
            args.output_file.append(newOutputName(inputList[i],
                args.export_as_audio, makingDataFile, args.export_as_json))

    TEMP = tempfile.mkdtemp()
    log.debug(f'\n   - Temp Directory: {TEMP}')

    if(args.combine_files):
        # Combine video files, then set input to 'combined.mp4'.
        cmd = [ffmpeg, '-y']
        for fileref in inputList:
            cmd.extend(['-i', fileref])
        cmd.extend(['-filter_complex', f'[0:v]concat=n={len(inputList)}:v=1:a=1',
            '-codec:v', 'h264', '-pix_fmt', 'yuv420p', '-strict', '-2',
            f'{TEMP}/combined.mp4'])
        cmd = ffAddDebug(cmd, log.is_ffmpeg)
        subprocess.call(cmd)
        inputList = [f'{TEMP}/combined.mp4']

    speeds = [args.silent_speed, args.video_speed]
    log.debug(f'   - Speeds: {speeds}')

    audioExtensions = ['.wav', '.mp3', '.m4a', '.aiff', '.flac', '.ogg', '.oga',
        '.acc', '.nfa', '.mka']

    # videoExtensions = ['.mp4', '.mkv', '.mov', '.webm', '.ogv']

    for i, INPUT_FILE in enumerate(inputList):
        fileFormat = INPUT_FILE[INPUT_FILE.rfind('.'):]

        chunks = None
        if(fileFormat == '.json'):
            log.debug('Reading .json file')
            from makeCutList import readCutList
            INPUT_FILE, chunks, speeds = readCutList(INPUT_FILE, version, log)

            newOutput = newOutputName(INPUT_FILE, args.export_as_audio,
                makingDataFile, False)

            fileFormat = INPUT_FILE[INPUT_FILE.rfind('.'):]
        else:
            newOutput = args.output_file[i]

        log.debug(f'   - INPUT_FILE: {INPUT_FILE}')
        log.debug(f'   - newOutput: {newOutput}')

        if(os.path.isfile(newOutput) and INPUT_FILE != newOutput):
            log.debug(f'  Removing already existing file: {newOutput}')
            os.remove(newOutput)

        sampleRate = getSampleRate(INPUT_FILE, ffmpeg, args.sample_rate)
        audioBitrate = getAudioBitrate(INPUT_FILE, ffprobe, log, args.audio_bitrate)

        log.debug(f'   - sampleRate: {sampleRate}')
        log.debug(f'   - audioBitrate: {audioBitrate}')

        audioFile =  fileFormat in audioExtensions
        if(audioFile):
            if(args.force_fps_to is None):
                fps = 30 # Audio files don't have frames, so give fps a dummy value.
            else:
                fps = args.force_fps_to
            if(args.force_tracks_to is None):
                tracks = 1
            else:
                tracks = args.force_tracks_to
            cmd = [ffmpeg, '-y', '-i', INPUT_FILE]
            if(audioBitrate is not None):
                cmd.extend(['-b:a', audioBitrate])
            cmd.extend(['-ac', '2', '-ar', sampleRate, '-vn', f'{TEMP}/fastAud.wav'])
            cmd = ffAddDebug(cmd, log.is_ffmpeg)
            subprocess.call(cmd)

            sampleRate, audioData = read(f'{TEMP}/fastAud.wav')
        else:
            if(args.force_fps_to is not None):
                fps = args.force_fps_to
            elif(args.export_to_premiere):
                # This is the default fps value for Premiere Pro Projects.
                fps = 29.97
            else:
                # Grab fps to know what the output video's fps should be.
                # DaVinci Resolve doesn't need fps, but grab it away just in case.
                fps = ffmpegFPS(ffmpeg, INPUT_FILE, log)

            tracks = args.force_tracks_to
            if(tracks is None):
                tracks = vidTracks(INPUT_FILE, ffprobe, log)

            if(args.cut_by_this_track >= tracks):
                allTracks = ''
                for trackNum in range(tracks):
                    allTracks += f'Track {trackNum}\n'

                if(tracks == 1):
                    message = f'is only {tracks} track'
                else:
                    message = f'are only {tracks} tracks'
                log.error("You choose a track that doesn't exist.\n" \
                    f'There {message}.\n {allTracks}')

            # Get video codec
            vcodec = getVideoCodec(INPUT_FILE, ffmpeg, log, args.video_codec)

            # Split audio tracks into: 0.wav, 1.wav, etc.
            for trackNum in range(tracks):
                cmd = [ffmpeg, '-y', '-i', INPUT_FILE]
                if(audioBitrate is not None):
                    cmd.extend(['-ab', audioBitrate])
                cmd.extend(['-ac', '2', '-ar', sampleRate, '-map',
                    f'0:a:{trackNum}', f'{TEMP}/{trackNum}.wav'])
                cmd = ffAddDebug(cmd, log.is_ffmpeg)
                subprocess.call(cmd)

            # Check if the `--cut_by_all_tracks` flag has been set or not.
            if(args.cut_by_all_tracks):
                # Combine all audio tracks into one audio file, then read.
                cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-filter_complex',
                    f'[0:a]amix=inputs={tracks}:duration=longest', '-ar',
                    sampleRate, '-ac', '2', '-f', 'wav', #'-acodec', 'pcm_s16le',
                    f'{TEMP}/combined.wav']
                cmd = ffAddDebug(cmd, log.is_ffmpeg)
                subprocess.call(cmd)

                sampleRate, audioData = read(f'{TEMP}/combined.wav')
            else:
                # Read only one audio file.
                if(os.path.isfile(f'{TEMP}/{args.cut_by_this_track}.wav')):
                    sampleRate, audioData = read(f'{TEMP}/{args.cut_by_this_track}.wav')
                else:
                    log.bug('Audio track not found!')

        log.debug(f'   - Frame Rate: {fps}')
        if(chunks is None):
            from cutting import audioToHasLoud, motionDetection

            audioList = None
            motionList = None
            if('audio' in args.edit_based_on):
                log.debug('Analyzing audio volume.')
                audioList = audioToHasLoud(audioData, sampleRate,
                    args.silent_threshold,  fps, log)

            if('motion' in args.edit_based_on):
                log.debug('Analyzing video motion.')
                motionList = motionDetection(INPUT_FILE, ffprobe,
                    args.motion_threshold, log, width=args.width,
                    dilates=args.dilates, blur=args.blur)

                if(audioList is not None):
                    if(len(audioList) != len(motionList)):
                        log.debug(f'audioList Length:  {len(audioList)}')
                        log.debug(f'motionList Length: {len(motionList)}')
                    if(len(audioList) > len(motionList)):
                        log.debug('Reducing the size of audioList to match motionList.')
                        audioList = audioList[:len(motionList)]
                    elif(len(motionList) > len(audioList)):
                        log.debug('Reducing the size of motionList to match audioList.')
                        motionList = motionList[:len(audioList)]

            from cutting import combineArrs, applySpacingRules

            hasLoud = combineArrs(audioList, motionList, args.edit_based_on, log)
            del audioList, motionList

            chunks, includeFrame = applySpacingRules(hasLoud, fps,
                args.frame_margin, args.min_clip_length, args.min_cut_length,
                args.ignore, args.cut_out, log)
            del hasLoud
        else:
            from cutting import generateIncludes

            includeFrame = generateIncludes(chunks, log)

        clips = []
        numCuts = len(chunks)
        for chunk in chunks:
            if(speeds[chunk[2]] != 99999):
                clips.append([chunk[0], chunk[1], speeds[chunk[2]] * 100])

        if(fps is None and not audioFile):
            if(makingDataFile):
                dotIndex = INPUT_FILE.rfind('.')
                end = '_constantFPS' + INPUT_FILE[dotIndex:]
                constantLoc = INPUT_FILE[:dotIndex] + end
            else:
                constantLoc = f'{TEMP}/constantVid{fileFormat}'
            cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-filter:v', 'fps=fps=30',
                constantLoc]
            cmd = ffAddDebug(cmd, log.is_ffmpeg)
            subprocess.call(cmd)
            INPUT_FILE = constantLoc

        if(args.export_as_json):
            from makeCutList import makeCutList
            makeCutList(INPUT_FILE, newOutput, version, chunks, speeds, log)
            continue

        if(args.preview):
            newOutput = None
            from preview import preview
            preview(INPUT_FILE, chunks, speeds, fps, audioFile, log)
            continue

        if(args.export_to_premiere):
            from premiere import exportToPremiere
            exportToPremiere(INPUT_FILE, TEMP, newOutput, clips, tracks, sampleRate,
                audioFile, log)
            continue
        if(args.export_to_resolve):
            duration = chunks[len(chunks) - 1][1]
            from resolve import exportToResolve
            exportToResolve(INPUT_FILE, newOutput, clips, duration, sampleRate,
                audioFile, log)
            continue
        if(audioFile):
            from fastAudio import fastAudio, handleAudio
            theFile = handleAudio(ffmpeg, INPUT_FILE, audioBitrate, str(sampleRate),
                TEMP, log)
            fastAudio(theFile, newOutput, chunks, speeds, log, fps,
                args.machine_readable_progress, args.no_progress)
            continue

        from fastVideo import handleAudioTracks, fastVideo, muxVideo
        continueVid = handleAudioTracks(ffmpeg, newOutput, args.export_as_audio,
            tracks, args.keep_tracks_seperate, chunks, speeds, fps, TEMP,
            args.machine_readable_progress, args.no_progress, log)
        if(continueVid):
            fastVideo(INPUT_FILE, chunks, includeFrame, speeds, fps,
            args.machine_readable_progress, args.no_progress, TEMP, log)
            muxVideo(ffmpeg, newOutput, args.keep_tracks_seperate, tracks,
                args.video_bitrate, args.tune, args.preset, vcodec,
                args.constant_rate_factor, TEMP, log)

    if(newOutput is not None and not os.path.isfile(newOutput)):
        log.bug(f'The file {newOutput} was not created.')

    if(not args.preview and not makingDataFile):
        timer.stop()

    if(not args.preview and makingDataFile):
        from usefulFunctions import humanReadableTime
        # Assume making each cut takes about 30 seconds.
        timeSave = humanReadableTime(numCuts * 30)

        s = 's' if numCuts != 1 else ''
        log.print(f'Auto-Editor made {numCuts} cut{s}', end='')
        log.print(f', which would have taken about {timeSave} if edited manually.')

    if(not args.no_open):
        from usefulFunctions import smartOpen
        smartOpen(newOutput, log)

    rmtree(TEMP)

if(__name__ == '__main__'):
    main()
