'''auto-editor.py'''

# external python libraries
from audiotsm import phasevocoder
from audiotsm.io.wav import WavReader, WavWriter
from scipy.io import wavfile
from PIL import Image # pip install pillow
import numpy as np

# internal python libraries
from math import ceil
import os
import argparse
import subprocess
from re import search
import sys
from datetime import timedelta
from time import time
from shutil import move, rmtree, copyfile
from multiprocessing import Process

FADE_SIZE = 400
TEMP_FOLDER = '.TEMP'
CACHE = '.CACHE'

def createAudio(chunks, samplesPerFrame, NEW_SPEED,
    audioData, SAMPLE_RATE, maxAudioVolume):

    print('Creating new audio.')

    outputAudioData = []
    outputPointer = 0
    # create audio envelope mask
    mask = [x / FADE_SIZE for x in range(FADE_SIZE)]

    num = 0
    chunk_len = str(len(chunks))
    for chunk in chunks:
        if(NEW_SPEED[int(chunk[2])] < 99999):
            audioChunk = audioData[int(chunk[0]*samplesPerFrame):int(chunk[1]*samplesPerFrame)]

            sFile = ''.join([TEMP_FOLDER, '/tempStart.wav'])
            eFile = ''.join([TEMP_FOLDER, '/tempEnd.wav'])
            wavfile.write(sFile, SAMPLE_RATE, audioChunk)
            with WavReader(sFile) as reader:
                with WavWriter(eFile, reader.channels, reader.samplerate) as writer:
                    tsm = phasevocoder(reader.channels, speed=NEW_SPEED[int(chunk[2])])
                    tsm.run(reader, writer)
            __, alteredAudioData = wavfile.read(eFile)
            leng = alteredAudioData.shape[0]
            endPointer = outputPointer + leng
            outputAudioData.extend((alteredAudioData / maxAudioVolume).tolist())

            # smooth out transitiion's audio by quickly fading in/out
            if(leng < FADE_SIZE):
                for i in range(outputPointer, endPointer):
                    outputAudioData[i] = 0
            else:
                for i in range(outputPointer, outputPointer+FADE_SIZE):
                    outputAudioData[i][0] *= mask[i-outputPointer]
                    outputAudioData[i][1] *= mask[i-outputPointer]
                for i in range(endPointer-FADE_SIZE, endPointer):
                    outputAudioData[i][0] *= (1-mask[i-endPointer+FADE_SIZE])
                    outputAudioData[i][1] *= (1-mask[i-endPointer+FADE_SIZE])

            outputPointer = endPointer

        num += 1
        if(num % 10 == 0):
            print(''.join([str(num), '/', chunk_len, ' audio chunks done.']))

    print('Creating finished audio.')
    outputAudioData = np.asarray(outputAudioData)
    wavfile.write(TEMP_FOLDER+'/audioNew.wav', SAMPLE_RATE, outputAudioData)
    print('Audio finished.')


def resize(input_file, output_file, size):
    im = Image.open(input_file)
    w, h = im.size
    size_tuple = (int(w * size), int(h * size))
    im = im.resize(size_tuple)
    nw, nh = im.size

    dif1 = nw - w
    dif2 = nh - h
    left = dif1 / 2
    right = w + dif1 / 2
    top = dif2 / 2
    bottom = h + dif2 / 2

    cropped_im = im.crop((left, top, right, bottom))
    cropped_im.save(output_file)


def copyFrame(inputFrame, newIndex, frameRate, theZoom):
    src = ''.join([CACHE, '/frame{:06d}'.format(inputFrame+1), '.jpg'])
    if(os.path.isfile(src)):
        dst = ''.join([TEMP_FOLDER, '/newFrame{:06d}'.format(newIndex+1), '.jpg'])
        if(theZoom == 1):
            copyfile(src, dst)
        else:
            resize(src, dst, theZoom)


def createVideo(chunks, NEW_SPEED, frameRate, ZOOM):
    print('Creating new video.')
    newIndex = 0
    num = 0
    chunk_len = str(len(chunks))
    for chunk in chunks:
        n = chunk[0]
        end = chunk[1]
        theSpeed = NEW_SPEED[int(chunk[2])]
        theZoom = ZOOM[int(chunk[2])]
        while(n <= end):
            n += theSpeed
            if(n <= end):
                newIndex += 1
                copyFrame(int(n), newIndex, frameRate, theZoom)
        num += 1
        if(num % 10 == 0):
            print(''.join([str(num), '/', chunk_len, ' video chunks done.']))


    print('Creating finished video. (This can take a while)')
    command = f'ffmpeg -y -framerate {frameRate} -i {TEMP_FOLDER}/newFrame%06d.jpg'
    command += f' {TEMP_FOLDER}/output.mp4'
    command += ' -nostats -loglevel 0'
    subprocess.call(command, shell=True)
    print('Video finished.')


def getFrameRate(path):
    process = subprocess.Popen(['ffmpeg', '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    # __ represents an unneeded variable
    output = stdout.decode()
    match_dict = search(r"\s(?P<fps>[\d\.]+?)\stbr", output).groupdict()
    return float(match_dict["fps"])


def getMaxVolume(s):
    maxv = float(np.max(s))
    minv = float(np.min(s))
    return max(maxv, -minv)


def getAvgVolume(s):
    new_s = np.absolute(s)
    return np.mean(new_s)


def quality_type(x):
    x = int(x)
    if(x > 31):
        raise argparse.ArgumentTypeError("Minimum frame quality is 31")
    if(x < 1):
        raise argparse.ArgumentTypeError("Maximum frame quality is 1")
    return x


if(__name__ == '__main__'):
    parser = argparse.ArgumentParser()
    parser.add_argument('input',
        help='the path to the video file you want modified. can be a URL with youtube-dl.')
    parser.add_argument('-o', '--output_file', type=str, default='',
        help='name the output file.')
    parser.add_argument('-t', '--silent_threshold', type=float, default=0.04,
        help='the volume that frames audio needs to surpass to be sounded. It ranges from 0 to 1.')
    parser.add_argument('-l', '--loudness_threshold', type=float, default=0.50,
        help='(New!) the volume that needs to be surpassed to zoom in the video.')
    parser.add_argument('-v', '--video_speed', type=float, default=1.00,
        help='the speed that sounded (spoken) frames should be played at.')
    parser.add_argument('-s', '--silent_speed', type=float, default=99999,
        help='the speed that silent frames should be played at.')
    parser.add_argument('-m', '--frame_margin', type=float, default=4,
        help='tells how many frames on either side of speech should be included.')
    parser.add_argument('-r', '--sample_rate', type=float, default=44100,
        help='sample rate of the input and output videos.')
    parser.add_argument('-f', '--frame_rate', type=float,
        help='manually set the frame rate (fps) of the input video.')
    parser.add_argument('-q', '--frame_quality', type=quality_type, default=3,
        help='quality of frames from input video. 1 is highest, 31 is lowest.')
    parser.add_argument('--get_auto_fps', '--get_frame_rate', action='store_true',
        help='return what auto-editor thinks the frame rate is.')
    parser.add_argument('--verbose', action='store_true',
        help='display more information when running.')
    parser.add_argument('--prerun', action='store_true',
        help='create the cache folder without doing extra work.')
    parser.add_argument('--clear_cache', action='store_true',
        help='delete the cache folder and all of its contents.')

    args = parser.parse_args()

    startTime = time()

    SAMPLE_RATE = args.sample_rate
    SILENT_THRESHOLD = args.silent_threshold
    LOUD_THRESHOLD = args.loudness_threshold
    FRAME_SPREADAGE = args.frame_margin
    if(args.silent_speed <= 0):
        args.silent_speed = 99999
    if(args.video_speed <= 0):
        args.video_speed = 99999
    NEW_SPEED = [args.silent_speed, args.video_speed, args.video_speed]
    ZOOM = [1, 1, 1.2]
    FRAME_QUALITY = args.frame_quality
    VERBOSE = args.verbose
    PRERUN = args.prerun

    INPUT_FILE = args.input

    if(args.clear_cache):
        rmtree(CACHE)
        sys.exit()

    # check if we need to download the file with youtube-dl
    if(INPUT_FILE.startswith('http://') or INPUT_FILE.startswith('https://')):
        print('URL detected, using youtube-dl to download from webpage.')
        command = f"youtube-dl -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4' '{INPUT_FILE}' --output web_download"
        subprocess.call(command, shell=True)
        print('Finished Download')
        INPUT_FILE = 'web_download.mp4'

    # find fps if frame_rate is not given
    if(args.frame_rate is None):
        frameRate = getFrameRate(INPUT_FILE)
    else:
        frameRate = args.frame_rate

    if(args.get_auto_fps):
        print(frameRate)
        sys.exit()

    if(len(args.output_file) >= 1):
        OUTPUT_FILE = args.output_file
    else:
        dotIndex = INPUT_FILE.rfind('.')
        OUTPUT_FILE = INPUT_FILE[:dotIndex]+'_ALTERED'+INPUT_FILE[dotIndex:]

    # make Temp folder
    try:
        os.mkdir(TEMP_FOLDER)
    except OSError:
        rmtree(TEMP_FOLDER)
        os.mkdir(TEMP_FOLDER)

    # make Cache folder
    SKIP = False
    try:
        os.mkdir(CACHE)
    except OSError:
        if(os.path.isfile(f'{CACHE}/cache.txt')):
            file = open(f'{CACHE}/cache.txt', 'r')
            x = file.readlines()
            if(x[0] == INPUT_FILE+'\n' and x[1] == str(frameRate)):
                print('Using cache.')
                SKIP = True
            file.close()
        if(not SKIP):
            rmtree(CACHE)
            os.mkdir(CACHE)

    if(not SKIP):
        print('Splitting video into jpgs. (This can take a while)')

        command = f'ffmpeg -i "{INPUT_FILE}" -qscale:v {FRAME_QUALITY} {CACHE}/frame%06d.jpg'
        if(not VERBOSE):
            command += ' -nostats -loglevel 0'
        subprocess.call(command, shell=True)

        # -b:a means audio bitrate
        # -ac 2 means set the audio channels to 2. (stereo)
        # -ar means set the audio sampling rate
        # -vn means disable video
        print('Separating audio from video.')
        command = f'ffmpeg -i "{INPUT_FILE}" -b:a 160k -ac 2 -ar {SAMPLE_RATE} -vn {CACHE}/audio.wav '
        if(not VERBOSE):
            command += '-nostats -loglevel 0'
        subprocess.call(command, shell=True)

    if(PRERUN):
        print('Done.')
        sys.exit()

    # calculating chunks.
    sampleRate, audioData = wavfile.read(CACHE+'/audio.wav')
    audioSampleCount = audioData.shape[0]
    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / frameRate
    audioFrameCount = int(ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount))

    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        maxchunksVolume = getMaxVolume(audiochunks) / maxAudioVolume
        if(maxchunksVolume >= LOUD_THRESHOLD):
            hasLoudAudio[i] = 2
        elif(maxchunksVolume >= SILENT_THRESHOLD):
            hasLoudAudio[i] = 1

    chunks = [[0, 0, 0]]
    shouldIncludeFrame = np.zeros((audioFrameCount))
    for i in range(audioFrameCount):
        start = int(max(0, i-FRAME_SPREADAGE))
        end = int(min(audioFrameCount, i+1+FRAME_SPREADAGE))
        shouldIncludeFrame[i] = np.max(hasLoudAudio[start:end])

        # did we flip?
        if (i >= 1 and shouldIncludeFrame[i] != shouldIncludeFrame[i-1]):
            chunks.append([chunks[-1][1], i, shouldIncludeFrame[i-1]])

    chunks.append([chunks[-1][1], audioFrameCount, shouldIncludeFrame[i-1]])
    chunks = chunks[1:]

    print(getAvgVolume(audiochunks) / maxAudioVolume)
    # chunks = [startFrame, stopFrame, isLoud?]

    p1 = Process(target=createAudio, args=(chunks, samplesPerFrame,
        NEW_SPEED, audioData, SAMPLE_RATE, maxAudioVolume))
    p1.start()
    p2 = Process(target=createVideo, args=(chunks, NEW_SPEED, frameRate, ZOOM))
    p2.start()

    p1.join()
    p2.join()

    print('Muxing audio and video.')
    command = f'ffmpeg -y -i {TEMP_FOLDER}/output.mp4 -i {TEMP_FOLDER}/audioNew.wav -c:v copy -c:a aac'
    # faststart is recommended for YouTube videos since it lets the player play the video
    # before everything is loaded.
    command += ' -movflags +faststart'
    command += f' "{OUTPUT_FILE}"'
    if(not VERBOSE):
        command += ' -nostats -loglevel 0'
    subprocess.call(command, shell=True)

    print('Finished.')
    timeLength = round(time() - startTime, 2)
    minutes = timedelta(seconds=round(timeLength))
    print(f'took {timeLength} seconds ({minutes})')

    file = open(f'{CACHE}/cache.txt', 'w')
    file.write(f'{INPUT_FILE}\n{frameRate}')

    rmtree(TEMP_FOLDER)
