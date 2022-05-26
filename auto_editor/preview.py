from statistics import fmean, median
from typing import List, Tuple

from auto_editor.timeline import Timeline
from auto_editor.utils.func import to_timecode
from auto_editor.utils.log import Log


def display(secs: float) -> str:
    return to_timecode(round(secs), "rass")


def time_frame(title: str, frames: float, fps: float) -> None:
    tc = to_timecode(frames / fps, "ass")
    preci = 0 if int(frames) == frames else 2
    print(f" - {f'{title}:':<10} {tc:<12} ({frames:.{preci}f})")


def preview(timeline: Timeline, log: Log) -> None:
    log.conwrite("")

    fps = timeline.fps
    in_len = sum([inp.fdur for inp in timeline.inputs])

    out_len: float = 0
    for vclips in timeline.v:
        dur: float = 0
        for vclip in vclips:
            dur += vclip.dur / vclip.speed
        out_len = max(out_len, dur / fps)
    for aclips in timeline.a:
        dur = 0
        for aclip in aclips:
            dur += aclip.dur / aclip.speed
        out_len = max(out_len, dur / fps)

    diff = out_len - in_len

    print(
        f"\nlength:\n - change: ({display(in_len)}) 100% -> "
        f"({display(out_len)}) {round((out_len / in_len) * 100, 2)}%\n "
        f"- diff: ({display(diff)}) {round((diff / in_len) * 100, 2)}%"
    )

    clip_lens = [clip.dur / clip.speed for clip in timeline.a[0]]

    # Calculate cuts
    oe: List[Tuple[int, int]] = []

    # TODO: Make offset_end_pairs work on overlapping clips.
    for clip in timeline.a[0]:
        oe.append((clip.offset, clip.offset + clip.dur))

    cut_lens = []
    i = 0
    while i < len(oe) - 1:
        if i == 0 and oe[i][0] != 0:
            cut_lens.append(oe[i][1])

        cut_lens.append(oe[i + 1][0] - oe[i][1])
        i += 1

    if len(oe) > 0 and oe[-1][1] < round(in_len * fps):
        cut_lens.append(round(in_len * fps) - oe[-1][1])

    print(f"clips: {len(clip_lens)}")
    log.debug(clip_lens)
    if len(clip_lens) == 0:
        clip_lens = [0]
    time_frame("smallest", min(clip_lens), fps)
    time_frame("largest", max(clip_lens), fps)
    if len(clip_lens) > 1:
        time_frame("median", median(clip_lens), fps)
        time_frame("average", fmean(clip_lens), fps)

    print(f"cuts: {len(cut_lens)}")
    log.debug(cut_lens)
    if len(cut_lens) == 0:
        cut_lens = [0]
    time_frame("smallest", min(cut_lens), fps)
    time_frame("largest", max(cut_lens), fps)
    if len(cut_lens) > 1:
        time_frame("median", median(cut_lens), fps)
        time_frame("average", fmean(cut_lens), fps)
    print("")
