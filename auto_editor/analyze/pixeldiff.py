import av
import numpy as np
import numpy.typing as npt
from PIL import ImageChops

from auto_editor.ffwrapper import FileInfo
from auto_editor.utils.progressbar import ProgressBar


def pixel_difference(inp: FileInfo, progress: ProgressBar) -> npt.NDArray[np.uint64]:
    path, fps = inp.path, inp.gfps

    container = av.open(path, "r")

    video_stream = container.streams.video[0]
    video_stream.thread_type = "AUTO"

    inaccurate_dur = int(float(video_stream.duration * video_stream.time_base) * fps)

    progress.start(inaccurate_dur, "Analyzing pixel diffs")

    prev_image = None
    image = None
    index = 0

    threshold_list = np.zeros((1024), dtype=np.uint64)

    for frame in container.decode(video_stream):
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
