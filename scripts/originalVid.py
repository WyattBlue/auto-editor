'''originalVid.py'''

import numpy as np
from audiotsm import phasevocoder
from audiotsm.io.wav import WavReader, WavWriter
from scipy.io import wavfile
from PIL import Image

import os
import math
import subprocess
from shutil import copyfile

TEMP = '.TEMP'
CACHE = '.CACHE'

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
    """
    This function is responsible for outputting a new image sequence in the correct order.

    splitVideo is also responsible for creating Renames.txt. copying every jpeg is
    computationally expensive, renaming the file is less so, but we still need to create
    the cache folder and we can't do that if the program has no idea what it renamed
    and where. Renames.txt will be read in originalMethod.py to recreate the original
    image sequence.

    To avoid desyncing issues with the audio, we need to have audioData and go along
    roughly the same way originalAudio.py does it. Specifically, get the length of the
    new audio chunk.

    If the speed set is 1, this is easy. If not, we have to create a new file modified
    to be the new speed with audiotsm, then read that file to get the length.
    """
    print('Creating new video.')
    num = 0
    chunk_len = str(len(chunks))
    outputPointer = 0
    Renames = []
    lastExisting = None
    for chunk in chunks:
        if(NEW_SPEED[int(chunk[2])] < 99999):
            audioChunk = audioData[int(chunk[0]*samplesPerFrame):int(chunk[1]*samplesPerFrame)]
            if(NEW_SPEED[chunk[2]] == 1):
                leng = len(audioChunk)
            else:
                sFile = TEMP + '/tempStart2.wav'
                eFile = TEMP + '/tempEnd2.wav'
                wavfile.write(sFile, SAMPLE_RATE, audioChunk)
                with WavReader(sFile) as reader:
                    with WavWriter(eFile, reader.channels, reader.samplerate) as writer:
                        phasevocoder(reader.channels, speed=NEW_SPEED[chunk[2]]).run(reader, writer)
                __, alteredAudioData = wavfile.read(eFile)
                leng = alteredAudioData.shape[0]

            endPointer = outputPointer + leng

            startOutputFrame = int(math.ceil(outputPointer/samplesPerFrame))
            endOutputFrame = int(math.ceil(endPointer/samplesPerFrame))
            for outputFrame in range(startOutputFrame, endOutputFrame):
                inputFrame = int(chunk[0]+NEW_SPEED[chunk[2]]*(outputFrame-startOutputFrame))

                src = ''.join([CACHE, '/frame{:06d}'.format(inputFrame+1), '.jpg'])
                dst = ''.join([TEMP, '/newFrame{:06d}'.format(outputFrame+1), '.jpg'])
                if(os.path.isfile(src)):
                    lastExisting = inputFrame
                    if(inputFrame in zooms):
                        resize(src, dst, zooms[inputFrame])
                    else:
                        os.rename(src, dst)
                        Renames.extend([src, dst])
                else:
                    if(lastExisting == None):
                        print(src + ' does not exist.')
                        raise IOError(f'Fatal Error! No existing frame exist.')
                    src = ''.join([CACHE, '/frame{:06d}'.format(lastExisting+1), '.jpg'])
                    if(os.path.isfile(src)):
                        if(lastExisting in zooms):
                            resize(src, dst, zooms[lastExisting])
                        else:
                            os.rename(src, dst)
                            Renames.extend([src, dst])
                    else:
                        # uh oh, we need to find the file we just renamed!
                        myFile = None
                        for i in range(0, len(Renames), 2):
                            if(Renames[i] == src):
                                myFile = Renames[i+1]
                                break
                        if(myFile is not None):
                            copyfile(myFile, dst)
                        else:
                            raise IOError(f'Error! The file {src} does not exist.')

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
