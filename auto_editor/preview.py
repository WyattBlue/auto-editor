'''preview.py'''

# Internal Libraries
from datetime import timedelta

# Included Libraries
from auto_editor.utils.func import get_new_length

def printTimeFrame(title, frames, fps):
    in_sec = round(frames / fps, 1)
    fps = round(fps)
    if(in_sec < 1):
        minutes = '{}/{} frames'.format(int(frames), fps)
    else:
        minutes = timedelta(seconds=round(in_sec))
    print('{}: {} secs ({})'.format(title, in_sec, minutes))


def preview(inp, chunks, speeds, log):
    fps = 30 if inp.fps is None else float(inp.fps)

    old_time = chunks[len(chunks)-1][1]
    print('')
    printTimeFrame('Old length', old_time, fps)

    new_length = get_new_length(chunks, speeds, fps)
    printTimeFrame('New length', new_length * fps, fps)
    print('')

    clips = 0
    cuts = 0
    cut_lens = []
    clip_lens = []
    for chunk in chunks:
        state = chunk[2]
        if(speeds[state] != 99999):
            clips += 1
            leng = (chunk[1] - chunk[0]) / speeds[state]
            clip_lens.append(leng)
        else:
            cuts += 1
            leng = chunk[1] - chunk[0]
            cut_lens.append(leng)

    print('Number of clips: {}'.format(clips))
    if(len(clip_lens) == 1):
        printTimeFrame('Clip length', clip_lens[0], fps)
    else:
        printTimeFrame('Smallest clip length', min(clip_lens), fps)
        printTimeFrame('Largest clip length', max(clip_lens), fps)
        printTimeFrame('Average clip length', sum(clip_lens) / len(clip_lens), fps)
        print('\nNumber of cuts: {}'.format(cuts))

    if(cut_lens != []):
        if(len(cut_lens) == 1):
            printTimeFrame('Cut length', cut_lens[0], fps)
        else:
            printTimeFrame('Smallest cut length', min(cut_lens), fps)
            printTimeFrame('Largest cut length', max(cut_lens), fps)
            printTimeFrame('Average cut length', sum(cut_lens) / len(cut_lens), fps)
        print('')

    log.debug('Chunks: {}'.format(chunks))
