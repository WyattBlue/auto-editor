'''preview.py'''

# Included functions
from usefulFunctions import getNewLength

# Internal libraries
import os
from datetime import timedelta

def printTimeFrame(title: str, frames, fps: float):
    inSec = round(frames / fps, 1)
    fps = round(fps)
    if(inSec < 1):
        minutes = f'{int(frames)}/{fps} frames'
    else:
        minutes = timedelta(seconds=round(inSec))
    print(f'{title}: {inSec} secs ({minutes})')


def preview(myInput, chunks: list, speeds: list, fps: float, audioFile, log):
    if(not os.path.isfile(myInput)):
        log.error('preview.py: Could not find file ' + myInput)

    oldTime = chunks[len(chunks)-1][1]
    print('')
    printTimeFrame('Old length', oldTime, fps)

    newL = getNewLength(chunks, speeds, fps)
    printTimeFrame('New length', newL * fps, fps)
    print('')

    clips = 0
    cuts = 0
    cutL = []
    clipLengths = []
    for chunk in chunks:
        state = chunk[2]
        if(speeds[state] != 99999):
            clips += 1
            leng = (chunk[1] - chunk[0]) / speeds[state]
            clipLengths.append(leng)
        else:
            cuts += 1
            leng = chunk[1] - chunk[0]
            cutL.append(leng)

    print('Number of clips:', clips)
    printTimeFrame('Smallest clip length', min(clipLengths), fps)
    printTimeFrame('Largest clip length', max(clipLengths), fps)
    printTimeFrame('Average clip length', sum(clipLengths) / len(clipLengths), fps)
    print('\nNumber of cuts:', cuts)
    printTimeFrame('Smallest cut length', min(cutL), fps)
    printTimeFrame('Largest cut length', max(cutL), fps)
    printTimeFrame('Average cut length', sum(cutL) / len(cutL), fps)
    print('')
    if(not audioFile):
        print('Video framerate:', fps)
    log.debug(f'Chunks:\n{chunks}')
