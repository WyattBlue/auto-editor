from __future__ import annotations

from fractions import Fraction

import av
import numpy as np
from numpy.typing import NDArray
from PIL import ImageChops, ImageFilter, ImageOps

from auto_editor.utils.bar import Bar


def new_size(size: tuple[int, int], width: int) -> tuple[int, int]:
    h, w = size
    return width, int(h * (width / w))


def motion_detection(
    path: str, track: int, tb: Fraction, bar: Bar, width: int, blur: int
) -> NDArray[np.float_]:
    container = av.open(path, "r")

    stream = container.streams.video[track]
    stream.thread_type = "AUTO"

    inaccurate_dur = int(stream.duration * stream.time_base * stream.rate)

    bar.start(inaccurate_dur, "Analyzing motion")

    prev_image = None
    image = None
    total_pixels = None
    index = 0

    threshold_list = np.zeros((1024), dtype=np.float_)

    for frame in container.decode(stream):
        prev_image = image

        index = int(frame.time * tb)
        bar.tick(index)

        if index > len(threshold_list) - 1:
            threshold_list = np.concatenate(
                (threshold_list, np.zeros((len(threshold_list)), dtype=np.float_)),
                axis=0,
            )

        image = frame.to_image()

        if total_pixels is None:
            total_pixels = image.size[0] * image.size[1]

        image.thumbnail(new_size(image.size, width))
        image = ImageOps.grayscale(image)

        if blur > 0:
            image = image.filter(ImageFilter.GaussianBlur(radius=blur))

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))

            threshold_list[index] = count / total_pixels

    bar.end()
    return threshold_list[:index]
