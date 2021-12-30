'''analyze/audio.py'''

import numpy as np
import math

from auto_editor.utils.log import Log

def get_max_volume(s: np.ndarray) -> float:
    return max(float(np.max(s)), -float(np.min(s)))


def display_audio_levels(read_track, fps: float):
    import sys

    from auto_editor.scipy.wavfile import read

    sample_rate, audio_samples = read(read_track)

    max_volume = get_max_volume(audio_samples)
    sample_count = audio_samples.shape[0]

    sample_rate_per_frame = sample_rate / fps
    audio_frame_count = math.ceil(sample_count / sample_rate_per_frame)

    for i in range(audio_frame_count):
        start = int(i * sample_rate_per_frame)
        end = min(int((i+1) * sample_rate_per_frame), sample_count)
        audiochunks = audio_samples[start:end]
        sys.stdout.write('{:.20f}\n'.format(get_max_volume(audiochunks) / max_volume))


def audio_detection(audio_samples, sample_rate, silent_threshold, fps, log):
    # type: (np.ndarray, int, float, float, Log) -> np.ndarray
    log.conwrite('Analyzing audio volume.')

    max_volume = get_max_volume(audio_samples)
    sample_count = audio_samples.shape[0]

    sample_rate_per_frame = sample_rate / fps
    audio_frame_count = math.ceil(sample_count / sample_rate_per_frame)
    has_loud_audio = np.zeros((audio_frame_count), dtype=np.bool_)

    # Calculate when the audio is loud or silent.
    for i in range(audio_frame_count):
        start = int(i * sample_rate_per_frame)
        end = min(int((i+1) * sample_rate_per_frame), sample_count)
        audiochunks = audio_samples[start:end]
        if(get_max_volume(audiochunks) / max_volume > silent_threshold):
            has_loud_audio[i] = True

    return has_loud_audio
