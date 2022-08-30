from __future__ import annotations

from fractions import Fraction
from statistics import fmean, median

from auto_editor.analyze import get_media_length
from auto_editor.output import Ensure
from auto_editor.timeline import Timeline
from auto_editor.utils.func import to_timecode
from auto_editor.utils.log import Log


def time_frame(title: str, ticks: float, tb: Fraction, per: str | None = None) -> None:
    tc = to_timecode(ticks / tb, "ass")

    tp = 9 if tc.startswith("-") else 10
    tcp = 12 if tc.startswith("-") else 11
    preci = 0 if int(ticks) == ticks else 2
    end = "" if per is None else f" {per:>7}"
    print(f" - {f'{title}:':<{tp}} {tc:<{tcp}} {f'({ticks:.{preci}f})':<6}{end}")


def all_cuts(tl: Timeline, in_len: int) -> list[int]:
    # Calculate cuts
    tb = tl.timebase
    oe: list[tuple[int, int]] = []

    # TODO: Make offset_end_pairs work on overlapping clips.
    for clip in tl.a[0]:
        oe.append((clip.offset, clip.offset + clip.dur))

    cut_lens = []
    i = 0
    while i < len(oe) - 1:
        if i == 0 and oe[i][0] != 0:
            cut_lens.append(oe[i][1])

        cut_lens.append(oe[i + 1][0] - oe[i][1])
        i += 1

    if len(oe) > 0 and oe[-1][1] < round(in_len * tb):
        cut_lens.append(in_len - oe[-1][1])
    return cut_lens


def preview(ensure: Ensure, tl: Timeline, temp: str, log: Log) -> None:
    log.conwrite("")
    tb = tl.timebase

    # Calculate input videos length
    in_len = 0
    for inp in tl.inputs:
        in_len += get_media_length(ensure, inp, tl.timebase, temp, log)

    out_len = tl.out_len()

    diff = out_len - in_len

    print("\nlength:")
    time_frame("input", in_len, tb, per="100.0%")
    time_frame("output", out_len, tb, per=f"{round((out_len / in_len) * 100, 2)}%")
    time_frame("diff", diff, tb, per=f"{round((diff / in_len) * 100, 2)}%")

    clip_lens = [clip.dur / clip.speed for clip in tl.a[0]]
    log.debug(clip_lens)

    print(f"clips:\n - amount:    {len(clip_lens)}")
    if len(clip_lens) > 0:
        time_frame("smallest", min(clip_lens), tb)
        time_frame("largest", max(clip_lens), tb)
    if len(clip_lens) > 1:
        time_frame("median", median(clip_lens), tb)
        time_frame("average", fmean(clip_lens), tb)

    cut_lens = all_cuts(tl, in_len)
    log.debug(cut_lens)
    print(f"cuts:\n - amount:    {len(clip_lens)}")
    if len(cut_lens) > 0:
        time_frame("smallest", min(cut_lens), tb)
        time_frame("largest", max(cut_lens), tb)
    if len(cut_lens) > 1:
        time_frame("median", median(cut_lens), tb)
        time_frame("average", fmean(cut_lens), tb)
    print("")
