#!/usr/bin/env python3
'''__main__.py'''

# Internal python libraries
import os
import re
import sys
import time
import difflib
import platform
import tempfile
import subprocess
from shutil import rmtree
from datetime import timedelta

version = '20w47a'

def file_type(file):
    if(not os.path.isfile(file)):
        print('Auto-Editor could not find the file: ' + file)
        sys.exit(1)
    return file

def float_type(num):
    if(num.endswith('%')):
        return float(num[:-1]) / 100
    return float(num)

def sample_rate_type(num):
    if(num.endswith(' Hz')):
        return int(num[:-3])
    if(num.endswith(' kHz')):
        return int(float(num[:-4]) * 1000)
    return int(num)

def pipeToConsole(myCommands):
    process = subprocess.Popen(myCommands, stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    return stdout.decode()

def ffmpegFPS(ffmpeg, path, log):
    output = pipeToConsole([ffmpeg, '-i', path, '-hide_banner'])
    try:
        matchDict = re.search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
        return float(matchDict['fps'])
    except AttributeError:
        log.warning('frame rate detection failed.\n' \
            'If your video has a variable frame rate, ignore this message.')
        return 30

def main():
    options = []
    option_names = []

    def add_argument(*names, nargs=1, type=str, default=None,
        action='default', range=None, choices=None, help='', extra=''):
        nonlocal options
        nonlocal option_names

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
        option_names = option_names + list(names)

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
    add_argument('--motion_threshold', type=float_type, default=0.04, range='0 to 1',
        help='how much motion is required to be considered "moving"')
    add_argument('--edit_based_on', default='audio',
        choices=['audio', 'motion', 'audio_or_motion', 'audio_and_motion',
            'audio_xor_motion', 'audio_and_not_motion'],
        help='decide if to use audio/motion to consider when making edits.')

    dirPath = os.path.dirname(os.path.realpath(__file__))
    # Fixes pip not able to find other included modules.
    sys.path.append(os.path.abspath(dirPath))

    from usefulFunctions import Log

    audioExtensions = ['.wav', '.mp3', '.m4a', '.aiff', '.flac', '.ogg', '.oga', '.acc', '.nfa', '.mka']

    invalidExtensions = ['.txt', '.md', '.rtf', '.csv', '.cvs', '.html', '.htm', '.xml', '.json', '.yaml', '.png',
        '.jpeg', '.jpg', '.gif', '.exe', '.doc', '.docx', '.odt', '.pptx', '.xlsx', '.xls', 'ods', '.pdf', '.bat',
        '.dll', '.prproj', '.psd', '.aep', '.zip', '.rar', '.7z', '.java', '.class', '.js', '.c', '.cpp',
        '.csharp', '.py', '.app', '.git', '.github', '.gitignore', '.db', '.ini', '.BIN']

    class parse_options():
        def __init__(self, userArgs, log, *args):
            # Set the default options.
            for options in args:
                for option in options:
                    key = option['names'][0].replace('-', '')
                    if(option['action'] == 'store_true'):
                        value = False
                    elif(option['nargs'] != 1):
                        value = []
                    else:
                        value = option['default']
                    setattr(self, key, value)

            def get_option(item, the_args):
                for options in the_args:
                    for option in options:
                        if(item in option['names']):
                            return option
                return None

            # Figure out attributes changed by user.
            myList = []
            settingInputs = True
            optionList = 'input'
            i = 0
            while i < len(userArgs):
                item = userArgs[i]
                if(i == len(userArgs) - 1):
                    nextItem = None
                else:
                    nextItem = userArgs[i+1]

                option = get_option(item, args)

                if(option is not None):
                    if(optionList is not None):
                        setattr(self, optionList, myList)
                    settingInputs = False
                    optionList = None
                    myList = []

                    key = option['names'][0].replace('-', '')

                    # Show help for specific option.
                    if(nextItem == '-h' or nextItem == '--help'):
                        print(' ', ', '.join(option['names']))
                        print('   ', option['help'])
                        print('   ', option['extra'])
                        if(option['action'] == 'default'):
                            print('    type:', option['type'].__name__)
                            print('    default:', option['default'])
                            if(option['range'] is not None):
                                print('    range:', option['range'])
                            if(option['choices'] is not None):
                                print('    choices:', ', '.join(option['choices']))
                        else:
                            print(f'    type: flag')
                        sys.exit()

                    if(option['nargs'] != 1):
                        settingInputs = True
                        optionList = key
                    elif(option['action'] == 'store_true'):
                        value = True
                    else:
                        try:
                            # Convert to correct type.
                            value = option['type'](nextItem)
                        except:
                            typeName = option['type'].__name__
                            log.error(f'Couldn\'t convert "{nextItem}" to {typeName}')
                        if(option['choices'] is not None):
                            if(value not in option['choices']):
                                optionName = option['names'][0]
                                myChoices = ', '.join(option['choices'])
                                log.error(f'{value} is not a choice for {optionName}' \
                                    f'\nchoices are:\n  {myChoices}')
                        i += 1
                    setattr(self, key, value)
                else:
                    if(settingInputs and not item.startswith('-')):
                        # Input file names
                        myList.append(item)
                    else:
                        # Unknown Option!
                        hmm = difflib.get_close_matches(item, option_names)
                        potential_options = ', '.join(hmm)
                        append = ''
                        if(hmm != []):
                            append = f'\n\n    Did you mean:\n        {potential_options}'
                        log.error(f'Unknown option: {item}{append}')
                i += 1
            if(settingInputs):
                setattr(self, optionList, myList)

    args = parse_options(sys.argv[1:], Log(3), options)

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

    from usefulFunctions import vidTracks, conwrite
    from wavfile import read, write

    if(not args.preview):
        if(args.export_to_premiere):
            conwrite('Exporting to Adobe Premiere Pro XML file.')
        elif(args.export_to_resolve):
            conwrite('Exporting to DaVinci Resolve XML file.')
        elif(args.export_as_audio):
            conwrite('Exporting as audio.')
        else:
            conwrite('Starting.')

    newF = None
    newP = None
    if(platform.system() == 'Windows' and not args.my_ffmpeg):
        newF = os.path.join(dirPath, 'win-ffmpeg/bin/ffmpeg.exe')
        newP = os.path.join(dirPath, 'win-ffmpeg/bin/ffprobe.exe')
    if(platform.system() == 'Darwin' and not args.my_ffmpeg):
        newF = os.path.join(dirPath, 'mac-ffmpeg/bin/ffmpeg')
        newP = os.path.join(dirPath, 'mac-ffmpeg/bin/ffprobe')
    if(newF is not None and os.path.isfile(newF)):
        ffmpeg = newF
        ffprobe = newP
    else:
        ffmpeg = 'ffmpeg'
        ffprobe = 'ffprobe'

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
        log.debug('Check for update Error: ' + str(err))

    if(args.silent_speed <= 0 or args.silent_speed > 99999):
        args.silent_speed = 99999
    if(args.video_speed <= 0 or args.video_speed > 99999):
        args.video_speed = 99999

    inputList = []
    for myInput in args.input:
        if(os.path.isdir(myInput)):
            def validFiles(path, badExts):
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

    startTime = time.time()

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
        if(log.ffmpeg):
            cmd.extend(['-hide_banner'])
        else:
            cmd.extend(['-nostats', '-loglevel', '8'])

        subprocess.call(cmd)
        inputList = [f'{TEMP}/combined.mp4']

    speeds = [args.silent_speed, args.video_speed]
    numCuts = 0
    for i, INPUT_FILE in enumerate(inputList):
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

        audioFile = fileFormat in audioExtensions

        # Get output file name.
        newOutput = args.output_file[i]

        # Grab the sample rate from the input.
        sr = args.sample_rate
        if(sr is None):
            output = pipeToConsole([ffmpeg, '-i', INPUT_FILE, '-hide_banner'])
            try:
                matchDict = re.search(r'\s(?P<grp>\w+?)\sHz', output).groupdict()
                sr = matchDict['grp']
            except AttributeError:
                sr = 48000
        args.sample_rate = sr

        # Grab the audio bitrate from the input.
        abit = args.audio_bitrate
        if(abit is None):
            if(not INPUT_FILE.endswith('.mkv')):
                output = pipeToConsole([ffprobe, '-v', 'error', '-select_streams',
                    'a:0', '-show_entries', 'stream=bit_rate', '-of',
                    'compact=p=0:nk=1', INPUT_FILE])
                try:
                    abit = int(output)
                except:
                    log.warning("Couldn't automatically detect audio bitrate.")
                    abit = '500k'
                    log.debug('Setting audio bitrate to ' + abit)
                else:
                    abit = str(round(abit / 1000)) + 'k'
        else:
            abit = str(abit)
        args.audio_bitrate = abit

        if(audioFile):
            fps = 30 # Audio files don't have frames, so give fps a dummy value.
            tracks = 1
            cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-b:a', args.audio_bitrate, '-ac', '2',
                '-ar', str(args.sample_rate), '-vn', f'{TEMP}/fastAud.wav']
            if(log.ffmpeg):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '8'])
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
                log.error("You choose a track that doesn't exist.\n" \
                    f'There are only {tracks-1} tracks. (starting from 0)')

            vcodec = args.video_codec
            if(vcodec == 'copy'):
                output = pipeToConsole([ffmpeg, '-i', INPUT_FILE, '-hide_banner'])
                try:
                    matchDict = re.search(r'Video:\s(?P<video>\w+?)\s', output).groupdict()
                    vcodec = matchDict['video']
                    log.debug(vcodec)
                except AttributeError:
                    vcodec = 'uncompressed'
                    log.warning("Couldn't automatically detect video codec.")

            if(args.video_bitrate is not None and vcodec == 'uncompressed'):
                log.warning('Your bitrate will not be applied because' \
                        ' the video codec is "uncompressed".')

            if(vcodec == 'uncompressed'):
                # FFmpeg copies the uncompressed output that cv2 spits out.
                vcodec = 'copy'

            # Split audio tracks into: 0.wav, 1.wav, etc.
            for trackNum in range(tracks):
                cmd = [ffmpeg, '-y', '-i', INPUT_FILE]
                if(args.audio_bitrate is not None):
                    cmd.extend(['-ab', args.audio_bitrate])

                cmd.extend(['-ac', '2', '-ar', str(args.sample_rate), '-map',
                    f'0:a:{trackNum}', f'{TEMP}/{trackNum}.wav'])

                if(log.is_ffmpeg):
                    cmd.extend(['-hide_banner'])
                else:
                    cmd.extend(['-nostats', '-loglevel', '8'])
                subprocess.call(cmd)

            # Check if the `--cut_by_all_tracks` flag has been set or not.
            if(args.cut_by_all_tracks):
                # Combine all audio tracks into one audio file, then read.
                cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-filter_complex',
                    f'[0:a]amerge=inputs={tracks}', '-map', 'a', '-ar',
                    str(args.sample_rate), '-ac', '2', '-f', 'wav', f'{TEMP}/combined.wav']
                if(log.is_ffmpeg):
                    cmd.extend(['-hide_banner'])
                else:
                    cmd.extend(['-nostats', '-loglevel', '8'])

                subprocess.call(cmd)

                sampleRate, audioData = read(f'{TEMP}/combined.wav')
            else:
                # Read only one audio file.
                if(os.path.isfile(f'{TEMP}/{args.cut_by_this_track}.wav')):
                    sampleRate, audioData = read(f'{TEMP}/{args.cut_by_this_track}.wav')
                else:
                    log.error('Audio track not found!')

        from cutting import audioToHasLoud, motionDetection, applySpacingRules
        import numpy as np

        audioList = None
        motionList = None
        if(args.edit_based_on != 'motion'):
            log.debug('Analyzing audio volume.')
            audioList = audioToHasLoud(audioData, sampleRate, args.silent_threshold, fps, log)

        if(args.edit_based_on != 'audio'):
            log.debug('Analyzing video motion.')
            motionList = motionDetection(INPUT_FILE, ffprobe, args.motion_threshold, log,
                width=400, dilates=2, blur=True)

            if(audioList is not None):
                if(len(audioList) > len(motionList)):
                    log.debug('Reducing the size of audioList to match motionList')
                    log.debug(f'audioList Length:  {len(audioList)}')
                    log.debug(f'motionList Length: {len(motionList)}')
                    audioList = audioList[:len(motionList)]

        if(args.edit_based_on == 'audio'):
            hasLoud = audioList
            if(max(audioList) == 0):
                log.error('There was no place where audio exceeded the threshold.')
        if(args.edit_based_on == 'motion'):
            hasLoud = motionList
            if(max(motionList) == 0):
                log.error('There was no place where motion exceeded the threshold.')

        # Only raise a warning for other cases.
        if(audioList is not None and max(audioList) == 0):
            log.warning('There was no place where audio exceeded the threshold.')
        if(motionList is not None and max(motionList) == 0):
            log.warning('There was no place where motion exceeded the threshold.')

        if(args.edit_based_on == 'audio_and_motion'):
            log.debug('Applying "Python bitwise and" on arrays.')
            hasLoud = audioList & motionList

        if(args.edit_based_on == 'audio_or_motion'):
            log.debug('Applying "Python bitwise or" on arrays.')
            hasLoud = audioList | motionList

        if(args.edit_based_on == 'audio_xor_motion'):
            log.debug('Applying "numpy bitwise_xor" on arrays')
            hasLoud = np.bitwise_xor(audioList, motionList)

        if(args.edit_based_on == 'audio_and_not_motion'):
            log.debug('Applying "Python bitwise and" with "numpy bitwise not" on arrays.')
            hasLoud = audioList & np.invert(motionList)

        chunks, includeFrame = applySpacingRules(hasLoud, fps, args.frame_margin,
            args.min_clip_length, args.min_cut_length, args.ignore, args.cut_out, log)

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
            cmd = [ffmpeg, '-y', '-i', INPUT_FILE, '-filter:v', f'fps=fps=30', constantLoc]
            if(log.is_ffmpeg):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '8'])
            subprocess.call(cmd)
            INPUT_FILE = constancLoc

        if(args.preview):
            args.no_open = True
            from preview import preview

            preview(INPUT_FILE, chunks, speeds, fps, audioFile, log)
            continue

        if(args.export_to_premiere):
            args.no_open = True
            from premiere import exportToPremiere

            exportToPremiere(INPUT_FILE, TEMP, newOutput, clips, tracks, sampleRate, audioFile, log)
            continue
        if(args.export_to_resolve):
            args.no_open = True
            duration = chunks[len(chunks) - 1][1]
            from resolve import exportToResolve

            exportToResolve(INPUT_FILE, newOutput, clips, duration, sampleRate, audioFile, log)
            continue
        if(audioFile and not makingDataFile):
            from fastAudio import fastAudio

            fastAudio(ffmpeg, INPUT_FILE, newOutput, chunks, speeds, args.audio_bitrate,
                sampleRate, True, TEMP, log)
            continue

        from fastVideo import fastVideo
        fastVideo(ffmpeg, INPUT_FILE, newOutput, chunks, includeFrame, speeds, tracks,
            args.audio_bitrate, sampleRate, TEMP, args.keep_tracks_seperate, vcodec, fps,
            args.export_as_audio, args.video_bitrate, args.preset, args.tune, log)

    if(not os.path.isfile(newOutput)):
        log.error(f'The file {newOutput} was not created.')

    if(not args.preview and not makingDataFile):
        timeLength = round(time.time() - startTime, 2)
        minutes = timedelta(seconds=round(timeLength))
        print(f'Finished. took {timeLength} seconds ({minutes})')

    if(not args.preview and makingDataFile):
        timeSave = numCuts * 2 # assuming making each cut takes about 2 seconds.
        units = 'seconds'
        if(timeSave >= 3600):
            timeSave = round(timeSave / 3600, 1)
            if(timeSave % 1 == 0):
                timeSave = round(timeSave)
            units = 'hours'
        if(timeSave >= 60):
            timeSave = round(timeSave / 60, 1)
            if(timeSave >= 10 or timeSave % 1 == 0):
                timeSave = round(timeSave)
            units = 'minutes'

        plural = 's' if numCuts != 1 else ''

        print(f'Auto-Editor made {numCuts} cut{plural}', end='') # Don't add a newline.
        if(numCuts > 4):
            print(f', which would have taken about {timeSave} {units} if edited manually.')
        else:
            print('.')

    if(not args.no_open):
        try:  # should work on Windows
            os.startfile(newOutput)
        except AttributeError:
            try:  # should work on MacOS and most Linux versions
                subprocess.call(['open', newOutput])
            except:
                try: # should work on WSL2
                    subprocess.call(['cmd.exe', '/C', 'start', newOutput])
                except:
                    log.warning('Could not open output file.')
    rmtree(TEMP)

if(__name__ == '__main__'):
    main()
