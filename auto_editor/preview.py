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
        return "-" + str(timedelta(seconds=round(abs(secs))))
    return str(timedelta(seconds=round(secs)))


def time_frame(title: str, frames: Union[int, float], fps: float) -> None:
    in_sec = round(frames / fps, 1)
    minutes = timedelta(seconds=round(in_sec))
    print(f"{title}: {in_sec} secs ({minutes})")


def preview(inp: FileInfo, chunks: List[Tuple[int, int, float]], log: Log) -> None:
    log.conwrite("")

    old_length = chunks[-1][1] / inp.gfps
    new_length = get_new_length(chunks, inp.gfps)

    diff = new_length - old_length

    print(
        f"\nlength:\n - change: ({display_length(old_length)}) 100% -> "
        f"({display_length(new_length)}) {round((new_length / old_length) * 100, 2)}%\n "
        f"- diff: ({display_length(diff)}) {round((diff / old_length) * 100, 2)}%"
    )

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

    print(f"clips: {clips}")
    if len(clip_lens) < 2:
        time_frame(" - clip length", sum(clip_lens), inp.gfps)
    else:
        time_frame(" - smallest", min(clip_lens), inp.gfps)
        time_frame(" - largest", max(clip_lens), inp.gfps)
        time_frame(" - average", sum(clip_lens) / len(clip_lens), inp.gfps)

    print(f"cuts: {cuts}")
    if len(cut_lens) < 2:
        time_frame(" - cut length", sum(cut_lens), inp.gfps)
    else:
        time_frame(" - smallest", min(cut_lens), inp.gfps)
        time_frame(" - largest", max(cut_lens), inp.gfps)
        time_frame(" - average", sum(cut_lens) / len(cut_lens), inp.gfps)
    print("")

    log.debug(f"Chunks: {chunks}")
