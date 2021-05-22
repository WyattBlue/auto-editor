'''preview.py'''

# Internal Libraries
import os
from datetime import timedelta

# Included Libraries
from auto_editor.usefulFunctions import getNewLength

def printTimeFrame(title: str, frames, fps: float):
    in_sec = round(frames / fps, 1)
    fps = round(fps)
    if(in_sec < 1):
        minutes = '{}/{} frames'.format(int(frames), fps)
    else:
        minutes = timedelta(seconds=round(in_sec))
    print('{}: {} secs ({})'.format(title, in_sec, minutes))


def preview(myInput, chunks: list, speeds: list, fps: float, audioFile, log):
    old_time = chunks[len(chunks)-1][1]
    print('')
    printTimeFrame('Old length', old_time, fps)

    new_length = getNewLength(chunks, speeds, fps)
    printTimeFrame('New length', new_length * fps, fps)
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

    if(cutL != []):
        printTimeFrame('Smallest cut length', min(cutL), fps)
        printTimeFrame('Largest cut length', max(cutL), fps)
        printTimeFrame('Average cut length', sum(cutL) / len(cutL), fps)
        print('')

    if(not audioFile):
        print('Video framerate:', fps)
    log.debug(f'Chunks:\n{chunks}')
