#!/usr/bin/env python3
'''auto-editor.py'''

# Internal python libraries
import os
import argparse
import re
import subprocess
import sys
import time
import platform
from datetime import timedelta
from shutil import rmtree
from operator import itemgetter

version = '20w28a'

# files that start with . are hidden, but can be viewed by running "ls -f" from console.
TEMP = '.TEMP'
CACHE = '.CACHE'

def getFrameRate(path):
    """
    get the frame rate by asking ffmpeg to do it for us then using a regex command to
    retrieve it.
    """
    process = subprocess.Popen(['ffmpeg', '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    matchDict = re.search(r'\s(?P<fps>[\d\.]+?)\stbr', output).groupdict()
    return float(matchDict['fps'])


def file_type(file):
    if(not os.path.isfile(file)):
        print('Could not locate file:', file)
        sys.exit()
    return file


def time_units(uinput):
    try:
        return int(uinput)
    except ValueError:
        if(uinput.endswith('secs')):
            return int(uinput[:3])
        else:
            print('Incorrect format for time units')
            sys.exit()

if(__name__ == '__main__'):
    parser = argparse.ArgumentParser()
    parser.add_argument('input', nargs='*',
        help='the path to the video file you want modified. can be a URL with youtube-dl.')
    parser.add_argument('--output_file', '-o', type=str, default='',
        help='name the output file.')
    parser.add_argument('--silent_threshold', '-t', type=float, default=0.04,
        help='the volume that frames audio needs to surpass to be sounded. It ranges from 0 to 1.')
    parser.add_argument('--zoom_threshold', '-l', type=float, default=2.00,
        help='the volume that needs to be surpassed to zoom in the video. (0-1)')
    parser.add_argument('--video_speed', '--sounded_speed', '-v', type=float, default=1.00,
        help='the speed that sounded (spoken) frames should be played at.')
    parser.add_argument('--silent_speed', '-s', type=float, default=99999,
        help='the speed that silent frames should be played at.')
    parser.add_argument('--frame_margin', '-m', type=int, default=4,
        help='tells how many frames on either side of speech should be included.')
    parser.add_argument('--sample_rate', '-r', type=float, default=48000,
        help='sample rate of the input and output videos.')
    parser.add_argument('--audio_bitrate', type=str, default='160k',
        help='number of bits per second for audio. Example, 160k.')
    parser.add_argument('--frame_rate', '-f', type=float,
        help='manually set the frame rate (fps) of the input video.')
    parser.add_argument('--verbose', action='store_true',
        help='display more information when running.')
    parser.add_argument('--clear_cache', action='store_true',
        help='delete the cache folder and all of its contents.')
    parser.add_argument('--version', action='store_true',
        help='show which auto-editor you have.')
    parser.add_argument('--debug', action='store_true',
        help='show helpful debugging values.')
    parser.add_argument('--background_music', type=file_type,
        help='add background music to your output.')
    parser.add_argument('--background_volume', type=float, default=-8,
        help="set the dBs louder or softer compared to the audio track that bases the cuts.")
    parser.add_argument('--cut_by_this_audio', type=file_type,
        help="base cuts by this audio file instead of the video's audio.")
    parser.add_argument('--cut_by_this_track', '-ct', type=int, default=0,
        help='base cuts by a different audio track in the video.')
    parser.add_argument('--cut_by_all_tracks', action='store_true',
        help='combine all audio tracks into 1 before basing cuts.')
    parser.add_argument('--keep_tracks_seperate', action='store_true',
        help="Don't combine audio tracks. (Warning, multiple audio tracks are not supported on most platforms)")
    parser.add_argument('--hardware_accel', type=str,
        help='set the hardware used for gpu acceleration.')
    parser.add_argument('--combine_files', action='store_true',
        help='combine all files in a folder before editing.')
    parser.add_argument('--no_open', action='store_true',
        help='do not open the file after editing is done.')
    parser.add_argument('--preview', action='store_true',
        help='show stats on how the video will be cut.')
    parser.add_argument('--export_to_premiere', action='store_true',
        help='export as an XML file for Adobe Premiere Pro instead of outputting a video.')

    args = parser.parse_args()

    if(args.debug):
        is64bit = '64-bit' if sys.maxsize > 2**32 else '32-bit'
        print('Python Version:', platform.python_version(), is64bit)
        # platform can be 'Linux', 'Darwin' (macOS), 'Java', 'Windows'
        # more here: https://docs.python.org/3/library/platform.html#platform.system
        print('Platform:', platform.system())
        print('Auto-Editor Version:', version)
        sys.exit()

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

    if(args.input == []):
        print('auto-editor.py: error: the following arguments are required: input')
        sys.exit()

    INPUT_FILE = args.input[0]
    OUTPUT_FILE = args.output_file
    BACK_MUS = args.background_music
    BACK_VOL = args.background_volume
    NEW_TRAC = args.cut_by_this_audio
    BASE_TRAC = args.cut_by_this_track
    COMBINE_TRAC = args.cut_by_all_tracks

    SILENT_SPEED = args.silent_speed
    VIDEO_SPEED = args.video_speed

    if(SILENT_SPEED <= 0 or SILENT_SPEED > 99999):
        SILENT_SPEED = 99999
    if(VIDEO_SPEED <= 0 or VIDEO_SPEED > 99999):
        VIDEO_SPEED = 99999

    HWACCEL = args.hardware_accel

    if(os.path.isdir(INPUT_FILE)):
        # get the file path and date modified so that it can be sorted later.
        INPUTS = []
        for filename in os.listdir(INPUT_FILE):
            if(not filename.startswith('.')):
                dic = {}
                dic['file'] = os.path.join(INPUT_FILE, filename)
                dic['time'] = os.path.getmtime(dic['file'])

                INPUTS.append(dic)

        # sort the list by the key 'time'.
        newlist = sorted(INPUTS, key=itemgetter('time'), reverse=False)

        # then reduce to a list that only has strings.
        INPUTS = []
        for item in newlist:
            INPUTS.append(item['file'])

        if(args.combine_files):
            outputDir = ''

            with open('combine_files.txt', 'w') as outfile:
                for fileref in INPUTS:
                    outfile.write(f"file '{fileref}'\n")

            cmd = ['ffmpeg', '-f', 'concat', '-safe', '0', '-i', 'combine_files.txt',
            '-c', 'copy', 'combined.mp4']
            subprocess.call(cmd)

            INPUTS = ['combined.mp4']

            os.remove('combine_files.txt')
        else:
            outputDir = INPUT_FILE + '_ALTERED'
            # create the new folder for all the outputs
            try:
                os.mkdir(outputDir)
            except OSError:
                rmtree(outputDir)
                os.mkdir(outputDir)
    else:
        outputDir = ''
        if(os.path.isfile(INPUT_FILE)):
            INPUTS = [INPUT_FILE]
        # if input is URL, download as mp4 with youtube-dl
        elif(INPUT_FILE.startswith('http://') or INPUT_FILE.startswith('https://')):
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
            sys.exit()

    if(args.preview):
        from scripts.preview import preview

        preview(INPUT_FILE, args.silent_threshold, args.zoom_threshold,
            args.frame_margin, args.sample_rate, VIDEO_SPEED, SILENT_SPEED)
        sys.exit()

    startTime = time.time()

    # all the inputs are stored in the INPUTS variable
    del INPUT_FILE

    for INPUT_FILE in INPUTS:
        dotIndex = INPUT_FILE.rfind('.')
        extension = INPUT_FILE[dotIndex:]
        isAudio = extension in ['.wav', '.mp3', '.m4a']

        if(isAudio):
            from fastAudio import fastAudio

            fastAudio(INPUT_FILE, newOutput, args.silent_threshold, args.frame_margin,
                args.sample_rate, args.audio_bitrate, args.verbose, SILENT_SPEED,
                VIDEO_SPEED, True):
            continue
        else:
            try:
                frameRate = getFrameRate(INPUT_FILE)
            except AttributeError:
                print('Warning! frame rate detection failed.')
                print('If your video has a variable frame rate, ignore this message.')
                # convert frame rate to 30 or a user defined value
                if(args.frame_rate is None):
                    frameRate = 30
                else:
                    frameRate = args.frame_rate

                cmd = ['ffmpeg', '-i', INPUT_FILE, '-filter:v', f'fps=fps={frameRate}',
                    TEMP+'/constantVid'+extension, '-hide_banner']
                if(not args.verbose):
                    cmd.extend(['-nostats', '-loglevel', '0'])
                subprocess.call(cmd)
                INPUT_FILE = TEMP+'/constantVid'+extension

        if(BACK_MUS is None and BACK_VOL != -8):
            print('Warning! Background volume specified even though no background music was provided.')

        if(outputDir != ''):
            newOutput = os.path.join(outputDir, os.path.basename(INPUT_FILE))
            print(newOutput)
        else:
            newOutput = OUTPUT_FILE

        if(args.export_to_premiere):
            from scripts.premiere import exportToPremiere

            outFile = exportToPremiere(INPUT_FILE, newOutput, args.silent_threshold,
                args.zoom_threshold, args.frame_margin, args.sample_rate, VIDEO_SPEED,
                SILENT_SPEED)
            continue

        if(BACK_MUS is None and args.zoom_threshold == 2
            and NEW_TRAC == None and HWACCEL is None):

            if(SILENT_SPEED == 99999 and VIDEO_SPEED == 1):
                from scripts.fastVideo import fastVideo

                outFile = fastVideo(INPUT_FILE, newOutput, args.silent_threshold,
                    args.frame_margin, args.sample_rate, args.audio_bitrate,
                    args.verbose, args.cut_by_this_track, args.keep_tracks_seperate)
            else:
                from scripts.fastVideoPlus import fastVideoPlus

                outFile = fastVideoPlus(INPUT_FILE, newOutput, args.silent_threshold,
                    args.frame_margin, args.sample_rate, args.audio_bitrate,
                    args.verbose, VIDEO_SPEED, SILENT_SPEED, args.cut_by_this_track,
                    args.keep_tracks_seperate)
        else:
            from scripts.originalMethod import originalMethod

            outFile = originalMethod(INPUT_FILE, newOutput, args.frame_rate, args.frame_margin,
                args.silent_threshold, args.zoom_threshold, args.sample_rate,
                args.audio_bitrate, SILENT_SPEED, VIDEO_SPEED, args.keep_tracks_seperate, BACK_MUS,
                BACK_VOL, NEW_TRAC, BASE_TRAC, COMBINE_TRAC, args.verbose, HWACCEL)

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
