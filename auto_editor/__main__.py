#!/usr/bin/env python3
'''__main__.py'''

# Internal python libraries
import os
import re
import sys
import platform
import tempfile
import subprocess
from shutil import rmtree

version = '20w48a'

def file_type(file: str) -> str:
    if(not os.path.isfile(file)):
        print('Auto-Editor could not find the file: ' + file)
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

def main():
    options = []

    def add_argument(*names, nargs=1, type=str, default=None,
        action='default', range=None, choices=None, help='', extra=''):
        nonlocal options

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
        options.append(newDic)

    add_argument('(input)', nargs='*',
        help='the path to a file, folder, or url you want edited.')
    add_argument('--help', '-h', action='store_true',
        help='print this message and exit.')

    add_argument('--frame_margin', '-m', type=int, default=6, range='0 to Infinity',
        help='set how many "silent" frames of on either side of "loud" sections be included.')
    add_argument('--silent_threshold', '-t', type=float_type, default=0.04, range='0 to 1',
        help='set the volume that frames audio needs to surpass to be "loud".')
    add_argument('--video_speed', '--sounded_speed', '-v', type=float_type, default=1.00,
        range='0 to 999999',
        help='set the speed that "loud" sections should be played at.')
    add_argument('--silent_speed', '-s', type=float_type, default=99999, range='0 to 99999',
        help='set the speed that "silent" sections should be played at.')
    add_argument('--output_file', '-o', nargs='*',
        help='set the name(s) of the new output.')

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
    add_argument('--debug', '--verbose', action='store_true',
        help='show debugging messages and values.')
    add_argument('--show_ffmpeg_debug', action='store_true',
        help='show ffmpeg progress and output.')

    # TODO: add export_as_video
    add_argument('--export_as_audio', '-exa', action='store_true',
        help='export as a WAV audio file.')
    add_argument('--export_to_premiere', '-exp', action='store_true',
        help='export as an XML file for Adobe Premiere Pro instead of outputting a media file.')
    add_argument('--export_to_resolve', '-exr', action='store_true',
        help='export as an XML file for DaVinci Resolve instead of outputting a media file.')

    add_argument('--video_bitrate', '-vb',
        help='set the number of bits per second for video.')
    add_argument('--audio_bitrate', '-ab',
        help='set the number of bits per second for audio.')
    add_argument('--sample_rate', '-r', type=sample_rate_type,
        help='set the sample rate of the input and output videos.')
    add_argument('--video_codec', '-vcodec', default='uncompressed',
        help='set the video codec for the output media file.')
    add_argument('--preset', '-p', default='medium',
        choices=['ultrafast', 'superfast', 'veryfast', 'faster', 'fast', 'medium',
            'slow', 'slower', 'veryslow'],
        help='set the preset for ffmpeg to help save file size or increase quality.')
    add_argument('--tune', default='none',
        choices=['film', 'animation', 'grain', 'stillimage', 'fastdecode',
            'zerolatency', 'none'],
        help='set the tune for ffmpeg to compress video better.')

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

    dirPath = os.path.dirname(os.path.realpath(__file__))
    # Fixes pip not able to find other included modules.
    sys.path.append(os.path.abspath(dirPath))

    from usefulFunctions import Log, Timer
    from parser import parse_options

    args = parse_options(sys.argv[1:], Log(), options)

    # Print the help screen for the entire program.
    if(args.help):
        print('')
        for option in options:
            print(' ', ', '.join(option['names']) + ':', option['help'])
        print('\nThe help command can also be used on a specific option.')
        print('example:')
        print('    auto-editor --frame_margin --help')
        print('\nHave an issue? Make an issue. '\
            'Visit https://github.com/wyattblue/auto-editor/issues')
        sys.exit()

    if(args.version):
        print('Auto-Editor version', version)
        sys.exit()

    audioExtensions = ['.wav', '.mp3', '.m4a', '.aiff', '.flac', '.ogg', '.oga',
        '.acc', '.nfa', '.mka']

    # videoExtensions = ['.mp4', '.mkv', '.mov', '.webm', '.ogv']

    invalidExtensions = ['.txt', '.md', '.rtf', '.csv', '.cvs', '.html', '.htm',
        '.xml', '.json', '.yaml', '.png', '.jpeg', '.jpg', '.gif', '.exe', '.doc',
        '.docx', '.odt', '.pptx', '.xlsx', '.xls', 'ods', '.pdf', '.bat', '.dll',
        '.prproj', '.psd', '.aep', '.zip', '.rar', '.7z', '.java', '.class', '.js',
        '.c', '.cpp', '.csharp', '.py', '.app', '.git', '.github', '.gitignore',
        '.db', '.ini', '.BIN']

    from usefulFunctions import conwrite, getBinaries, pipeToConsole, ffAddDebug
    from mediaMetadata import vidTracks, getSampleRate, getAudioBitrate
    from mediaMetadata import getVideoCodec, ffmpegFPS
    from wavfile import read

    if(not args.preview):
        if(args.export_to_premiere):
            conwrite('Exporting to Adobe Premiere Pro XML file.')
        elif(args.export_to_resolve):
            conwrite('Exporting to DaVinci Resolve XML file.')
        elif(args.export_as_audio):
            conwrite('Exporting as audio.')
        else:
            conwrite('Starting.')

    ffmpeg, ffprobe = getBinaries(platform.system(), dirPath, args.my_ffmpeg)
    makingDataFile = args.export_to_premiere or args.export_to_resolve
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

    log = Log(args.debug, args.show_ffmpeg_debug)
    log.debug('')

    if(is64bit == '32-bit'):
        log.warning('You have the 32-bit version of Python, which may lead to memory crashes.')
    if(args.frame_margin < 0):
        log.error('Frame margin cannot be negative.')

    if(args.input == []):
        log.error('You need the (input) argument so that auto-editor can do the work for you.')

    try:
        from requests import get
        latestVersion = get('https://raw.githubusercontent.com/wyattblue/auto-editor/master/resources/version.txt')
        if(latestVersion.text != version):
            print('\nAuto-Editor is out of date. Run:\n')
            print('    pip3 install -U auto-editor')
            print('\nto upgrade to the latest version.\n')
        del latestVersion
    except Exception as err:
        log.debug('Connection Error: ' + str(err))

    if(args.silent_speed <= 0 or args.silent_speed > 99999):
        args.silent_speed = 99999
    if(args.video_speed <= 0 or args.video_speed > 99999):
        args.video_speed = 99999

    inputList = []
    for myInput in args.input:
        if(os.path.isdir(myInput)):
            def validFiles(path: str, badExts: list):
                for f in os.listdir(path):
                    if(not f[f.rfind('.'):] in badExts):
                        yield os.path.join(path, f)

            inputList += sorted(validFiles(myInput, invalidExtensions))
        elif(os.path.isfile(myInput)):
            inputList.append(myInput)
        elif(myInput.startswith('http://') or myInput.startswith('https://')):
            basename = re.sub(r'\W+', '-', myInput)

            if(not os.path.isfile(basename + '.mp4')):
                print('URL detected, using youtube-dl to download from webpage.')
                cmd = ['youtube-dl', '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4',
                       myInput, '--output', basename, '--no-check-certificate']
                if(ffmpeg != 'ffmpeg'):
                    cmd.extend(['--ffmpeg-location', ffmpeg])
                subprocess.call(cmd)

            inputList.append(basename + '.mp4')
        else:
            log.error('Could not find file: ' + myInput)

    timer = Timer()

    if(args.output_file is None):
        args.output_file = []

    # Figure out the output file names.
    if(len(args.output_file) < len(inputList)):
        for i in range(len(inputList) - len(args.output_file)):
            oldFile = inputList[i]
            dotIndex = oldFile.rfind('.')
            if(args.export_to_premiere or args.export_to_resolve):
                args.output_file.append(oldFile[:dotIndex] + '.xml')
            else:
                ext = oldFile[dotIndex:]
                if(args.export_as_audio):
                    ext = '.wav'
                end = '_ALTERED' + ext
                args.output_file.append(oldFile[:dotIndex] + end)

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
    numCuts = 0
    for i, INPUT_FILE in enumerate(inputList):
        log.debug(f'   - INPUT_FILE: {INPUT_FILE}')
        # Ignore folders
        if(os.path.isdir(INPUT_FILE)):
            continue

        # Throw error if file referenced doesn't exist.
        if(not os.path.isfile(INPUT_FILE)):
            log.error(f"{INPUT_FILE} doesn't exist!")

        # Check if the file format is valid.
        fileFormat = INPUT_FILE[INPUT_FILE.rfind('.'):]

        if(fileFormat in invalidExtensions):
            log.error(f'Invalid file extension "{fileFormat}" for {INPUT_FILE}')

        # Get output file name.
        newOutput = args.output_file[i]
        log.debug(f'   - newOutput: {newOutput}')

        sampleRate = getSampleRate(INPUT_FILE, ffmpeg, args.sample_rate)
        audioBitrate = getAudioBitrate(INPUT_FILE, ffprobe, log, args.audio_bitrate)

        audioFile = fileFormat in audioExtensions
        if(audioFile):
            fps = 30 # Audio files don't have frames, so give fps a dummy value.
            tracks = 1
            cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-b:a', audioBitrate, '-ac', '2',
                '-ar', sampleRate, '-vn', f'{TEMP}/fastAud.wav']
            cmd = ffAddDebug(cmd, log.is_ffmpeg)
            subprocess.call(cmd)

            sampleRate, audioData = read(f'{TEMP}/fastAud.wav')
        else:
            if(args.export_to_premiere):
                # This is the default fps value for Premiere Pro Projects.
                fps = 29.97
            else:
                # Grab fps to know what the output video's fps should be.
                # DaVinci Resolve doesn't need fps, but grab it away just in case.
                fps = ffmpegFPS(ffmpeg, INPUT_FILE, log)

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

            if(args.video_bitrate is not None and vcodec == 'copy'):
                log.warning('Your bitrate will not be applied because the video' \
                    ' codec is "uncompressed".')

            # Split audio tracks into: 0.wav, 1.wav, etc.
            for trackNum in range(tracks):
                cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-ab', audioBitrate,
                    '-ac', '2', '-ar', sampleRate, '-map', f'0:a:{trackNum}',
                    f'{TEMP}/{trackNum}.wav']
                cmd = ffAddDebug(cmd, log.is_ffmpeg)
                subprocess.call(cmd)

            # Check if the `--cut_by_all_tracks` flag has been set or not.
            if(args.cut_by_all_tracks):
                # Combine all audio tracks into one audio file, then read.
                cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-filter_complex',
                    f'[0:a]amerge=inputs={tracks}', '-map', 'a', '-ar',
                    sampleRate, '-ac', '2', '-f', 'wav', f'{TEMP}/combined.wav']
                cmd = ffAddDebug(cmd, log.is_ffmpeg)
                subprocess.call(cmd)

                sampleRate, audioData = read(f'{TEMP}/combined.wav')
            else:
                # Read only one audio file.
                if(os.path.isfile(f'{TEMP}/{args.cut_by_this_track}.wav')):
                    sampleRate, audioData = read(f'{TEMP}/{args.cut_by_this_track}.wav')
                else:
                    log.error('Audio track not found!')

        from cutting import audioToHasLoud, motionDetection

        audioList = None
        motionList = None
        if('audio' in args.edit_based_on):
            log.debug('Analyzing audio volume.')
            audioList = audioToHasLoud(audioData, sampleRate, args.silent_threshold, fps, log)

        if('motion' in args.edit_based_on):
            log.debug('Analyzing video motion.')
            motionList = motionDetection(INPUT_FILE, ffprobe, args.motion_threshold, log,
                width=400, dilates=2, blur=21)

            if(audioList is not None):
                if(len(audioList) > len(motionList)):
                    log.debug('Reducing the size of audioList to match motionList')
                    log.debug(f'audioList Length:  {len(audioList)}')
                    log.debug(f'motionList Length: {len(motionList)}')
                    audioList = audioList[:len(motionList)]

        from cutting import combineArrs, applySpacingRules

        hasLoud = combineArrs(audioList, motionList, args.edit_based_on, log)
        del audioList, motionList

        chunks, includeFrame = applySpacingRules(hasLoud, fps, args.frame_margin,
            args.min_clip_length, args.min_cut_length, args.ignore, args.cut_out, log)
        del hasLoud

        clips = []
        for chunk in chunks:
            if(speeds[chunk[2]] == 99999):
                numCuts += 1
            else:
                clips.append([chunk[0], chunk[1], speeds[chunk[2]] * 100])

        if(fps is None and not audioFile):
            if(makingDataFile):
                dotIndex = INPUT_FILE.rfind('.')
                end = '_constantFPS' + oldFile[dotIndex:]
                constantLoc = oldFile[:dotIndex] + end
            else:
                constantLoc = f'{TEMP}/constantVid{fileFormat}'
            cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-filter:v', 'fps=fps=30',
                constantLoc]
            cmd = ffAddDebug(cmd, log.is_ffmpeg)
            subprocess.call(cmd)
            INPUT_FILE = constantLoc

        if(args.preview):
            args.no_open = True
            from preview import preview

            preview(INPUT_FILE, chunks, speeds, fps, audioFile, log)
            continue

        if(args.export_to_premiere):
            args.no_open = True
            from premiere import exportToPremiere

            exportToPremiere(INPUT_FILE, TEMP, newOutput, clips, tracks, sampleRate,
                audioFile, log)
            continue
        if(args.export_to_resolve):
            args.no_open = True
            duration = chunks[len(chunks) - 1][1]
            from resolve import exportToResolve

            exportToResolve(INPUT_FILE, newOutput, clips, duration, sampleRate,
                audioFile, log)
            continue
        if(audioFile):
            from fastAudio import fastAudio, handleAudio

            theFile = handleAudio(ffmpeg, INPUT_FILE, audioBitrate, str(sampleRate),
                TEMP, log)
            fastAudio(theFile, newOutput, chunks, speeds, log, fps)
            continue

        from fastVideo import handleAudioTracks, fastVideo, muxVideo

        continueVid = handleAudioTracks(ffmpeg, newOutput, args.export_as_audio,
            tracks, args.keep_tracks_seperate, chunks, speeds, fps, TEMP, log)
        if(continueVid):
            fastVideo(INPUT_FILE, chunks, includeFrame, speeds, fps, TEMP, log)
            muxVideo(ffmpeg, newOutput, args.keep_tracks_seperate, tracks,
                args.video_bitrate, args.tune, args.preset, args.video_codec,
                TEMP, log)

    if(not os.path.isfile(newOutput)):
        log.error(f'The file {newOutput} was not created.')

    if(not args.preview and not makingDataFile):
        timer.stop()

    if(not args.preview and makingDataFile):
        from usefulFunctions import humanReadableTime
        # Assume making each cut takes about 2 seconds.
        timeSave = humanReadableTime(numCuts * 2)

        s = 's' if numCuts != 1 else ''
        print(f'Auto-Editor made {numCuts} cut{s}', end='')
        if(numCuts > 4):
            print(f', which would have taken about {timeSave} if edited manually.')
        else:
            print('.')

    if(not args.no_open):
        from usefulFunctions import smartOpen
        smartOpen(newOutput, log)

    rmtree(TEMP)

if(__name__ == '__main__'):
    main()
