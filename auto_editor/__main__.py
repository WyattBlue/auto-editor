#!/usr/bin/env python3
'''__main__.py'''

# Internal python libraries
import os
import re
import sys
import time
import argparse
import platform
import tempfile
import subprocess
from shutil import rmtree
from datetime import timedelta

version = '20w32a'

def file_type(file):
    if(not os.path.isfile(file)):
        print('Error! Could not locate file:', file)
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

def ffmpegFPS(ffmpeg, path):
    output = pipeToConsole([ffmpeg, '-i', path])
    try:
        matchDict = re.search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
        return float(matchDict['fps'])
    except AttributeError:
        print('Warning! frame rate detection failed.')
        print('If your video has a variable frame rate, ignore this message.')
        return None

def main():
    parser = argparse.ArgumentParser(prog='Auto-Editor', usage='auto-editor [input] [options]')

    basic = parser.add_argument_group('Basic Options')
    basic.add_argument('input', nargs='*',
        help='the path to the file(s), folder, or url you want edited.')
    basic.add_argument('--frame_margin', '-m', type=int, default=6, metavar='',
        help='set how many "silent" frames of on either side of "loud" sections be included.')
    basic.add_argument('--silent_threshold', '-t', type=float_type, default=0.04, metavar='',
        help='set the volume that frames audio needs to surpass to be "loud". (0-1)')
    basic.add_argument('--video_speed', '--sounded_speed', '-v', type=float_type, default=1.00, metavar='',
        help='set the speed that "loud" sections should be played at.')
    basic.add_argument('--silent_speed', '-s', type=float_type, default=99999, metavar='',
        help='set the speed that "silent" sections should be played at.')
    basic.add_argument('--output_file', '-o', nargs='*', metavar='',
        help='set the name(s) of the new output.')

    advance = parser.add_argument_group('Advanced Options')
    advance.add_argument('--no_open', action='store_true',
        help='do not open the file after editing is done.')
    advance.add_argument('--min_clip_length', '-mclip', type=int, default=3, metavar='',
        help='set the minimum length a clip can be. If a clip is too short, cut it.')
    advance.add_argument('--min_cut_length', '-mcut', type=int, default=6, metavar='',
        help="set the minimum length a cut can be. If a cut is too short, don't cut")
    advance.add_argument('--combine_files', action='store_true',
        help='combine all input files into one before editing.')
    advance.add_argument('--video_codec', '-vcodec', default='copy', metavar='',
        help='(for exporting video only) set the video codec for the output file.')

    audio = parser.add_argument_group('Audio Options')
    audio.add_argument('--audio_bitrate', type=str, default='160k', metavar='',
        help='set the number of bits per second for audio.')

    cutting = parser.add_argument_group('Cutting Options')
    cutting.add_argument('--cut_by_this_audio', '-ca', type=file_type, metavar='',
        help="base cuts by this audio file instead of the video's audio.")
    cutting.add_argument('--cut_by_this_track', '-ct', type=int, default=0, metavar='',
        help='base cuts by a different audio track in the video.')
    cutting.add_argument('--cut_by_all_tracks', '-cat', action='store_true',
        help='combine all audio tracks into one before basing cuts.')
    cutting.add_argument('--keep_tracks_seperate', action='store_true',
        help="don't combine audio tracks when exporting.")

    debug = parser.add_argument_group('Developer/Debugging Options')
    debug.add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    debug.add_argument('--version', action='store_true',
        help='show which auto-editor you have.')
    debug.add_argument('--debug', '--verbose', action='store_true',
        help='show helpful debugging values.')

    misc = parser.add_argument_group('Export Options')
    misc.add_argument('--preview', action='store_true',
        help='show stats on how the input will be cut.')
    misc.add_argument('--export_to_premiere', '-exp', action='store_true',
        help='export as an XML file for Adobe Premiere Pro instead of outputting a media file.')
    misc.add_argument('--export_to_resolve', '-exr', action='store_true',
        help='export as an XML file for DaVinci Resolve instead of outputting a media file.')

    dep = parser.add_argument_group('Deprecated Options')
    dep.add_argument('--clear_cache', action='store_true',
        help='delete the cache folder and all its contents.')
    dep.add_argument('--hardware_accel', type=str, metavar='',
        help='set the hardware used for gpu acceleration.')
    dep.add_argument('--sample_rate', '-r', type=sample_rate_type, default=48000, metavar='',
        help='set the sample rate of the input and output videos.')

    args = parser.parse_args()

    dirPath = os.path.dirname(os.path.realpath(__file__))
    # fixes pip not able to find other included modules.
    sys.path.append(os.path.abspath(dirPath))

    if(args.version):
        print('Auto-Editor version', version)
        sys.exit()

    if(args.clear_cache):
        cache = os.path.join(dirPath, 'cache')
        if(os.path.isdir(cache)):
            rmtree(cache)
        print('Removed cache.')
        if(args.input == []):
            sys.exit()

    newF = None
    if(platform.system() == 'Windows' and not args.my_ffmpeg):
        newF = os.path.join(dirPath, 'win-ffmpeg/bin/ffmpeg.exe')
    if(platform.system() == 'Darwin' and not args.my_ffmpeg):
        newF = os.path.join(dirPath, 'mac-ffmpeg/bin/ffmpeg')
    if(newF is not None and os.path.isfile(newF)):
        ffmpeg = newF
    else:
        ffmpeg = 'ffmpeg'

    makingDataFile = args.export_to_premiere or args.export_to_resolve

    if(args.hardware_accel is not None):
        output = pipeToConsle([ffmpeg, '-hwaccels', '-hide_banner'])
        output = output.replace('Hardware acceleration methods:', '')
        output = output.replace('\n', '')
        hwaccels = output.split(',')
        if(args.hardware_accel not in hwaccels):
            print('Error! Invalid hardware accel:', args.hardware_accel)
            print('Available hardware:', ' '.join(hwaccels))
            sys.exit(1)

    if(args.debug):
        is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'
        print('Python Version:', platform.python_version(), is64bit)
        # platform can be 'Linux', 'Darwin' (macOS), 'Java', 'Windows'
        print('Platform:', platform.system())
        print('FFmpeg path:', ffmpeg)
        print('Auto-Editor version', version)
        if(args.input == []):
            sys.exit()

    if(args.input == []):
        print('Error! The following arguments are required: input')
        print('In other words, you need the path to a video or an audio file so that auto-editor can do the work for you.')
        sys.exit(1)

    if(args.silent_speed <= 0 or args.silent_speed > 99999):
        args.silent_speed = 99999
    if(args.video_speed <= 0 or args.video_speed > 99999):
        args.video_speed = 99999

    inputList = []
    for myInput in args.input:
        if(os.path.isdir(myInput)):
            inputList += sort(os.listdir(myInput))
        elif(os.path.isfile(myInput)):
            inputList.append(myInput)
        elif(myInput.startswith('http://') or myInput.startswith('https://')):
            print('URL detected, using youtube-dl to download from webpage.')
            basename = re.sub(r'\W+', '-', myInput)
            cmd = ['youtube-dl', '-f', 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4',
                   myInput, '--output', basename, '--no-check-certificate']
            if(ffmpeg != 'ffmpeg'):
                cmd.extend(['--ffmpeg-location', ffmpeg])
            subprocess.call(cmd)
            inputList.append(basename + '.mp4')
        else:
            print('Error! Could not find file:', myInput)
            sys.exit(1)

    if(args.output_file is None):
        args.output_file = []

    if(len(args.output_file) < len(inputList)):
        for i in range(len(inputList) - len(args.output_file)):
            oldFile = inputList[i]
            dotIndex = oldFile.rfind('.')
            if(args.export_to_premiere or args.export_to_resolve):
                args.output_file.append(oldFile[:dotIndex] + '.xml')
            else:
                end = '_ALTERED' + oldFile[dotIndex:]
                args.output_file.append(oldFile[:dotIndex] + end)

    if(args.combine_files):
        with open(f'{TEMP}/combines.txt', 'w') as outfile:
            for fileref in inputList:
                outfile.write(f"file '{fileref}'\n")

        cmd = [ffmpeg, '-f', 'concat', '-safe', '0', '-i', f'{TEMP}/combines.txt',
            '-c', 'copy', 'combined.mp4']
        subprocess.call(cmd)
        inputList = ['combined.mp4']

    TEMP = tempfile.mkdtemp()
    speeds = [args.silent_speed, args.video_speed]

    startTime = time.time()

    from usefulFunctions import isAudioFile, vidTracks, conwrite, getAudioChunks
    from wavfile import read, write

    for i, INPUT_FILE in enumerate(inputList):
        newOutput = args.output_file[i]
        fileFormat = INPUT_FILE[INPUT_FILE.rfind('.'):]

        if(isAudioFile(INPUT_FILE)):
            fps = 30
            cmd = [ffmpeg, '-i', myInput, '-b:a', args.audio_bitrate, '-ac', '2', '-ar',
                str(args.sample_rate), '-vn', f'{TEMP}/fastAud.wav', '-nostats',
                '-loglevel', '0']
            subprocess.call(cmd)

            sampleRate, audioData = read(f'{TEMP}/fastAud.wav')
        else:
            fps = ffmpegFPS(ffmpeg, INPUT_FILE)
            tracks = vidTracks(INPUT_FILE, ffmpeg)

            if(args.cut_by_this_track >= tracks):
                print("Error! You choose a track that doesn't exist.")
                print(f'There are only {tracks-1} tracks. (starting from 0)')
                sys.exit(1)

            for trackNum in range(tracks):
                cmd = [ffmpeg, '-i', INPUT_FILE, '-ab', args.audio_bitrate, '-ac', '2',
                '-ar', str(args.sample_rate), '-map', f'0:a:{trackNum}',
                f'{TEMP}/{trackNum}.wav']
                if(args.debug):
                    cmd.extend(['-hide_banner'])
                else:
                    cmd.extend(['-nostats', '-loglevel', '0'])
                subprocess.call(cmd)

            if(args.cut_by_all_tracks):
                cmd = [ffmpeg, '-i', INPUT_FILE, '-ab', args.audio_bitrate, '-ac', '2', '-ar',
                str(args.sample_rate),'-map', '0', f'{TEMP}/combined.wav']
                if(args.debug):
                    cmd.extend(['-hide_banner'])
                else:
                    cmd.extend(['-nostats', '-loglevel', '0'])
                subprocess.call(cmd)

                sampleRate, audioData = read(f'{TEMP}/combined.wav')
            else:
                sampleRate, audioData = read(f'{TEMP}/{args.cut_by_this_track}.wav')

        chunks = getAudioChunks(audioData, sampleRate, fps, args.silent_threshold,
            args.frame_margin, args.min_clip_length, args.min_cut_length)

        if(fps is None and not isAudioFile(INPUT_FILE)):
            if(makingDataFile):
                dotIndex = INPUT_FILE.rfind('.')
                end = '_constantFPS' + oldFile[dotIndex:]
                constantLoc = oldFile[:dotIndex] + end
            else:
                constantLoc = f'{TEMP}/constantVid{fileFormat}'
            cmd = [ffmpeg, '-i', INPUT_FILE, '-filter:v', f'fps=fps=30',
                constantLoc, '-hide_banner']
            if(args.debug):
                cmd.extend(['-hide_banner'])
            else:
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)
            INPUT_FILE = constancLoc

        if(args.preview):
            args.no_open = True
            from preview import preview

            preview(INPUT_FILE, chunks, speeds, args.debug)
            continue

        if(args.export_to_premiere):
            args.no_open = True
            from premiere import exportToPremiere

            exportToPremiere(INPUT_FILE, newOutput, chunks, speeds, sampleRate)
            continue
        if(args.export_to_resolve):
            args.no_open = True
            from resolve import exportToResolve

            exportToResolve(INPUT_FILE, newOutput, chunks, speeds, sampleRate)
            continue
        if(isAudioFile(INPUT_FILE) and not makingDataFile):
            from fastAudio import fastAudio

            fastAudio(ffmpeg, INPUT_FILE, newOutput, chunks, speeds, args.audio_bitrate,
            sampleRate, args.debug, True)
            continue

        from fastVideo import fastVideo
        fastVideo(ffmpeg, INPUT_FILE, newOutput, chunks, speeds, tracks,
            args.audio_bitrate, sampleRate, args.debug, TEMP,
            args.keep_tracks_seperate, args.video_codec, fps)

    if(not os.path.isfile(newOutput)):
        print(f'Error! The file {newOutput} was not created.')
        sys.exit(1)

    if(not args.preview and makingDataFile):
        print('Finished.')
        timeLength = round(time.time() - startTime, 2)
        minutes = timedelta(seconds=round(timeLength))
        print(f'took {timeLength} seconds ({minutes})')

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
                    print('Warning! Could not open output file.')
    rmtree(TEMP)

if(__name__ == '__main__'):
    main()
