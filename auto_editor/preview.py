'''preview.py'''

# Internal Libraries
from datetime import timedelta

# Included Libraries
from auto_editor.utils.func import get_new_length

def display_length(secs):
    # display length
    if(secs < 0):
        return '-' + str(timedelta(seconds=round(abs(secs))))
    return str(timedelta(seconds=round(secs)))

def time_frame(title, frames, fps):
    in_sec = round(frames / fps, 1)
    minutes = timedelta(seconds=round(in_sec))
    print('{}: {} secs ({})'.format(title, in_sec, minutes))


def preview(inp, chunks, log):
    fps = 30 if inp.fps is None else float(inp.fps)

    log.conwrite('')

    old_length = chunks[-1][1] / fps
    new_length = get_new_length(chunks, fps)

    diff = new_length - old_length

    print('\nlength:\n - change: ({}) 100% -> ({}) {}%\n - diff: ({}) {}%'.format(
        display_length(old_length),
        display_length(new_length),
        round((new_length / old_length) * 100, 2),
        display_length(diff),
        round((diff / old_length) * 100, 2),
    ))

    clips = 0
    cuts = 0
    cut_lens = []
    clip_lens = []
    for chunk in chunks:
        if(chunk[2] != 99999):
            clips += 1
            leng = (chunk[1] - chunk[0]) / chunk[2]
            clip_lens.append(leng)
        else:
            cuts += 1
            leng = chunk[1] - chunk[0]
            cut_lens.append(leng)

    print('clips: {}'.format(clips))
    if(len(clip_lens) == 1):
        time_frame(' - clip length', clip_lens[0], fps)
    else:
        time_frame(' - smallest', min(clip_lens), fps)
        time_frame(' - largest', max(clip_lens), fps)
        time_frame(' - average', sum(clip_lens) / len(clip_lens), fps)
        print('cuts: {}'.format(cuts))

    if(cut_lens != []):
        if(len(cut_lens) == 1):
            time_frame(' - cut length', cut_lens[0], fps)
        else:
            time_frame(' - smallest', min(cut_lens), fps)
            time_frame(' - largest', max(cut_lens), fps)
            time_frame(' - average', sum(cut_lens) / len(cut_lens), fps)
        print('')

    log.debug('Chunks: {}'.format(chunks))
