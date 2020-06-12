'''auto-editor.py'''

# external python libraries
from pydub import AudioSegment
from audiotsm import phasevocoder
from audiotsm.io.wav import WavReader, WavWriter
from scipy.io import wavfile
from PIL import Image # pip install pillow
import numpy as np

# internal python libraries
import math
import os
import argparse
import subprocess
import sys
import time
from datetime import timedelta
from shutil import move, rmtree, copyfile
from multiprocessing import Process

# included functions
from scripts.originalAudio import handleAudio
from scripts.originalVid import splitVideo
from scripts.original #???

version = '20w24a'

def debug():
    print('Python Version:')
    print(sys.version)
    print('Is your python 64-Bit?')
    print(sys.maxsize > 2**32)
    print('Auto-Editor Version:')
    print(version)


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
    parser.add_argument('--prerun', action='store_true',
        help='create the cache folder without doing extra work.')
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
        help="Don't combine audio tracks ever. (Warning, multiple audio tracks are not supported on most platforms (YouTube)")
    parser.add_argument('--hardware_accel', type=str,
        help='set the hardware used for gpu acceleration')

    args = parser.parse_args()

    if(args.debug):
        debug()
        sys.exit()

    if(args.version):
        print('Auto-Editor version:', version)
        sys.exit()

    if(args.clear_cache):
        print('Removing cache')
        rmtree(CACHE)
        if(args.input == []):
            sys.exit()

    startTime = time.time()

    SAMPLE_RATE = args.sample_rate
    SILENT_THRESHOLD = args.silent_threshold
    LOUD_THRESHOLD = args.loudness_threshold
    FRAME_SPREADAGE = args.frame_margin
    if(args.silent_speed <= 0):
        args.silent_speed = 99999
    if(args.video_speed <= 0):
        args.video_speed = 99999
    NEW_SPEED = [args.silent_speed, args.video_speed]

    FRAME_QUALITY = args.frame_quality
    VERBOSE = args.verbose
    PRERUN = args.prerun
    HWACCEL = args.hardware_accel
    KEEP_SEP = args.keep_tracks_seperate

    if(args.input == []):
        print('auto-editor.py: error: the following arguments are required: input')
        sys.exit(0)

    INPUT_FILE = args.input[0]
    BACK_MUS = args.background_music
    BACK_VOL = args.background_volume
    NEW_TRAC = args.cut_by_this_audio
    BASE_TRAC = args.cut_by_this_track
    COMBINE_TRAC = args.cut_by_all_tracks
    INPUTS = args.input

    # if input is URL, download as mp4 with youtube-dl
    if(INPUT_FILE.startswith('http://') or INPUT_FILE.startswith('https://')):
        print('URL detected, using youtube-dl to download from webpage.')
        cmd = ["youtube-dl", "-f", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4",
            INPUT_FILE, "--output", "web_download"]
        subprocess.call(cmd)
        print('Finished Download')
        INPUT_FILE = 'web_download.mp4'
        OUTPUT_FILE = 'web_download_ALTERED.mp4'


    if(args.get_auto_fps):
        print(frameRate)
        sys.exit()

    # original method
    originalMethod()

    print('Finished.')
    timeLength = round(time.time() - startTime, 2)
    minutes = timedelta(seconds=round(timeLength))
    print(f'took {timeLength} seconds ({minutes})')

    if(not os.path.isfile(OUTPUT_FILE)):
        raise IOError(f'Error: The file {OUTPUT_FILE} was not created.')

    try:  # should work on Windows
        os.startfile(OUTPUT_FILE)
    except AttributeError:
        try:  # should work on MacOS and most linux versions
            subprocess.call(["open", OUTPUT_FILE])
        except:
            try: # should work on WSL2
                subprocess.call(["cmd.exe", "/C", "start", OUTPUT_FILE])
            except:
                print("could not open output file")

    # reset cache folder
    if(not audioOnly):
        with open(f'{TEMP}/Renames.txt', 'r') as f:
            renames = f.read().splitlines()
            for i in range(0, len(renames), 2):
                os.rename(renames[i+1], renames[i])

    # create cache check with vid stats

    if(BACK_MUS is not None):
        tracks -= 1
    file = open(f'{CACHE}/cache.txt', 'w')
    file.write(f'{INPUT_FILE}\n{frameRate}\n{fileSize}\n{FRAME_QUALITY}\n{tracks}\n{COMBINE_TRAC}\n')

    rmtree(TEMP)
