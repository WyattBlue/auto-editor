from __future__ import annotations

from typing import TYPE_CHECKING

import av
import numpy as np
from PIL import ImageChops, ImageFilter, ImageOps

from auto_editor.analyze.helper import get_all_list

if TYPE_CHECKING:
    from fractions import Fraction

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


av.logging.set_level(av.logging.PANIC)


def new_size(size: tuple[int, int], width: int) -> tuple[int, int]:
    h, w = size
    return width, int(h * (width / w))


def motion_detection(
    inp: FileInfo, i: int, mobj, tb: Fraction, bar: Bar, strict: bool, temp: str, log: Log
) -> NDArray[np.float_]:

    if mobj.stream >= len(inp.videos):
        if not strict:
            return get_all_list(inp.path, i, tb, temp, log)
        log.error(f"Video stream '{mobj.stream}' does not exist.")

    container = av.open(inp.path, "r")

    stream = container.streams.video[mobj.stream]
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

        image.thumbnail(new_size(image.size, mobj.width))
        image = ImageOps.grayscale(image)

        if mobj.blur > 0:
            image = image.filter(ImageFilter.GaussianBlur(radius=mobj.blur))

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))

            threshold_list[index] = count / total_pixels

    bar.end()
    return threshold_list[:index]
