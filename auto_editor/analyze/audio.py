import numpy as np
import numpy.typing as npt
from math import ceil

from auto_editor.utils.progressbar import ProgressBar


def get_max_volume(s: np.ndarray) -> float:
    return max(float(np.max(s)), -float(np.min(s)))


def audio_detection(
    audio_samples: np.ndarray,
    sample_rate: int,
    fps: float,
    progress: ProgressBar,
) -> npt.NDArray[np.float_]:

    max_volume = get_max_volume(audio_samples)

    if max_volume == 0:
        # Prevent dividing by zero
        max_volume = 1

    sample_count = audio_samples.shape[0]

    sample_rate_per_frame = sample_rate / fps
    audio_frame_count = ceil(sample_count / sample_rate_per_frame)

    progress.start(audio_frame_count, "Analyzing audio volume")

    threshold_list = np.zeros((audio_frame_count), dtype=np.float_)

    # Calculate when the audio is loud or silent.
    for i in range(audio_frame_count):

        if i % 500 == 0:
            progress.tick(i)

        start = int(i * sample_rate_per_frame)
        end = min(int((i + 1) * sample_rate_per_frame), sample_count)

        threshold_list[i] = get_max_volume(audio_samples[start:end]) / max_volume

    progress.end()
    return threshold_list
