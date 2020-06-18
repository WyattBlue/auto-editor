'''auto-editor.py'''

# external python libraries
import numpy as np

# internal python libraries
import os
import argparse
import subprocess
import sys
import time
from datetime import timedelta
from shutil import rmtree
from operator import itemgetter

# included functions
from scripts.originalMethod import originalMethod
from scripts.fastVideo import fastVideo

version = '20w25a'

TEMP = '.TEMP'
CACHE = '.CACHE'

def getFrameRate(path):
    from re import search

    process = subprocess.Popen(['ffmpeg', '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    matchDict = search(r"\s(?P<fps>[\d\.]+?)\stbr", output).groupdict()
    return float(matchDict["fps"])


def file_type(file):
    if(not os.path.isfile(file)):
        print('Could not locate file:', file)
        sys.exit()
    return file


def quality_type(x):
    x = int(x)
    if(x > 31):
        raise argparse.ArgumentTypeError("Minimum frame quality is 31")
    if(x < 1):
        raise argparse.ArgumentTypeError("Maximum frame quality is 1")
    return x


if(__name__ == '__main__'):
    parser = argparse.ArgumentParser()
    parser.add_argument('input', nargs='*',
        help='the path to the video file you want modified. can be a URL with youtube-dl.')
    parser.add_argument('--output_file', '-o', type=str, default='',
        help='name the output file.')
    parser.add_argument('--silent_threshold', '-t', type=float, default=0.04,
        help='the volume that frames audio needs to surpass to be sounded. It ranges from 0 to 1.')
    parser.add_argument('--loudness_threshold', '-l', type=float, default=2.00,
        help='the volume that needs to be surpassed to zoom in the video. (0-1)')
    parser.add_argument('--video_speed', '--sounded_speed', '-v', type=float, default=1.00,
        help='the speed that sounded (spoken) frames should be played at.')
    parser.add_argument('--silent_speed', '-s', type=float, default=99999,
        help='the speed that silent frames should be played at.')
    parser.add_argument('--frame_margin', '-m', type=int, default=4,
        help='tells how many frames on either side of speech should be included.')
    parser.add_argument('--sample_rate', '-r', type=float, default=44100,
        help='sample rate of the input and output videos.')
    parser.add_argument('--frame_rate', '-f', type=float,
        help='manually set the frame rate (fps) of the input video.')
    parser.add_argument('--frame_quality', '-q', type=quality_type, default=3,
        help='quality of frames from input video. 1 is highest, 31 is lowest.')
    parser.add_argument('--get_auto_fps', '--get_frame_rate', action='store_true',
        help='return what auto-editor thinks the frame rate is.')
    parser.add_argument('--verbose', action='store_true',
        help='display more information when running.')
    parser.add_argument('--clear_cache', action='store_true',
        help='delete the cache folder and all of its contents.')
    parser.add_argument('--version', action='store_true',
        help='show which auto-editor you have')
    parser.add_argument('--debug', action='store_true',
        help='show helpful debugging values.')
    parser.add_argument('--background_music', type=file_type,
        help='add background music to your output')
    parser.add_argument('--background_volume', type=float, default=-12,
        help="set the dBs louder or softer compared to the audio track that bases the cuts")
    parser.add_argument('--cut_by_this_audio', type=file_type,
        help='base cuts by this audio file instead of the video\'s audio')
    parser.add_argument('--cut_by_this_track', '-ct', type=int, default=0,
        help='base cuts by a different audio track in the video.')
    parser.add_argument('--cut_by_all_tracks', action='store_true',
        help='combine all audio tracks into 1 before basing cuts')
    parser.add_argument('--keep_tracks_seperate', action='store_true',
        help="Don't combine audio tracks ever. (Warning, multiple audio tracks are not supported on most platforms")
    parser.add_argument('--hardware_accel', type=str,
        help='set the hardware used for gpu acceleration')

    args = parser.parse_args()

    if(args.debug):
        print('Python Version:')
        print(sys.version)
        print('Is your python 64-Bit?')
        print(sys.maxsize > 2**32)
        print('Auto-Editor Version:')
        print(version)
        sys.exit()

    if(args.version):
        print('Auto-Editor version:', version)
        sys.exit()

    if(args.clear_cache):
        print('Removing cache')
        if(os.path.isfile('.CACHE')):
            rmtree('.CACHE')
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
    GIVEN_FPS = args.frame_rate

    SAMPLE_RATE = args.sample_rate
    SILENT_THRESHOLD = args.silent_threshold
    LOUD_THRESHOLD = args.loudness_threshold
    FRAME_SPREADAGE = args.frame_margin
    FRAME_QUALITY = args.frame_quality

    SILENT_SPEED = args.silent_speed
    VIDEO_SPEED = args.video_speed

    if(SILENT_SPEED <= 0 or SILENT_SPEED > 99999):
        SILENT_SPEED = 99999
    if(VIDEO_SPEED <= 0 or VIDEO_SPEED > 99999):
        VIDEO_SPEED = 99999

    VERBOSE = args.verbose
    HWACCEL = args.hardware_accel
    KEEP_SEP = args.keep_tracks_seperate

    if(os.path.isdir(INPUT_FILE)):
        # get a list of videos sorted by date modified. (date created is too platform dependent)
        INPUTS = []
        for filename in os.listdir(INPUT_FILE):
            if(not filename.startswith('.')):
                dic = {}
                dic['file'] = os.path.join(INPUT_FILE, filename)
                dic['time'] = os.path.getmtime(dic['file'])
                print(dic['time'])
                INPUTS.append(dic)

        outputDir = INPUT_FILE+'_ALTERED'
        newlist = sorted(INPUTS, key=itemgetter('time'), reverse=False)

        INPUTS = []
        for item in newlist:
            INPUTS.append(item['file'])
        del newlist

        print(INPUTS)

        sys.exit()

        # create the new folder for all the outputs
        try:
            os.mkdir(outputDir)
        except OSError:
            rmtree(outputDir)
            os.mkdir(outputDir)

    else:
        outputDir = ''
        if(os.path.isfile(INPUT_FILE)):
            # if input is URL, download as mp4 with youtube-dl
            if(INPUT_FILE.startswith('http://') or INPUT_FILE.startswith('https://')):
                print('URL detected, using youtube-dl to download from webpage.')
                cmd = ["youtube-dl", "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4",
                    INPUT_FILE, "--output", "web_download"]
                subprocess.call(cmd)
                print('Finished Download')
                INPUT_FILE = 'web_download.mp4'
                OUTPUT_FILE = 'web_download_ALTERED.mp4'

            INPUTS = [INPUT_FILE]
        else:
            print('Could not find file:', INPUT_FILE)
            sys.exit()

    if(args.get_auto_fps):
        print(getFrameRate(INPUT_FILE))
        sys.exit()

    startTime = time.time()

    # all the inputs are stored in the INPUTS variable
    del INPUT_FILE

    for INPUT_FILE in INPUTS:

        dotIndex = INPUT_FILE.rfind('.')
        extension = INPUT_FILE[dotIndex:]
        isAudio = extension in ['.wav', '.mp3', '.m4a']

        print('converting:', INPUT_FILE)

        if(not isAudio):
            try:
                frameRate = getFrameRate(INPUT_FILE)
            except AttributeError:
                print('Warning! frame rate detection failed.')
                print('If your video has a variable frame rate, ignore this message.')
                # convert frame rate to 30 or a user defined value
                if(GIVEN_FPS is None):
                    frameRate = 30
                else:
                    frameRate = GIVEN_FPS

                cmd = ['ffmpeg', '-i', INPUT_FILE, '-filter:v', f'fps=fps={frameRate}',
                    TEMP+'/constantVid'+extension, '-hide_banner']
                if(not VERBOSE):
                    cmd.extend(['-nostats', '-loglevel', '0'])
                subprocess.call(cmd)
                INPUT_FILE = TEMP+'/constantVid'+extension

        if(BACK_MUS is None and BACK_VOL != -12):
            print('Warning! Background volume specified even though no background music was provided.')

        if(outputDir != ''):
            newOutput = os.path.join(outputDir, os.path.basename(INPUT_FILE))
            print(newOutput)
        else:
            newOutput = OUTPUT_FILE

        if(KEEP_SEP == False and BACK_MUS is None and LOUD_THRESHOLD == 2
            and NEW_TRAC == None and SILENT_SPEED == 99999 and VIDEO_SPEED == 1
            and BASE_TRAC == 0 and HWACCEL is None and not isAudio):

            outFile = fastVideo(INPUT_FILE, newOutput, SILENT_THRESHOLD,
                FRAME_SPREADAGE, SAMPLE_RATE, VERBOSE)
        else:
            outFile = originalMethod(INPUT_FILE, newOutput, GIVEN_FPS, FRAME_SPREADAGE,
                FRAME_QUALITY, SILENT_THRESHOLD, LOUD_THRESHOLD, SAMPLE_RATE, SILENT_SPEED,
                VIDEO_SPEED, KEEP_SEP, BACK_MUS, BACK_VOL, NEW_TRAC, BASE_TRAC, COMBINE_TRAC,
                VERBOSE, HWACCEL)

    print('Finished.')
    timeLength = round(time.time() - startTime, 2)
    minutes = timedelta(seconds=round(timeLength))
    print(f'took {timeLength} seconds ({minutes})')

    if(not os.path.isfile(outFile)):
        raise IOError(f'Error: The file {outFile} was not created.')

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

    if(os.path.isfile('.TEMP')):
        rmtree('.TEMP')
