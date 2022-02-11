from math import ceil

import av
import numpy as np

def get_np_list(path, audio_samples, sample_rate, fps, func):
    if audio_samples is not None:
        sample_count = audio_samples.shape[0]
        sample_rate_per_frame = sample_rate / fps
        audio_frame_count = ceil(sample_count / sample_rate_per_frame)
        return func((audio_frame_count), dtype=np.bool_)

    video = av.open(path, 'r').streams.video[0]
    total_frames = int(float(video.duration * video.time_base) * fps)
    return func((total_frames), dtype=np.bool_)
