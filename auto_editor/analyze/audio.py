from math import ceil

import numpy as np
import numpy.typing as npt

from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar


def get_max_volume(s: np.ndarray) -> float:
    return max(float(np.max(s)), -float(np.min(s)))


def audio_length(samp_count: int, sample_rate: int, timebase: int, log: Log) -> int:
    assert isinstance(timebase, int)
    samp_per_ticks = sample_rate / timebase
    ticks = ceil(samp_count / samp_per_ticks)
    log.debug(f"Audio Length: {ticks}")
    log.debug(f"... without ceil: {float(samp_count / samp_per_ticks)}")
    return ticks


def audio_detection(
    audio_samples: np.ndarray,
    sample_rate: int,
    timebase: int,
    progress: ProgressBar,
    log: Log,
) -> npt.NDArray[np.float_]:

    max_volume = get_max_volume(audio_samples)
    log.debug(f"Max volume: {max_volume}")

    samp_count = audio_samples.shape[0]
    samp_per_ticks = sample_rate / timebase

    audio_ticks = audio_length(samp_count, sample_rate, timebase, log)
    progress.start(audio_ticks, "Analyzing audio volume")

    threshold_list = np.zeros((audio_ticks), dtype=np.float_)

    if max_volume == 0:  # Prevent dividing by zero
        return threshold_list

    # Determine when audio is silent or loud.
    for i in range(audio_ticks):
        if i % 500 == 0:
            progress.tick(i)

        start = int(i * samp_per_ticks)
        end = min(int((i + 1) * samp_per_ticks), samp_count)

        threshold_list[i] = get_max_volume(audio_samples[start:end]) / max_volume

    progress.end()
    return threshold_list
