from __future__ import annotations

import json
import os
from math import ceil
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.wavfile import read

if TYPE_CHECKING:
    from fractions import Fraction

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


def link_nodes(*nodes):
    for c, n in zip(nodes, nodes[1:]):
        c.link_to(n)


def to_threshold(arr: np.ndarray, t: int | float) -> NDArray[np.bool_]:
    return np.fromiter((x >= t for x in arr), dtype=np.bool_)


def get_media_length(
    ensure: Ensure, inp: FileInfo, tb: Fraction, temp: str, log: Log
) -> int:
    if inp.audios:
        if (arr := read_cache(inp, tb, "audio", {"stream": 0}, temp)) is not None:
            return len(arr)

        sr, samples = read(ensure.audio(inp.path, inp.index, stream=0))
        samp_count = len(samples)
        del samples

        samp_per_ticks = sr / tb
        ticks = int(samp_count / samp_per_ticks)
        log.debug(f"Audio Length: {ticks}")
        log.debug(f"... without rounding: {float(samp_count / samp_per_ticks)}")
        return ticks

    # If there's no audio, get length in video metadata.
    import av

    av.logging.set_level(av.logging.PANIC)

    with av.open(inp.path, "r") as cn:
        if len(cn.streams.video) < 1:
            log.error("Could not get media duration")

        video = cn.streams.video[0]
        dur = int(video.duration * video.time_base * tb)
        log.debug(f"Video duration: {dur}")

    return dur


def get_all(
    ensure: Ensure, inp: FileInfo, tb: Fraction, temp: str, log: Log
) -> NDArray[np.bool_]:
    return np.zeros(get_media_length(ensure, inp, tb, temp, log), dtype=np.bool_)


def get_none(
    ensure: Ensure, inp: FileInfo, tb: Fraction, temp: str, log: Log
) -> NDArray[np.bool_]:
    return np.ones(get_media_length(ensure, inp, tb, temp, log), dtype=np.bool_)


def _dict_tag(tag: str, tb: Fraction, obj) -> tuple[str, dict]:
    if isinstance(obj, dict):
        obj_dict = obj.copy()
    else:
        obj_dict = obj.__dict__.copy()
    if "threshold" in obj_dict:
        del obj_dict["threshold"]

    key = f"{tag}:{tb}:"
    for k, v in obj_dict.items():
        key += f"{k}={v},"
    key = key[:-1]

    return key, obj_dict


def read_cache(
    inp: FileInfo, tb: Fraction, tag: str, obj, temp: str
) -> None | np.ndarray:
    from auto_editor import version

    workfile = os.path.join(os.path.dirname(temp), f"ae-{version}", "cache.json")

    if not os.path.isfile(workfile):
        return None

    with open(workfile) as file:
        cache = json.load(file)

    if inp.path not in cache:
        return None

    key, obj_dict = _dict_tag(tag, tb, obj)

    if key not in (root := cache[inp.path]):
        return None

    return np.asarray(root[key]["arr"], dtype=root[key]["type"])


def cache(
    tag: str, tb: Fraction, obj, arr: np.ndarray, inp: FileInfo, temp: str
) -> np.ndarray:
    from auto_editor import version

    workdur = os.path.join(os.path.dirname(temp), f"ae-{version}")
    workfile = os.path.join(workdur, "cache.json")
    if not os.path.exists(workdur):
        os.mkdir(workdur)

    key, obj_dict = _dict_tag(tag, tb, obj)

    if os.path.isfile(workfile):
        with open(workfile) as file:
            json_object = json.load(file)
    else:
        json_object = {}

    entry = {
        "type": str(arr.dtype),
        "arr": arr.tolist(),
    }

    if inp.path in json_object:
        json_object[inp.path][key] = entry
    else:
        json_object[inp.path] = {key: entry}

    with open(os.path.join(workdur, "cache.json"), "w") as file:
        file.write(json.dumps(json_object))

    return arr


def audio_levels(
    ensure: Ensure,
    inp: FileInfo,
    s: int,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.float_]:

    if s > len(inp.audios) - 1:
        if strict:
            log.error(f"Audio stream '{s}' does not exist.")
        return get_all(ensure, inp, tb, temp, log)

    if (arr := read_cache(inp, tb, "audio", {"stream": s}, temp)) is not None:
        return arr

    sr, samples = read(ensure.audio(inp.path, inp.index, s))

    def get_max_volume(s: np.ndarray) -> float:
        return max(float(np.max(s)), -float(np.min(s)))

    max_volume = get_max_volume(samples)
    log.debug(f"Max volume: {max_volume}")

    samp_count = samples.shape[0]
    samp_per_ticks = sr / tb

    audio_ticks = ceil(samp_count / samp_per_ticks)
    log.debug(f"Audio Length: {audio_ticks}")
    log.debug(f"... no rounding: {float(samp_count / samp_per_ticks)}")

    bar.start(audio_ticks, "Analyzing audio volume")

    threshold_list = np.zeros((audio_ticks), dtype=np.float_)

    if max_volume == 0:  # Prevent dividing by zero
        return threshold_list

    # Determine when audio is silent or loud.
    for i in range(audio_ticks):
        if i % 500 == 0:
            bar.tick(i)

        start = int(i * samp_per_ticks)
        end = min(int((i + 1) * samp_per_ticks), samp_count)

        threshold_list[i] = get_max_volume(samples[start:end]) / max_volume

    bar.end()
    return cache("audio", tb, {"stream": s}, threshold_list, inp, temp)


def motion_levels(
    ensure: Ensure,
    inp: FileInfo,
    mobj,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.float_]:
    import av
    from PIL import ImageChops, ImageFilter

    av.logging.set_level(av.logging.PANIC)

    if mobj.stream >= len(inp.videos):
        if not strict:
            return get_all(ensure, inp, tb, temp, log)
        log.error(f"Video stream '{mobj.stream}' does not exist.")

    if (arr := read_cache(inp, tb, "motion", mobj, temp)) is not None:
        return arr

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
    result = threshold_list[:index]
    del threshold_list

    return cache("motion", tb, mobj, result, inp, temp)


def pixeldiff_levels(
    ensure: Ensure,
    inp: FileInfo,
    pobj,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.uint64]:
    import av
    from PIL import ImageChops

    av.logging.set_level(av.logging.PANIC)

    if pobj.stream >= len(inp.videos):
        if not strict:
            return get_all(ensure, inp, tb, temp, log)
        log.error(f"Video stream '{pobj.stream}' does not exist.")

    if (arr := read_cache(inp, tb, "pixeldiff", pobj, temp)) is not None:
        return arr

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
    result = threshold_list[:index]
    del threshold_list

    return cache("pixeldiff", tb, pobj, result, inp, temp)


def random_levels(
    ensure: Ensure, inp: FileInfo, robj, timebase: Fraction, temp: str, log: Log
) -> NDArray[np.float_]:
    import random

    if robj.seed == -1:
        robj.seed = random.randint(0, 2147483647)

    random.seed(robj.seed)
    log.debug(f"Seed: {robj.seed}")

    arr = [
        random.random()
        for _ in range(get_media_length(ensure, inp, timebase, temp, log))
    ]
    return np.array(arr, dtype=np.float_)
