from typing import Tuple

import av
import numpy as np
from numpy.typing import NDArray
from PIL import ImageOps, ImageChops, ImageFilter

from auto_editor.utils.progressbar import ProgressBar


def new_size(size: Tuple[int, int], width: int) -> Tuple[int, int]:
    h, w = size
    return width, int(h * (width / w))


def motion_detection(
    path: str, fps: float, progress: ProgressBar, width: int, blur: int
) -> NDArray[np.float_]:
    container = av.open(path, "r")

    stream = container.streams.video[0]
    stream.thread_type = "AUTO"

    inaccurate_dur = int(stream.duration * stream.time_base * stream.rate)

    progress.start(inaccurate_dur, "Analyzing motion")

    prev_image = None
    image = None
    total_pixels = None
    index = 0

    threshold_list = np.zeros((1024), dtype=np.float_)

    for frame in container.decode(stream):
        if image is None:
            prev_image = None
        else:
            prev_image = image

        index = int(frame.time * fps)

        progress.tick(index)

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

    progress.end()
    return threshold_list[:index]
