import numpy as np
from math import ceil

from auto_editor.utils.progressbar import ProgressBar

def get_max_volume(s: np.ndarray) -> float:
    return max(float(np.max(s)), -float(np.min(s)))


def display_audio_levels(read_track, fps: float):
    import sys

    from auto_editor.scipy.wavfile import read

    sample_rate, audio_samples = read(read_track)

    max_volume = get_max_volume(audio_samples)
    sample_count = audio_samples.shape[0]

    sample_rate_per_frame = sample_rate / fps
    audio_frame_count = ceil(sample_count / sample_rate_per_frame)

    for i in range(audio_frame_count):
        start = int(i * sample_rate_per_frame)
        end = min(int((i+1) * sample_rate_per_frame), sample_count)
        audiochunks = audio_samples[start:end]
        sys.stdout.write('{:.20f}\n'.format(get_max_volume(audiochunks) / max_volume))


def audio_detection(
    audio_samples: np.ndarray,
    sample_rate: int,
    silent_threshold: float,
    fps: float,
    progress: ProgressBar,
    ) -> np.ndarray:

    max_volume = get_max_volume(audio_samples)
    sample_count = audio_samples.shape[0]

    sample_rate_per_frame = sample_rate / fps
    audio_frame_count = ceil(sample_count / sample_rate_per_frame)

    progress.start(audio_frame_count, 'Analyzing audio volume')

    has_loud_audio = np.zeros((audio_frame_count), dtype=np.bool_)

    # Calculate when the audio is loud or silent.
    for i in range(audio_frame_count):

        if i % 500 == 0:
            progress.tick(i)

        start = int(i * sample_rate_per_frame)
        end = min(int((i+1) * sample_rate_per_frame), sample_count)

        if get_max_volume(audio_samples[start:end]) / max_volume > silent_threshold:
            has_loud_audio[i] = True

    progress.end()
    return has_loud_audio
