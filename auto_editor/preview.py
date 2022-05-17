from datetime import timedelta

from auto_editor.ffwrapper import FileInfo
from auto_editor.timeline import Timeline
from auto_editor.utils.log import Log


def display(secs: float) -> str:
    if secs < 0:
        return f"-{timedelta(seconds=round(abs(secs)))}"
    return f"{timedelta(seconds=round(secs))}"


def time_frame(title: str, frames: float, fps: float) -> None:
    in_sec = round(frames / fps, 1)
    minutes = timedelta(seconds=round(in_sec))
    print(f"{title}: {in_sec} secs ({minutes})")


def preview(timeline: Timeline, log: Log) -> None:
    log.conwrite("")

    fps = timeline.fps

    old_length = sum([inp.fdur for inp in timeline.inputs])

    # TODO: Fix
    new_length = 0
    if len(timeline.vclips) > 0:
        dur = 0
        for clip in timeline.vclips[0]:
            dur += (clip.offset + clip.dur) / clip.speed
        new_length = max(new_length, dur / fps)

    if len(timeline.aclips) > 0:
        dur = 0
        for clip in timeline.aclips[0]:
            dur += (clip.offset + clip.dur) / clip.speed
        new_length = max(new_length, dur / fps)

    diff = new_length - old_length

    print(
        f"\nlength:\n - change: ({display(old_length)}) 100% -> "
        f"({display(new_length)}) {round((new_length / old_length) * 100, 2)}%\n "
        f"- diff: ({display(diff)}) {round((diff / old_length) * 100, 2)}%"
    )

    chunks = timeline.chunks
    if chunks is not None:
        clips = 0
        cuts = 0
        cut_lens = []
        clip_lens = []
        for chunk in timeline.chunks:
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
            time_frame(" - clip length", sum(clip_lens), fps)
        else:
            time_frame(" - smallest", min(clip_lens), fps)
            time_frame(" - largest", max(clip_lens), fps)
            time_frame(" - average", sum(clip_lens) / len(clip_lens), fps)

        print(f"cuts: {cuts}")
        if len(cut_lens) < 2:
            time_frame(" - cut length", sum(cut_lens), fps)
        else:
            time_frame(" - smallest", min(cut_lens), fps)
            time_frame(" - largest", max(cut_lens), fps)
            time_frame(" - average", sum(cut_lens) / len(cut_lens), fps)
    print("")
