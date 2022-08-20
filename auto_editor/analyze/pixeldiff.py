from __future__ import annotations

from typing import TYPE_CHECKING

import av
import numpy as np
from PIL import ImageChops

from auto_editor.analyze.helper import get_all_list

if TYPE_CHECKING:
    from fractions import Fraction

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


av.logging.set_level(av.logging.PANIC)


def pixel_difference(
    inp: FileInfo, i: int, pobj, tb: Fraction, bar: Bar, strict: bool, temp: str, log: Log
) -> NDArray[np.uint64]:

    if pobj.stream >= len(inp.videos):
        if not strict:
            return get_all_list(inp.path, i, tb, temp, log)
        log.error(f"Video stream '{pobj.stream}' does not exist.")

    container = av.open(inp.path, "r")

    stream = container.streams.video[pobj.stream]
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
