from __future__ import annotations

from typing import TYPE_CHECKING

import av
import numpy as np
from PIL import ImageChops, ImageFilter

from auto_editor.analyze.helper import get_all_list

if TYPE_CHECKING:
    from fractions import Fraction

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


av.logging.set_level(av.logging.PANIC)


def link_nodes(*nodes):
    for c, n in zip(nodes, nodes[1:]):
        c.link_to(n)


def motion_detection(
    inp: FileInfo,
    mobj,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.float_]:

    if mobj.stream >= len(inp.videos):
        if not strict:
            return get_all_list(inp, tb, temp, log)
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

    graph = av.filter.Graph()
    link_nodes(
        graph.add_buffer(template=stream),
        graph.add("scale", f"{mobj.width}:-1"),
        graph.add("buffersink"),
    )
    graph.configure()

    threshold_list = np.zeros((1024), dtype=np.float_)

    for unframe in container.decode(stream):
        graph.push(unframe)
        frame = graph.pull()

        prev_image = image

        index = int(frame.time * tb)
        bar.tick(index)

        if index > len(threshold_list) - 1:
            threshold_list = np.concatenate(
                (threshold_list, np.zeros((len(threshold_list)), dtype=np.float_)),
                axis=0,
            )

        image = frame.to_image().convert("L")

        if total_pixels is None:
            total_pixels = image.size[0] * image.size[1]

        if mobj.blur > 0:
            image = image.filter(ImageFilter.GaussianBlur(radius=mobj.blur))

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))

            threshold_list[index] = count / total_pixels

    bar.end()
    return threshold_list[:index]
