# Internal Libraries
from datetime import timedelta

# Typing
from typing import List, Tuple, Union

# Included Libraries
from auto_editor.utils.func import get_new_length
from auto_editor.utils.log import Log
from auto_editor.ffwrapper import FileInfo


def display_length(secs: Union[int, float]) -> str:
    if secs < 0:
        return '-' + str(timedelta(seconds=round(abs(secs))))
    return str(timedelta(seconds=round(secs)))

def time_frame(title: str, frames: Union[int, float], fps: float) -> None:
    in_sec = round(frames / fps, 1)
    minutes = timedelta(seconds=round(in_sec))
    print(f'{title}: {in_sec} secs ({minutes})')


def preview(inp: FileInfo, chunks: List[Tuple[int, int, float]], log: Log) -> None:
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
        if chunk[2] != 99999:
            clips += 1
            leng = (chunk[1] - chunk[0]) / chunk[2]
            clip_lens.append(leng)
        else:
            cuts += 1
            leng = chunk[1] - chunk[0]
            cut_lens.append(leng)

    print(f'clips: {clips}')
    if len(clip_lens) < 2:
        time_frame(' - clip length', sum(clip_lens), fps)
    else:
        time_frame(' - smallest', min(clip_lens), fps)
        time_frame(' - largest', max(clip_lens), fps)
        time_frame(' - average', sum(clip_lens) / len(clip_lens), fps)

    print(f'cuts: {cuts}')
    if len(cut_lens) < 2:
        time_frame(' - cut length', sum(cut_lens), fps)
    else:
        time_frame(' - smallest', min(cut_lens), fps)
        time_frame(' - largest', max(cut_lens), fps)
        time_frame(' - average', sum(cut_lens) / len(cut_lens), fps)
    print('')

    log.debug(f'Chunks: {chunks}')
