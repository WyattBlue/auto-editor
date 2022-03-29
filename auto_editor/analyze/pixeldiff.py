import sys

import av
import numpy as np
from PIL import ImageOps, ImageChops, ImageFilter

from auto_editor.utils.progressbar import ProgressBar


def display_pixel_diff(path: str) -> None:

    container = av.open(path, 'r')

    video_stream = container.streams.video[0]
    video_stream.thread_type = 'AUTO'

    prev_image = None
    image = None

    for frame in container.decode(video_stream):
        if image is None:
            prev_image = None
        else:
            prev_image = image

        image = frame.to_image()

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))
            sys.stdout.write(f'{count}\n')


def pixel_difference(path: str, fps: float, threshold: int, progress: ProgressBar) -> np.ndarray:

    container = av.open(path, 'r')

    video_stream = container.streams.video[0]
    video_stream.thread_type = 'AUTO'

    inaccurate_dur = int(float(video_stream.duration * video_stream.time_base) * fps)

    progress.start(inaccurate_dur, 'Analyzing pixel diffs')

    prev_image = None
    image = None
    index = 0

    has_motion = np.zeros((1024), dtype=np.bool_)

    for frame in container.decode(video_stream):
        if image is None:
            prev_image = None
        else:
            prev_image = image

        index = int(frame.time * fps)

        progress.tick(index)

        if index > len(has_motion) - 1:
            has_motion = np.concatenate(
                (has_motion, np.zeros((len(has_motion)), dtype=np.bool_)), axis=0
            )

        image = frame.to_image()

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))

            if count >= threshold:
                has_motion[index] = True

    progress.end()
    return has_motion[:index]
