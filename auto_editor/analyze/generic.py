'''analyze/generic.py'''

import math
import numpy as np

def get_np_list(inp, audio_samples, sample_rate, fps, func):
    if(audio_samples is not None):
        sample_count = audio_samples.shape[0]
        sample_rate_per_frame = sample_rate / fps
        audio_frame_count = int(math.ceil(sample_count / sample_rate_per_frame))
        return func((audio_frame_count), dtype=np.bool_)

    import cv2
    cap = cv2.VideoCapture(inp.path)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) + 1
    return func((total_frames), dtype=np.bool_)
