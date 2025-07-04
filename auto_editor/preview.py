from __future__ import annotations

import sys
from fractions import Fraction
from statistics import fmean, median
from typing import TextIO

from auto_editor.analyze import initLevels
from auto_editor.timeline import v3
from auto_editor.utils.bar import initBar
from auto_editor.utils.func import to_timecode
from auto_editor.utils.log import Log


def time_frame(
    fp: TextIO, title: str, ticks: float, tb: Fraction, per: str | None = None
) -> None:
    tc = to_timecode(ticks / tb, "ass")

    tp = 9 if tc.startswith("-") else 10
    tcp = 12 if tc.startswith("-") else 11
    preci = 0 if int(ticks) == ticks else 2
    end = "" if per is None else f" {per:>7}"

    fp.write(f" - {f'{title}:':<{tp}} {tc:<{tcp}} {f'({ticks:.{preci}f})':<6}{end}\n")


def all_cuts(tl: v3, in_len: int) -> list[int]:
    # Calculate cuts
    tb = tl.tb
    clip_spans: list[tuple[int, int]] = []

    for clip in tl.a[0]:
        old_offset = clip.offset * clip.speed
        clip_spans.append((round(old_offset), round(old_offset + clip.dur)))

    cut_lens = []
    i = 0
    while i < len(clip_spans) - 1:
        if i == 0 and clip_spans[i][0] != 0:
            cut_lens.append(clip_spans[i][0])

        cut_lens.append(clip_spans[i + 1][0] - clip_spans[i][1])
        i += 1

    if len(clip_spans) > 0 and clip_spans[-1][1] < round(in_len / tb):
        cut_lens.append(in_len - clip_spans[-1][1])

    return cut_lens


def preview(tl: v3, log: Log) -> None:
    log.conwrite("")
    tb = tl.tb

    # Calculate input videos length
    in_len = 0
    bar = initBar("none")
    for src in tl.unique_sources():
        in_len += initLevels(src, tb, bar, False, log).media_length

    out_len = len(tl)
    diff = out_len - in_len

    fp = sys.stdout
    fp.write("\nlength:\n")
    time_frame(fp, "input", in_len, tb, "100.0%")
    time_frame(fp, "output", out_len, tb, f"{round((out_len / in_len) * 100, 2)}%")
    time_frame(fp, "diff", diff, tb, f"{round((diff / in_len) * 100, 2)}%")

    clip_lens = [clip.dur for clip in tl.a[0]]
    log.debug(clip_lens)

    fp.write(f"clips:\n - amount:    {len(clip_lens)}\n")
    if len(clip_lens) > 0:
        time_frame(fp, "smallest", min(clip_lens), tb)
        time_frame(fp, "largest", max(clip_lens), tb)
    if len(clip_lens) > 1:
        time_frame(fp, "median", median(clip_lens), tb)
        time_frame(fp, "average", fmean(clip_lens), tb)

    cut_lens = all_cuts(tl, in_len)
    log.debug(cut_lens)
    fp.write(f"cuts:\n - amount:    {len(cut_lens)}\n")
    if len(cut_lens) > 0:
        time_frame(fp, "smallest", min(cut_lens), tb)
        time_frame(fp, "largest", max(cut_lens), tb)
    if len(cut_lens) > 1:
        time_frame(fp, "median", median(cut_lens), tb)
        time_frame(fp, "average", fmean(cut_lens), tb)

    fp.write("\n")
    fp.flush()
