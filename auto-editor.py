'''auto-editor.py'''

# external python libraries
from audiotsm import phasevocoder
from audiotsm.io.wav import WavReader, WavWriter
from scipy.io import wavfile
import numpy as np
import cv2

# internal python libraries
from math import ceil
import os
import argparse
import subprocess
import sys
import datetime
import time
from shutil import copyfile, rmtree
from multiprocessing import Process

TEMP_FOLDER = '.TEMP'

def createAudio(chunks, samplesPerFrame, AUDIO_FADE_ENVELOPE_SIZE,
    NEW_SPEED, audioData, SAMPLE_RATE, maxAudioVolume):

    print('Creating new audio.')

    outputAudioData = np.zeros((0, audioData.shape[1]))
    outputPointer = 0

    num = 0
    for chunk in chunks:
        audioChunk = audioData[int(chunk[0]*samplesPerFrame):int(chunk[1]*samplesPerFrame)]

        sFile = ''.join([TEMP_FOLDER, '/tempStart.wav'])
        eFile = ''.join([TEMP_FOLDER, '/tempEnd.wav'])
        wavfile.write(sFile, SAMPLE_RATE, audioChunk)
        with WavReader(sFile) as reader:
            with WavWriter(eFile, reader.channels, reader.samplerate) as writer:
                tsm = phasevocoder(reader.channels, speed=NEW_SPEED[int(chunk[2])])
                tsm.run(reader, writer)
        _, alteredAudioData = wavfile.read(eFile)
        leng = alteredAudioData.shape[0]
        endPointer = outputPointer + leng
        outputAudioData = np.concatenate((outputAudioData, alteredAudioData / maxAudioVolume))

        # smooth out transitiion's audio by quickly fading in/out
        if(leng < AUDIO_FADE_ENVELOPE_SIZE):
            outputAudioData[outputPointer:endPointer] = 0
        else:
            premask = np.arange(AUDIO_FADE_ENVELOPE_SIZE) / AUDIO_FADE_ENVELOPE_SIZE
            # make the fade-envelope mask stereo
            mask = np.repeat(premask[:, np.newaxis], 2, axis=1)
            outputAudioData[outputPointer:outputPointer+AUDIO_FADE_ENVELOPE_SIZE] *= mask
            outputAudioData[endPointer-AUDIO_FADE_ENVELOPE_SIZE:endPointer] *= 1-mask

        outputPointer = endPointer

        num += 1
        if(num % 10 == 0):
            print(f'{num} audio chunks done.')

    print('Creating finished audio.')
    wavfile.write(TEMP_FOLDER+'/audioNew.wav', SAMPLE_RATE, outputAudioData)
    print('Audio finished.')


def copyFrame(inputFrame, newIndex, frameRate):
    src = ''.join([TEMP_FOLDER, '/frame{:06d}'.format(inputFrame+1), '.jpg'])
    if(os.path.isfile(src)):
        dst = ''.join([TEMP_FOLDER, '/newFrame{:06d}'.format(newIndex+1), '.jpg'])
        copyfile(src, dst)
        if(newIndex % 200 == 0):
            f_sec = round(newIndex / frameRate)
            print(f'{newIndex} frames done ({datetime.timedelta(seconds=f_sec)})')


def createVideo(chunks, NEW_SPEED, frameRate):
    print('Creating new video.')
    newIndex = 0
    for chunk in chunks:
        n = chunk[0]
        end = chunk[1]
        theSpeed = NEW_SPEED[int(chunk[2])]
        while(n <= end):
            n += theSpeed
            if(n <= end):
                newIndex += 1
                copyFrame(int(n), newIndex, frameRate)
    print('Creating finished video. (This can take a while)')
    command = f'ffmpeg -y -framerate {frameRate} -i {TEMP_FOLDER}/newFrame%06d.jpg'
    command += f' {TEMP_FOLDER}/output.mp4'
    command += ' -nostats -loglevel 0'
    subprocess.call(command, shell=True)
    print('Video finished.')


def getMaxVolume(s):
    maxv = float(np.max(s))
    minv = float(np.min(s))
    return max(maxv, -minv)


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
    parser.add_argument('-v', '--video_speed', type=float, default=1.00,
        help='the speed that sounded (spoken) frames should be played at.')
    parser.add_argument('-s', '--silent_speed', type=float, default=99999,
        help='the speed that silent frames should be played at.')
    parser.add_argument('-m', '--frame_margin', type=float, default=4,
        help='tells how many frames on either side of speech should be included.')
    parser.add_argument('-r', '--sample_rate', type=float, default=44100,
        help='sample rate of the input and output videos.')
    parser.add_argument('-f', '--frame_rate', type=float,
        help='manually set the frame rate (fps) of the input video. auto-editor will try to set it for you.')
    parser.add_argument('-q', '--frame_quality', type=quality_type, default=3,
        help='quality of frames from input video. 1 is highest, 31 is lowest.')
    parser.add_argument('--get_auto_fps', '--get_frame_rate', action='store_true',
        help='return what auto-editor thinks the frame rate is.')
    parser.add_argument('--verbose', action='store_true',
        help='display more information when running.')

    args = parser.parse_args()

    startTime = time.time()

    # smooth out transitiion's audio by quickly fading in/out
    AUDIO_FADE_ENVELOPE_SIZE = 400

    SAMPLE_RATE = args.sample_rate
    SILENT_THRESHOLD = args.silent_threshold
    FRAME_SPREADAGE = args.frame_margin
    NEW_SPEED = [args.silent_speed, args.video_speed]
    FRAME_QUALITY = args.frame_quality
    VERBOSE = args.verbose

    ORIGINAL_NAME = args.input

    # check if we need to download the file with youtube-dl
    if(ORIGINAL_NAME.startswith('http://') or ORIGINAL_NAME.startswith('https://')):
        print('URL detected, using youtube-dl to download from webpage.')
        command = f"youtube-dl -f 'bestvideo[ext=mp4]+bestaudio[ext=m4a]/mp4' '{ORIGINAL_NAME}' --output web_download"
        subprocess.call(command, shell=True)
        print('Finished Download')
        ORIGINAL_NAME = 'web_download.mp4'


    INPUT_FILE = ORIGINAL_NAME.replace(' ', '\\ ')

    # find fps if frame_rate is not given
    if(args.frame_rate is None):
        cap = cv2.VideoCapture(ORIGINAL_NAME)
        frameRate = cap.get(cv2.CAP_PROP_FPS)
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

    # make Temp directory
    try:
        os.mkdir(TEMP_FOLDER)
    except OSError:
        rmtree(TEMP_FOLDER, ignore_errors=False)
        os.mkdir(TEMP_FOLDER)

    print('Splitting video into jpgs. (This can take a while)')

    command = f'ffmpeg -i {INPUT_FILE} -qscale:v {FRAME_QUALITY} {TEMP_FOLDER}/frame%06d.jpg'
    if(not VERBOSE):
        command += ' -nostats -loglevel 0'
    subprocess.call(command, shell=True)

    # -b:a means audio bitrate
    # -ac 2 means set the audio channels to 2. (stereo)
    # -ar means set the audio sampling rate
    # -vn means disable video
    print('Separating audio from video.')
    command = f'ffmpeg -i {INPUT_FILE} -b:a 160k -ac 2 -ar {SAMPLE_RATE} -vn {TEMP_FOLDER}/audio.wav '
    if(not VERBOSE):
        command += '-nostats -loglevel 0'
    subprocess.call(command, shell=True)

    sampleRate, audioData = wavfile.read(TEMP_FOLDER+'/audio.wav')
    audioSampleCount = audioData.shape[0]
    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / frameRate
    audioFrameCount = int(ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount))

    print('Calculating chunks.')

    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        maxchunksVolume = getMaxVolume(audiochunks) / maxAudioVolume
        if(maxchunksVolume >= SILENT_THRESHOLD):
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

    # chunks = [startFrame, stopFrame, isLoud?]

    p1 = Process(target=createAudio, args=(chunks, samplesPerFrame,
        AUDIO_FADE_ENVELOPE_SIZE, NEW_SPEED, audioData,
        SAMPLE_RATE, maxAudioVolume))
    p1.start()
    p2 = Process(target=createVideo, args=(chunks, NEW_SPEED, frameRate))
    p2.start()

    p1.join()
    p2.join()


    print('Muxing audio and video.')
    command = f'ffmpeg -y -i {TEMP_FOLDER}/output.mp4 -i {TEMP_FOLDER}/audioNew.wav -c:v copy -c:a aac'

    # -pix_fmt yuvj420p is added for the output to work in QuickTime and most other players
    command += ' -pix_fmt yuvj420p'
    # faststart is recommended for YouTube videos since it lets the player play the video
    # before everything is loaded.
    command += ' -movflags +faststart'
    command += f' {OUTPUT_FILE}'
    if(not VERBOSE):
        command += ' -nostats -loglevel 0'
    subprocess.call(command, shell=True)

    print('Finished.')
    timeLength = round(time.time() - startTime, 2)
    print(f'took {timeLength} seconds ({datetime.timedelta(seconds=timeLength)})')

    rmtree(TEMP_FOLDER, ignore_errors=False)
