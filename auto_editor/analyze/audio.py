from __future__ import annotations

import os
from math import ceil
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze.helper import get_all_list
from auto_editor.wavfile import read

if TYPE_CHECKING:
    from fractions import Fraction

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


def audio_detection(
    inp: FileInfo,
    s: int,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.float_]:

    if os.path.isfile(path := os.path.join(temp, f"{inp.index}-{s}.wav")):
        sr, samples = read(path)
    elif not strict:
        return get_all_list(inp, tb, temp, log)
    else:
        log.error(f"Audio stream '{s}' does not exist.")

    def get_max_volume(s: np.ndarray) -> float:
        return max(float(np.max(s)), -float(np.min(s)))

    max_volume = get_max_volume(samples)
    log.debug(f"Max volume: {max_volume}")

    samp_count = samples.shape[0]
    samp_per_ticks = sr / tb

    audio_ticks = ceil(samp_count / samp_per_ticks)
    log.debug(f"Audio Length: {audio_ticks}")
    log.debug(f"... without ceil: {float(samp_count / samp_per_ticks)}")

    bar.start(audio_ticks, "Analyzing audio volume")

    threshold_list = np.zeros((audio_ticks), dtype=np.float_)

    if max_volume == 0:  # Prevent dividing by zero
        return threshold_list

    # Determine when audio is silent or loud.
    for i in range(audio_ticks):
        if i % 500 == 0:
            bar.tick(i)

        start = int(i * samp_per_ticks)
        end = min(int((i + 1) * samp_per_ticks), samp_count)

        threshold_list[i] = get_max_volume(samples[start:end]) / max_volume

    bar.end()
    return threshold_list
