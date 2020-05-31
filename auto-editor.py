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
from re import search
from datetime import timedelta
from shutil import move, rmtree, copyfile
from multiprocessing import Process

FADE_SIZE = 400
TEMP = '.TEMP'
CACHE = '.CACHE'
version = '20w22d'

def debug():
    print('Python Version:')
    print(sys.version)
    print('Is your python 64-Bit?')
    print(sys.maxsize > 2**32)
    print('Auto-Editor Version:')
    print(version)


def splitAudio(filename, chunks, samplesPerFrame, NEW_SPEED, audioData, SAMPLE_RATE,
    maxAudioVolume):

    outputAudioData = []
    outputPointer = 0
    mask = [x / FADE_SIZE for x in range(FADE_SIZE)]
    num = 0
    chunk_len = str(len(chunks))
    for chunk in chunks:
        if(NEW_SPEED[int(chunk[2])] < 99999):
            start = int(chunk[0] * samplesPerFrame)
            end = int(chunk[1] * samplesPerFrame)
            audioChunk = audioData[start:end]

            sFile = ''.join([TEMP, '/tempStart.wav'])
            eFile = ''.join([TEMP, '/tempEnd.wav'])
            wavfile.write(sFile, SAMPLE_RATE, audioChunk)
            if(NEW_SPEED[int(chunk[2])] == 1):
                __, samefile = wavfile.read(sFile)
                leng = len(audioChunk)

                outputAudioData.extend((samefile / maxAudioVolume).tolist())
            else:
                with WavReader(sFile) as reader:
                    with WavWriter(eFile, reader.channels, reader.samplerate) as writer:
                        phasevocoder(reader.channels, speed=NEW_SPEED[int(chunk[2])]).run(reader, writer)
                __, alteredAudioData = wavfile.read(eFile)
                leng = alteredAudioData.shape[0]

                outputAudioData.extend((alteredAudioData / maxAudioVolume).tolist())

            endPointer = outputPointer + leng

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

    print(''.join([str(num), '/', chunk_len, ' audio chunks done.']))
    outputAudioData = np.asarray(outputAudioData)
    wavfile.write(filename, SAMPLE_RATE, outputAudioData)

    if(not os.path.isfile(filename)):
        print('Error: Audio file failed to be created.')
        print('-------')
    else:
        print('Audio finished.')


def handleAudio(tracks, chunks, samplesPerFrame, NEW_SPEED, maxAudioVolume):
    print('Creating new audio.')
    for i in range(tracks):
        sampleRate, audioData = wavfile.read(f'{CACHE}/{i}.wav')
        splitAudio(f'{TEMP}/new{i}.wav', chunks, samplesPerFrame, NEW_SPEED,
            audioData, sampleRate, maxAudioVolume)

    if(tracks != 1):
        print('All audio tracks finished.')

def resize(inputFile, outputFile, size):
    im = Image.open(inputFile)
    w, h = im.size
    size_tuple = (int(w * size), int(h * size))
    im = im.resize(size_tuple)
    nw, nh = im.size

    left = (nw - w) / 2
    right = w + (nw - w) / 2
    top = (nh - h) / 2
    bottom = h + (nh - h) / 2

    cropped_im = im.crop((left, top, right, bottom))
    cropped_im.save(outputFile)


def splitVideo(chunks, NEW_SPEED, frameRate, zooms, samplesPerFrame, SAMPLE_RATE,
    audioData, extension, VERBOSE):
    print('Creating new video.')
    num = 0
    chunk_len = str(len(chunks))
    outputPointer = 0
    Renames = []
    for chunk in chunks:
        if(NEW_SPEED[int(chunk[2])] < 99999):
            audioChunk = audioData[int(chunk[0]*samplesPerFrame):int(chunk[1]*samplesPerFrame)]
            if(NEW_SPEED[int(chunk[2])] == 1):
                leng = len(audioChunk)
            else:
                sFile = TEMP + '/tempStart2.wav'
                eFile = TEMP + '/tempEnd2.wav'
                wavfile.write(sFile, SAMPLE_RATE, audioChunk)
                with WavReader(sFile) as reader:
                    with WavWriter(eFile, reader.channels, reader.samplerate) as writer:
                        phasevocoder(reader.channels, speed=NEW_SPEED[int(chunk[2])]).run(reader, writer)
                __, alteredAudioData = wavfile.read(eFile)
                leng = alteredAudioData.shape[0]

            endPointer = outputPointer + leng

            startOutputFrame = int(math.ceil(outputPointer/samplesPerFrame))
            endOutputFrame = int(math.ceil(endPointer/samplesPerFrame))
            for outputFrame in range(startOutputFrame, endOutputFrame):
                inputFrame = int(chunk[0]+NEW_SPEED[int(chunk[2])]*(outputFrame-startOutputFrame))

                src = ''.join([CACHE, '/frame{:06d}'.format(inputFrame+1), '.jpg'])
                dst = ''.join([TEMP, '/newFrame{:06d}'.format(outputFrame+1), '.jpg'])
                if(os.path.isfile(src)):
                    if(inputFrame in zooms):
                        resize(src, dst, zooms[inputFrame])
                    else:
                        os.rename(src, dst)
                        Renames.extend([src, dst])
                else:
                    print("This shouldn't happen.")

            outputPointer = endPointer

        num += 1
        if(num % 10 == 0):
            print(''.join([str(num), '/', chunk_len, ' frame chunks done.']))
    print(''.join([str(num), '/', chunk_len, ' frame chunks done.']))

    with open(f'{TEMP}/Renames.txt', 'w') as f:
        for item in Renames:
            f.write(f"{item}\n")

    print('Creating finished video. (This can take a while)')
    cmd = ['ffmpeg', '-y', '-framerate', str(frameRate), '-i',
        f'{TEMP}/newFrame%06d.jpg', f'{TEMP}/output{extension}']
    if(not VERBOSE):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)


def getFrameRate(path):
    process = subprocess.Popen(['ffmpeg', '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    matchDict = search(r"\s(?P<fps>[\d\.]+?)\stbr", output).groupdict()
    return float(matchDict["fps"])


def getVideoLength(path):
    process = subprocess.Popen(['ffmpeg', '-i', path],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()
    m = search(r'(\d\d:\d\d:\d\d.\d\d,)', output)
    if(m):
        text = m.group(1)[:-1]
        return text
    else:
        return 'Unknown length'


def getZooms(chunks, audioFrameCount, hasLoudAudio, FRAME_SPREADAGE):
    zooms = {}
    shouldIncludeFrame = np.zeros((audioFrameCount))
    hold = False
    endZoom = 0
    wait = ''
    for i in range(audioFrameCount):
        if(i in zooms):
            continue
        start = int(max(0, i-FRAME_SPREADAGE))
        end = int(min(audioFrameCount, i+1+FRAME_SPREADAGE))
        shouldIncludeFrame[i] = np.max(hasLoudAudio[start:end])
        if(i >= 2 and shouldIncludeFrame[i] == 2 and hold == False):
            if(shouldIncludeFrame[i] != shouldIncludeFrame[i-1]):
                a = 1.2 - 1.0 # 1.0 -> 1.2
                p = int(frameRate / 3)
                for x in range(1, p + 1):
                    trans = a * math.sin((math.pi/(2*p)) * x + (2*math.pi))
                    zooms[i+x-3] = 1 + trans
                hold = True
                endZoom = i + x
                continue
        if(hold == True):
            zooms[i-1] = 1.2
            if(len(shouldIncludeFrame) - i > int(frameRate * 1.5) and
                shouldIncludeFrame[i] == 1 and i-endZoom > int(frameRate/2)):
                for y in range(len(chunks)):
                    if(chunks[y][0] == i and chunks[y][2] == 1):
                        hold = False
    return zooms

def getMaxVolume(s):
    maxv = float(np.max(s))
    minv = float(np.min(s))
    return max(maxv, -minv)


def formatAudio(inputFile, outputFile, sampleRate, size, VERBOSE=False):
    cmd = ['ffmpeg', '-i', inputFile, '-b:a', size, '-ac', '2', '-ar', str(sampleRate),
     '-vn', outputFile]
    if(not VERBOSE):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)


def formatForPydub(inputFile, outputFile, SAMPLE_RATE):
    cmd = ['ffmpeg', '-i', inputFile, '-vn', '-ar',
        str(SAMPLE_RATE), '-ac', '2', '-ab', '192k', '-f', 'mp3', outputFile]
    cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)


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
    parser.add_argument('--cut_by_this_audio', type=file_type,
        help='base cuts by this audio file instead of the video\'s audio')
    parser.add_argument('--cut_by_this_track', '-ct', type=int, default=0,
        help='base cuts by a different audio track in the video.')
    parser.add_argument('--cut_by_all_tracks', action='store_true',
        help='combine all audio tracks into 1 before basing cuts')

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

    if(args.input == []):
        print('auto-editor.py: error: the following arguments are required: input')
        sys.exit(0)

    INPUT_FILE = args.input[0]
    BACK_MUS = args.background_music
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
        extension = '.mp4'
        audioOnly = False
    else:
        dotIndex = INPUT_FILE.rfind('.')
        if(len(args.output_file) >= 1):
            OUTPUT_FILE = args.output_file
        else:
            OUTPUT_FILE = INPUT_FILE[:dotIndex]+'_ALTERED'+INPUT_FILE[dotIndex:]

        extension = INPUT_FILE[dotIndex:]
        audioOnly = extension == '.wav' or extension == '.mp3'

    if(not os.path.isfile(INPUT_FILE)):
        print('Could not find file:', INPUT_FILE)
        sys.exit()

    if(args.frame_rate is None):
        if(audioOnly):
            frameRate = 30
        else:
            frameRate = getFrameRate(INPUT_FILE)
    else:
        frameRate = args.frame_rate

    fileSize = os.stat(INPUT_FILE).st_size

    if(args.get_auto_fps):
        print(frameRate)
        sys.exit()

    try:
        os.mkdir(TEMP)
    except OSError:
        rmtree(TEMP)
        os.mkdir(TEMP)

    # make Cache folder
    SKIP = False
    try:
        os.mkdir(CACHE)
    except OSError:
        if(os.path.isfile(f'{CACHE}/cache.txt')):
            file = open(f'{CACHE}/cache.txt', 'r')
            x = file.read().splitlines()
            if(x[:4] == [INPUT_FILE, str(frameRate), str(fileSize), str(FRAME_QUALITY)]
                and x[5] == str(COMBINE_TRAC)):
                print('Using cache.')
                SKIP = True
                tracks = int(x[4])
            file.close()
        if(not SKIP):
            rmtree(CACHE)
            os.mkdir(CACHE)

    if(not SKIP):
        if(audioOnly):
            print('Formatting audio.')
            formatAudio(INPUT_FILE, f'{CACHE}/0.wav', SAMPLE_RATE, '160k', VERBOSE)
        else:
            # Videos can have more than one audio track os we need to extract them all
            print('Separating audio from video.')

            tracks = 0
            if(COMBINE_TRAC):
                while(True):
                    cmd = ['ffmpeg', '-i', INPUT_FILE, '-b:a', '192k', '-ac', '2', '-ar',
                            str(SAMPLE_RATE), '-vn', '-map', '0:a:'+str(tracks),
                            f'{CACHE}/{tracks}.wav']

                    process = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT)
                    stdout, __ = process.communicate()
                    output = stdout.decode()
                    output = output[-70:]
                    # no more audio tracks
                    if("To ignore this, add a trailing '?' to the map." in output):
                        break
                    tracks += 1

                    if(BASE_TRAC >= tracks):
                        print("Error: You choose a track that doesn't exist.")
                        print(f'There are only {tracks} tracks. (starting from 0)')
                        sys.exit()
            else:
                cmd = ['ffprobe', INPUT_FILE, '-hide_banner', '-loglevel', 'panic',
                    '-show_entries', 'stream=index', '-select_streams', 'a', '-of',
                    'compact=p=0:nk=1']

                process = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT)
                stdout, __ = process.communicate()
                output = stdout.decode()

                tracks = len(subprocess.getoutput(output).split('\n'))

                if(BASE_TRAC >= tracks):
                    print("Error: You choose a track that doesn't exist.")
                    print(f'There are only {tracks} tracks. (starting from 0)')
                    sys.exit()
                for trackNumber in range(tracks):
                    cmd = ['ffmpeg', '-i', INPUT_FILE, '-map', f'0:a:{trackNumber}',
                        f'{CACHE}/{trackNumber}.wav']
                    if(not VERBOSE):
                        cmd.extend(['-nostats', '-loglevel', '0'])
                    subprocess.call(cmd)

            if(COMBINE_TRAC):
                for i in range(tracks):
                    if(i == 0):
                        allAuds = AudioSegment.from_file(f'{CACHE}/{i}.wav')
                    else:
                        newTrack = AudioSegment.from_file(f'{CACHE}/{i}.wav')
                        allAuds = allAuds.overlay(newTrack)
                allAuds.export(f'{CACHE}/my0.wav', format='wav')
                os.rename(f'{CACHE}/my0.wav', f'{CACHE}/0.wav')
                tracks = 1
            print(f'Done with audio. ({tracks} tracks)')

            # now deal with the video (this takes longer)
            print('Splitting video into jpgs. (This can take a while)')
            cmd = ['ffmpeg', '-i', INPUT_FILE, '-qscale:v', str(FRAME_QUALITY),
                f'{CACHE}/frame%06d.jpg']
            if(not VERBOSE):
                cmd.extend(['-nostats', '-loglevel', '0'])
            subprocess.call(cmd)

    if(PRERUN):
        print('Done.')
        sys.exit()

    # calculating chunks.
    if(NEW_TRAC is None):
        # always base cuts by the first track
        sampleRate, audioData = wavfile.read(CACHE+'/'+str(BASE_TRAC)+'.wav')
    else:
        formatAudio(NEW_TRAC, f'{TEMP}/NEW_TRAC.wav', SAMPLE_RATE, '160k', VERBOSE)
        sampleRate, audioData = wavfile.read(f'{TEMP}/NEW_TRAC.wav')
    audioSampleCount = audioData.shape[0]
    maxAudioVolume = getMaxVolume(audioData)

    samplesPerFrame = sampleRate / frameRate
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
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
        shouldIncludeFrame[i] = min(1, np.max(hasLoudAudio[start:end]))

        if (i >= 1 and shouldIncludeFrame[i] != shouldIncludeFrame[i-1]):
            chunks.append([chunks[-1][1], i, shouldIncludeFrame[i-1]])

    chunks.append([chunks[-1][1], audioFrameCount, shouldIncludeFrame[i-1]])
    chunks = chunks[1:]

    if(audioOnly):
        splitAudio(TEMP+'/audioNew.wav', chunks, samplesPerFrame, NEW_SPEED, audioData,
            SAMPLE_RATE, maxAudioVolume)
    else:
        zooms = getZooms(chunks, audioFrameCount,
            hasLoudAudio, FRAME_SPREADAGE)

        p1 = Process(target=handleAudio, args=(tracks, chunks, samplesPerFrame, NEW_SPEED,
            maxAudioVolume))
        p1.start()
        p2 = Process(target=splitVideo, args=(chunks, NEW_SPEED, frameRate, zooms,
            samplesPerFrame, SAMPLE_RATE, audioData, extension, VERBOSE))
        p2.start()

        p1.join()
        p2.join()

    # combine all audio tracks into TEMP+/audioNew.wav
    if(tracks == 1):
        move(TEMP+'/new0.wav', TEMP+'/audioNew.wav')
    elif(1 == 0):
        for i in range(tracks):
            formatForPydub(f'{TEMP}/new{i}.wav', f'{TEMP}/for{i}.mp3', SAMPLE_RATE)
            if(i == 0):
                allAuds = AudioSegment.from_file(f'{TEMP}/for{i}.mp3')
            else:
                newTrack = AudioSegment.from_file(f'{TEMP}/for{i}.mp3')
                allAuds = allAuds.overlay(newTrack)
        allAuds.export(TEMP+"/audioNew.wav", format='wav')

    if(NEW_TRAC is not None):
        # New track is in TEMP+/audioNew.wav
        sampleRate, audioData = wavfile.read(CACHE+'/audio.wav')
        splitAudio(TEMP+'/vidAudio.wav', chunks, samplesPerFrame, NEW_SPEED, audioData,
            SAMPLE_RATE, maxAudioVolume)

        formatForPydub(TEMP+'/audioNew.wav', TEMP+'/newTrack.mp3', SAMPLE_RATE)
        formatForPydub(TEMP+'/vidAudio.wav', TEMP+'/vidAudio.mp3', SAMPLE_RATE)

        newTrack = AudioSegment.from_file(TEMP+'/newTrack.mp3')
        vidAudio = AudioSegment.from_file(TEMP+'/vidAudio.mp3')

        if(len(newTrack) > len(vidAudio)):
            newTrack = newTrack[:len(vidAudio)]

        combined = newTrack.overlay(vidAudio)
        combined.export(TEMP+"/audioNew.wav", format='wav')

    if(BACK_MUS is not None):
        formatForPydub(TEMP+'/audioNew.wav', TEMP+'/output.mp3', SAMPLE_RATE)

        vidSound = AudioSegment.from_file(TEMP+'/output.mp3')

        back = AudioSegment.from_file(BACK_MUS)
        if(len(back) > len(vidSound)):
            back = back[:len(vidSound)]

        def match_target_amplitude(back, vidSound, target):
            diff = back.dBFS - vidSound.dBFS
            change_in_dBFS = target - diff
            return back.apply_gain(change_in_dBFS)

        # fade the background music out by 1 second
        back = match_target_amplitude(back, vidSound, -12).fade_out(1000)

        combined = vidSound.overlay(back)
        combined.export(TEMP+"/audioNew.wav", format='wav')

    if(audioOnly):
        print('Moving audio.')
        move(f'{TEMP}/audioNew.wav', OUTPUT_FILE)
    else:
        print('Finishing video.')

        # ffmpeg -i 0.wav -i 1.wav -i vid.mp4 -map 0:a:0 -map 1:a:0 -map
        #  2:v:0 -c:v copy out.mp4

        cmd = ['ffmpeg', '-y']
        for i in range(tracks):
            cmd.extend(['-i', f'{TEMP}/new{i}.wav'])
        cmd.extend(['-i', TEMP+'/output'+extension]) # add input video
        for i in range(tracks):
            cmd.extend(['-map', f'{i}:a:0'])
        cmd.extend(['-map', f'{tracks}:v:0','-c:v', 'copy', '-movflags', '+faststart',
            OUTPUT_FILE])

        if(not VERBOSE):
            cmd.extend(['-nostats', '-loglevel', '0'])

        print(cmd)

        subprocess.call(cmd)

    print('Finished.')
    timeLength = round(time.time() - startTime, 2)
    minutes = timedelta(seconds=round(timeLength))
    print(f'took {timeLength} seconds ({minutes})')

    if(not os.path.isfile(OUTPUT_FILE)):
        raise IOError(f'The file {OUTPUT_FILE} was not created.')

    try: # should work on Windows
        os.startfile(OUTPUT_FILE)
    except AttributeError:
        try: # should work on MacOS and most linux versions
            subprocess.call(['open', OUTPUT_FILE])
        except:
            print('Could not open output file.')

    # reset cache folder
    if(not audioOnly):
        with open(f'{TEMP}/Renames.txt', 'r') as f:
            renames = f.read().splitlines()
            for i in range(0, len(renames), 2):
                os.rename(renames[i+1], renames[i])

    # create cache check with vid stats
    file = open(f'{CACHE}/cache.txt', 'w')
    file.write(f'{INPUT_FILE}\n{frameRate}\n{fileSize}\n{FRAME_QUALITY}\n{tracks}\n{COMBINE_TRAC}\n')

    rmtree(TEMP)
