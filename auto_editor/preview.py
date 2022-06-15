from statistics import fmean, median
from typing import List, Optional, Tuple

from auto_editor.method import get_media_duration
from auto_editor.timeline import Timeline
from auto_editor.utils.func import to_timecode
from auto_editor.utils.log import Log


def time_frame(
    title: str, frames: float, fps: float, per: Optional[str] = None
) -> None:
    tc = to_timecode(frames / fps, "ass")

    tp = 9 if tc.startswith("-") else 10
    tcp = 12 if tc.startswith("-") else 11
    preci = 0 if int(frames) == frames else 2
    end = "" if per is None else f" {per:>7}"
    print(f" - {f'{title}:':<{tp}} {tc:<{tcp}} {f'({frames:.{preci}f})':<6}{end}")


def preview(timeline: Timeline, temp: str, log: Log) -> None:
    log.conwrite("")
    fps = timeline.fps

    # Calculate input videos length
    in_len = 0
    for inp in timeline.inputs:
        in_len += get_media_duration(inp.path, inp.get_fps(), temp, log)

    out_len = timeline.out_len()

    diff = out_len - in_len

    print("\nlength:")
    time_frame("input", in_len, fps, per="100.0%")
    time_frame("output", out_len, fps, per=f"{round((out_len / in_len) * 100, 2)}%")
    time_frame("diff", diff, fps, per=f"{round((diff / in_len) * 100, 2)}%")

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
        cut_lens.append(in_len - oe[-1][1])

    log.debug(clip_lens)
    if len(clip_lens) == 0:
        clip_lens = [0]
    print(f"clips:\n - amount:    {len(clip_lens)}")
    time_frame("smallest", min(clip_lens), fps)
    time_frame("largest", max(clip_lens), fps)
    if len(clip_lens) > 1:
        time_frame("median", median(clip_lens), fps)
        time_frame("average", fmean(clip_lens), fps)

    log.debug(cut_lens)
    if len(cut_lens) == 0:
        cut_lens = [0]
    print(f"cuts:\n - amount:    {len(clip_lens)}")
    time_frame("smallest", min(cut_lens), fps)
    time_frame("largest", max(cut_lens), fps)
    if len(cut_lens) > 1:
        time_frame("median", median(cut_lens), fps)
        time_frame("average", fmean(cut_lens), fps)
    print("")
