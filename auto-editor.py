#!/usr/bin/env python3
'''auto-editor.py'''

# Internal python libraries
import os
import re
import sys
import time
import platform
import argparse
import subprocess
from shutil import rmtree
from datetime import timedelta
from operator import itemgetter

version = '20w29b'

# Files that start with . are hidden, but can be viewed by running "ls -f" from console.
TEMP = '.TEMP'
CACHE = '.CACHE'

def file_type(file):
    if(not os.path.isfile(file)):
        print('Could not locate file:', file)
        sys.exit(1)
    return file

def float_type(num):
    if(num.endswith('%')):
        num = float(num[:-1]) / 100
    else:
        num = float(num)
    return num

def sample_rate_type(num):
    if(num.endswith(' Hz')):
        num = int(num[:-3])
    elif(num.endswith(' kHz')):
        num = int(float(num[:-4]) * 1000)
    else:
        num = int(num)
    return num

if(__name__ == '__main__'):
    parser = argparse.ArgumentParser(prog='Auto-Editor', usage='Auto-Editor: [options]')

    basic = parser.add_argument_group('Basic Options')
    basic.add_argument('input', nargs='*',
        help='the path to the file, folder, or url you want edited.')
    basic.add_argument('--frame_margin', '-m', type=int, default=4, metavar='',
        help='set how many "silent" frames of on either side of "loud" sections be included.')
    basic.add_argument('--silent_threshold', '-t', type=float_type, default=0.04, metavar='',
        help='set the volume that frames audio needs to surpass to be sounded. (0-1)')
    basic.add_argument('--video_speed', '--sounded_speed', '-v', type=float_type, default=1.00, metavar='',
        help='set the speed that "loud" sections should be played at.')
    basic.add_argument('--silent_speed', '-s', type=float_type, default=99999, metavar='',
        help='set the speed that "silent" sections should be played at.')
    basic.add_argument('--output_file', '-o', type=str, default='', metavar='',
        help='set the name of the new output.')

    advance = parser.add_argument_group('Advanced Options')
    advance.add_argument('--no_open', action='store_true',
        help='do not open the file after editing is done.')
    advance.add_argument('--zoom_threshold', type=float_type, default=1.01, metavar='',
        help='set the volume that needs to be surpassed to zoom in the video. (0-1)')
    advance.add_argument('--combine_files', action='store_true',
        help='when using a folder as the input, combine all files in a folder before editing.')
    advance.add_argument('--hardware_accel', type=str, metavar='',
        help='set the hardware used for gpu acceleration.')

    audio = parser.add_argument_group('Audio Options')
    audio.add_argument('--sample_rate', '-r', type=sample_rate_type, default=48000, metavar='',
        help='set the sample rate of the input and output videos.')
    audio.add_argument('--audio_bitrate', type=str, default='160k', metavar='',
        help='set the number of bits per second for audio.')
    audio.add_argument('--background_music', type=file_type, metavar='',
        help='set an audio file to be added as background music to your output.')
    audio.add_argument('--background_volume', type=float, default=-8, metavar='',
        help="set the dBs louder or softer compared to the audio track that bases the cuts.")

    cutting = parser.add_argument_group('Cutting Options')
    cutting.add_argument('--cut_by_this_audio', type=file_type, metavar='',
        help="base cuts by this audio file instead of the video's audio.")
    cutting.add_argument('--cut_by_this_track', '-ct', type=int, default=0, metavar='',
        help='base cuts by a different audio track in the video.')
    cutting.add_argument('--cut_by_all_tracks', action='store_true',
        help='combine all audio tracks into one before basing cuts.')
    cutting.add_argument('--keep_tracks_seperate', action='store_true',
        help="don't combine audio tracks. mutually exclusive with cut_by_all_tracks.")

    debug = parser.add_argument_group('Developer/Debugging Options')
    debug.add_argument('--clear_cache', action='store_true',
        help='delete the cache folder and all its contents.')
    debug.add_argument('--my_ffmpeg', action='store_true',
        help='use your ffmpeg and other binaries instead of the ones packaged.')
    debug.add_argument('--version', action='store_true',
        help='show which auto-editor you have.')
    debug.add_argument('--debug', '--verbose', action='store_true',
        help='show helpful debugging values.')

    misc = parser.add_argument_group('Export Options')
    misc.add_argument('--preview', action='store_true',
        help='show stats on how the input will be cut.')
    misc.add_argument('--export_to_premiere', action='store_true',
        help='export as an XML file for Adobe Premiere Pro instead of outputting a media file.')

    #dep = parser.add_argument_group('Deprecated Options')

    args = parser.parse_args()

    if(args.version):
        print('Auto-Editor version:', version)
        sys.exit()

    if(args.clear_cache):
        print('Removing cache')
        if(os.path.isdir(CACHE)):
            rmtree(CACHE)
        if(os.path.isdir(TEMP)):
            rmtree(TEMP)
        if(args.input == []):
            sys.exit()

    # Set the file path to the ffmpeg installation.
    dirPath = os.path.dirname(os.path.realpath(__file__))
    ffmpeg = 'ffmpeg'
    if(platform.system() == 'Windows' and not args.my_ffmpeg):

        if(os.path.isfile(os.path.join(dirPath, 'scripts/win-ffmpeg/bin/ffmpeg.exe'))):
            ffmpeg = os.path.join(dirPath, 'scripts/win-ffmpeg/bin/ffmpeg.exe')

    if(platform.system() == 'Darwin' and not args.my_ffmpeg):
        newF = os.path.join(dirPath, 'scripts/mac-ffmpeg/unix-ffmpeg')
        binPath = os.path.join(dirPath, 'scripts/mac-ffmpeg.7z')

        if(os.path.isfile(newF)):
            ffmpeg = newF
        elif(os.path.isfile(binPath)):
            print('Unzipping folder with ffmpeg binaries.')

            # Use default program to extract the files.
            subprocess.call(['open', str(binPath)])
            while not os.path.exists(newF):
                time.sleep(0.5)
            ffmpeg = newF

    if(args.debug):
        is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'
        print('Python Version:', platform.python_version(), is64bit)
        # platform can be 'Linux', 'Darwin' (macOS), 'Java', 'Windows'
        # more here: https://docs.python.org/3/library/platform.html#platform.system
        print('Platform:', platform.system())
        print('FFmpeg:', ffmpeg)
        print('Auto-Editor Version:', version)
        if(args.input == []):
            sys.exit()

    if(args.input == []):
        print('auto-editor.py: error: the following arguments are required: input')
        sys.exit(1)

    INPUT_FILE = args.input[0]
    OUTPUT_FILE = args.output_file

    if(args.silent_speed <= 0 or args.silent_speed > 99999):
        args.silent_speed = 99999
    if(args.video_speed <= 0 or args.video_speed > 99999):
        args.video_speed = 99999

    if(os.path.isdir(INPUT_FILE)):
        # Get the file path and date modified so that it can be sorted later.
        INPUTS = []
        for filename in os.listdir(INPUT_FILE):
            if(not filename.startswith('.')):
                dic = {}
                dic['file'] = os.path.join(INPUT_FILE, filename)
                dic['time'] = os.path.getmtime(dic['file'])

                INPUTS.append(dic)

        # Sort the list by the key 'time'.
        newlist = sorted(INPUTS, key=itemgetter('time'), reverse=False)
        # Then reduce to a list that only has strings.
        INPUTS = []
        for item in newlist:
            INPUTS.append(item['file'])

        if(args.combine_files):
            outputDir = ''

            with open('combine_files.txt', 'w') as outfile:
                for fileref in INPUTS:
                    outfile.write(f"file '{fileref}'\n")

            cmd = [ffmpeg, '-f', 'concat', '-safe', '0', '-i', 'combine_files.txt',
                '-c', 'copy', 'combined.mp4']
            subprocess.call(cmd)

            INPUTS = ['combined.mp4']

            os.remove('combine_files.txt')
        else:
            outputDir = INPUT_FILE + '_ALTERED'
            # Create the new folder for all the outputs.
            try:
                os.mkdir(outputDir)
            except OSError:
                rmtree(outputDir)
                os.mkdir(outputDir)
    else:
        if(args.combine_files):
            print('Warning! --combine_files does nothing since input is not a folder.')
        outputDir = ''
        if(os.path.isfile(INPUT_FILE)):
            INPUTS = [INPUT_FILE]
        elif(INPUT_FILE.startswith('http://') or INPUT_FILE.startswith('https://')):
            # If input is a URL, download as a mp4 with youtube-dl.
            print('URL detected, using youtube-dl to download from webpage.')
            basename = re.sub(r'\W+', '-', INPUT_FILE)
            cmd = ["youtube-dl", "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4",
                   INPUT_FILE, "--output", basename]
            subprocess.call(cmd)

            INPUT_FILE = basename + '.mp4'
            INPUTS = [INPUT_FILE]
            if(OUTPUT_FILE == ''):
                OUTPUT_FILE = basename + '_ALTERED.mp4'
        else:
            print('Could not find file:', INPUT_FILE)
            sys.exit(1)

    if(args.preview):
        from scripts.preview import preview

        preview(ffmpeg, INPUT_FILE, args.silent_threshold, args.zoom_threshold,
            args.frame_margin, args.sample_rate, args.video_speed, args.silent_speed,
            args.cut_by_this_track, args.audio_bitrate)
        sys.exit()

    startTime = time.time()

    for INPUT_FILE in INPUTS:
        dotIndex = INPUT_FILE.rfind('.')
        extension = INPUT_FILE[dotIndex:]
        if(outputDir != ''):
            newOutput = os.path.join(outputDir, os.path.basename(INPUT_FILE))
            print(newOutput)
        else:
            newOutput = OUTPUT_FILE

        if(args.export_to_premiere):
            from scripts.premiere import exportToPremiere

            outFile = exportToPremiere(ffmpeg, INPUT_FILE, newOutput,
                args.silent_threshold, args.zoom_threshold, args.frame_margin,
                args.sample_rate, args.video_speed, args.silent_speed)
            continue

        isAudio = extension in ['.wav', '.mp3', '.m4a']
        if(isAudio):
            from scripts.fastAudio import fastAudio

            outFile = fastAudio(ffmpeg, INPUT_FILE, newOutput, args.silent_threshold,
                args.frame_margin, args.sample_rate, args.audio_bitrate, args.debug,
                args.silent_speed, args.video_speed, True)
            continue
        else:
            try:
                path = INPUT_FILE
                process = subprocess.Popen([ffmpeg, '-i', path],
                    stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                stdout, __ = process.communicate()
                output = stdout.decode()
                matchDict = re.search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
                __ = float(matchDict['fps'])
            except AttributeError:
                print('Warning! frame rate detection failed.')
                print('If your video has a variable frame rate, ignore this message.')

                # Auto-Editor wouldn't work if the video has a variable framerate, so
                # it needs to make a video with a constant framerate and use that for
                # it's input instead.

                cmd = [ffmpeg, '-i', INPUT_FILE, '-filter:v', f'fps=fps=30',
                    f'{TEMP}/constantVid{extension}', '-hide_banner']
                if(not args.debug):
                    cmd.extend(['-nostats', '-loglevel', '0'])
                subprocess.call(cmd)
                INPUT_FILE = f'{TEMP}/constantVid{extension}'

        if(args.background_music is None and args.background_volume != -8):
            print('Warning! Background volume specified even though no music was provided.')

        if(args.background_music is None and args.zoom_threshold > 1
            and args.cut_by_this_audio == None and args.hardware_accel is None):

            if(args.silent_speed == 99999 and args.video_speed == 1):
                from scripts.fastVideo import fastVideo

                outFile = fastVideo(ffmpeg, INPUT_FILE, newOutput, args.silent_threshold,
                    args.frame_margin, args.sample_rate, args.audio_bitrate,
                    args.debug, args.cut_by_this_track, args.keep_tracks_seperate)
            else:
                from scripts.fastVideoPlus import fastVideoPlus

                outFile = fastVideoPlus(ffmpeg, INPUT_FILE, newOutput, args.silent_threshold,
                    args.frame_margin, args.sample_rate, args.audio_bitrate,
                    args.debug, args.video_speed, args.silent_speed,
                    args.cut_by_this_track, args.keep_tracks_seperate)
        else:
            from scripts.originalMethod import originalMethod

            outFile = originalMethod(ffmpeg, INPUT_FILE, newOutput, args.frame_margin,
                args.silent_threshold, args.zoom_threshold, args.sample_rate,
                args.audio_bitrate, args.silent_speed, args.video_speed,
                args.keep_tracks_seperate, args.background_music, args.background_volume,
                args.cut_by_this_audio, args.cut_by_this_track, args.cut_by_all_tracks,
                args.debug, args.hardware_accel)

    print('Finished.')
    timeLength = round(time.time() - startTime, 2)
    minutes = timedelta(seconds=round(timeLength))
    print(f'took {timeLength} seconds ({minutes})')

    if(not os.path.isfile(outFile)):
        raise IOError(f'Error: The file {outFile} was not created.')

    if(not args.no_open and not args.export_to_premiere):
        try:  # should work on Windows
            os.startfile(outFile)
        except AttributeError:
            try:  # should work on MacOS and most Linux versions
                subprocess.call(['open', outFile])
            except:
                try: # should work on WSL2
                    subprocess.call(['cmd.exe', '/C', 'start', outFile])
                except:
                    print('Could not open output file.')

    if(os.path.isdir(TEMP)):
        rmtree(TEMP)
