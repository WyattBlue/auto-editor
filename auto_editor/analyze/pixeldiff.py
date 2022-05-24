import av
import numpy as np
from numpy.typing import NDArray
from PIL import ImageChops

from auto_editor.utils.progressbar import ProgressBar


def pixel_difference(
    path: str, fps: float, progress: ProgressBar
) -> NDArray[np.uint64]:
    container = av.open(path, "r")

    stream = container.streams.video[0]
    stream.thread_type = "AUTO"

    inaccurate_dur = int(stream.duration * stream.time_base * stream.rate)

    progress.start(inaccurate_dur, "Analyzing pixel diffs")

    prev_image = None
    image = None
    index = 0

    threshold_list = np.zeros((1024), dtype=np.uint64)

    for frame in container.decode(stream):
        if image is None:
            prev_image = None
        else:
            prev_image = image

        index = int(frame.time * fps)
        progress.tick(index)

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

    progress.end()
    return threshold_list[:index]
