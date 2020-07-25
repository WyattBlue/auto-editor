'''scripts/originalVid.py'''

import numpy as np
from PIL import Image

from wavfile import read, write
from usefulFunctions import progressBar

import os
import math
import time
import subprocess
from shutil import copyfile

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


def splitVideo(ffmpeg, chunks, speeds, frameRate, zooms, samplesPerFrame,
    SAMPLE_RATE, audioData, extension, verbose, TEMP, CACHE):
    Renames = []
    lastExisting = None
    remander = 0
    outputFrame = 0

    lastChunk = chunks[len(chunks)-1][1]
    nums = 0
    beginTime = time.time()

    for chunk in chunks:
        for inputFrame in range(chunk[0], chunk[1]):
            nums += 1
            progressBar(min(nums, lastChunk-1), lastChunk, beginTime,
                title='Creating new video.')

            doIt = 1 / speeds[chunk[2]] + remander
            for __ in range(int(doIt)):
                outputFrame += 1

                src = ''.join([CACHE, '/frame{:06d}'.format(inputFrame+1), '.jpg'])
                dst = ''.join([TEMP, '/newFrame{:06d}'.format(outputFrame), '.jpg'])

                if(os.path.isfile(src)):
                    lastExisting = inputFrame
                    if(inputFrame in zooms):
                        resize(src, dst, zooms[inputFrame])
                    else:
                        os.rename(src, dst)
                        Renames.extend([src, dst])
                else:
                    if(lastExisting is None):
                        raise IOError(f'Error! No existing frame exist.')
                    src = ''.join([CACHE, '/frame{:06d}'.format(lastExisting+1), '.jpg'])
                    if(os.path.isfile(src)):
                        if(lastExisting in zooms):
                            resize(src, dst, zooms[lastExisting])
                        else:
                            os.rename(src, dst)
                            Renames.extend([src, dst])
                    else:
                        # Uh oh, we need to find the file we just renamed!
                        myFile = None
                        for i in range(0, len(Renames), 2):
                            if(Renames[i] == src):
                                myFile = Renames[i+1]
                                break
                        if(myFile is not None):
                            copyfile(myFile, dst)
                        else:
                            raise IOError(f'Error! The file {src} does not exist.')
            remander = doIt % 1


    with open(f'{TEMP}/Renames.txt', 'w') as f:
        for item in Renames:
            f.write(f"{item}\n")

    cmd = [ffmpeg, '-y', '-framerate', str(frameRate), '-i',
        f'{TEMP}/newFrame%06d.jpg', f'{TEMP}/output{extension}']
    if(not verbose):
        cmd.extend(['-nostats', '-loglevel', '0'])
    subprocess.call(cmd)
