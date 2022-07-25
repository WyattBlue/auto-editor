from fractions import Fraction

import av
import numpy as np
from numpy.typing import NDArray
from PIL import ImageChops

from auto_editor.utils.bar import Bar


def pixel_difference(
    path: str, track: int, tb: Fraction, bar: Bar
) -> NDArray[np.uint64]:
    container = av.open(path, "r")

    stream = container.streams.video[track]
    stream.thread_type = "AUTO"

    inaccurate_dur = int(stream.duration * stream.time_base * stream.rate)

    bar.start(inaccurate_dur, "Analyzing pixel diffs")

    prev_image = None
    image = None
    index = 0

    threshold_list = np.zeros((1024), dtype=np.uint64)

    for frame in container.decode(stream):
        prev_image = image

        index = int(frame.time * tb)
        bar.tick(index)

        if index > len(threshold_list) - 1:
            threshold_list = np.concatenate(
                (threshold_list, np.zeros((len(threshold_list)), dtype=np.uint64)),
                axis=0,
            )

        image = frame.to_image()

        if prev_image is not None:
            threshold_list[index] = np.count_nonzero(
                ImageChops.difference(prev_image, image)
            )

    bar.end()
    return threshold_list[:index]
