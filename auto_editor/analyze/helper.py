from __future__ import annotations

import os
from fractions import Fraction
from math import ceil

import numpy as np
from numpy.typing import NDArray

from auto_editor.utils.log import Log
from auto_editor.wavfile import read


def to_threshold(arr: np.ndarray, t: int | float) -> NDArray[np.bool_]:
    return np.fromiter((x >= t for x in arr), dtype=np.bool_)


def get_media_length(path: str, i: int, tb: Fraction, temp: str, log: Log) -> int:
    # Read first audio track.
    if os.path.isfile(path := os.path.join(temp, f"{i}-0.wav")):
        sr, samples = read(path)
        samp_count = len(samples)
        del samples

        samp_per_ticks = sr / tb
        ticks = ceil(samp_count / samp_per_ticks)
        log.debug(f"Audio Length: {ticks}")
        log.debug(f"... without ceil: {float(samp_count / samp_per_ticks)}")
        return ticks

    # If there's no audio, get length in video metadata.
    import av

    av.logging.set_level(av.logging.PANIC)

    with av.open(path, "r") as cn:
        if len(cn.streams.video) < 1:
            log.error("Could not get media duration")

        video = cn.streams.video[0]
        dur = int(video.duration * video.time_base * tb)
        log.debug(f"Video duration: {dur}")

    return dur


def get_all_list(
    path: str, i: int, tb: Fraction, temp: str, log: Log
) -> NDArray[np.bool_]:
    return np.zeros(get_media_length(path, i, tb, temp, log) - 1, dtype=np.bool_)


def get_none_list(
    path: str, i: int, tb: Fraction, temp: str, log: Log
) -> NDArray[np.bool_]:
    return np.ones(get_media_length(path, i, tb, temp, log) - 1, dtype=np.bool_)
