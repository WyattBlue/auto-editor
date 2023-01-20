from __future__ import annotations

import json
import os
import re
from typing import TYPE_CHECKING

import numpy as np

from auto_editor import version
from auto_editor.objs.edit import (
    Audio,
    Motion,
    Pixeldiff,
    Subtitle,
    audio_builder,
    motion_builder,
    pixeldiff_builder,
    subtitle_builder,
)
from auto_editor.objs.util import ParserError, parse_dataclass
from auto_editor.render.subtitle import SubtitleParser
from auto_editor.utils.func import boolop
from auto_editor.utils.types import pos
from auto_editor.wavfile import read

if TYPE_CHECKING:
    from fractions import Fraction
    from typing import Any

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.interpreter import FileSetup
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


def link_nodes(*nodes: Any) -> None:
    for c, n in zip(nodes, nodes[1:]):
        c.link_to(n)


def to_threshold(arr: np.ndarray, t: int | float) -> NDArray[np.bool_]:
    return np.fromiter((x >= t for x in arr), dtype=np.bool_)


def mut_remove_small(
    arr: NDArray[np.bool_], lim: int, replace: int, with_: int
) -> None:
    start_p = 0
    active = False
    for j, item in enumerate(arr):
        if item == replace:
            if not active:
                start_p = j
                active = True
            # Special case for end.
            if j == len(arr) - 1:
                if j - start_p < lim:
                    arr[start_p : j + 1] = with_
        else:
            if active:
                if j - start_p < lim:
                    arr[start_p:j] = with_
                active = False


def get_media_length(
    ensure: Ensure, src: FileInfo, tb: Fraction, temp: str, log: Log
) -> int:
    if src.audios:
        if (arr := read_cache(src, tb, "audio", {"stream": 0}, temp)) is not None:
            return len(arr)

        sr, samples = read(ensure.audio(f"{src.path.resolve()}", src.label, stream=0))
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

    with av.open(f"{src.path}") as cn:
        if len(cn.streams.video) < 1:
            log.error("Could not get media duration")

        video = cn.streams.video[0]
        dur = int(video.duration * video.time_base * tb)
        log.debug(f"Video duration: {dur}")

    return dur


def get_all(
    ensure: Ensure, src: FileInfo, tb: Fraction, temp: str, log: Log
) -> NDArray[np.bool_]:
    return np.zeros(get_media_length(ensure, src, tb, temp, log), dtype=np.bool_)


def get_none(
    ensure: Ensure, src: FileInfo, tb: Fraction, temp: str, log: Log
) -> NDArray[np.bool_]:
    return np.ones(get_media_length(ensure, src, tb, temp, log), dtype=np.bool_)


def _dict_tag(tag: str, tb: Fraction, obj: Any) -> tuple[str, dict]:
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
    src: FileInfo, tb: Fraction, tag: str, obj: Any, temp: str
) -> None | np.ndarray:

    workfile = os.path.join(os.path.dirname(temp), f"ae-{version}", "cache.json")

    try:
        with open(workfile) as file:
            cache = json.load(file)
    except Exception:
        return None

    if f"{src.path.resolve()}" not in cache:
        return None

    key, obj_dict = _dict_tag(tag, tb, obj)

    if key not in (root := cache[f"{src.path.resolve()}"]):
        return None

    return np.asarray(root[key]["arr"], dtype=root[key]["type"])


def cache(
    tag: str, tb: Fraction, obj: Any, arr: np.ndarray, src: FileInfo, temp: str
) -> np.ndarray:

    workdur = os.path.join(os.path.dirname(temp), f"ae-{version}")
    workfile = os.path.join(workdur, "cache.json")
    if not os.path.exists(workdur):
        os.mkdir(workdur)

    key, obj_dict = _dict_tag(tag, tb, obj)

    try:
        with open(workfile) as file:
            json_object = json.load(file)
    except Exception:
        json_object = {}

    entry = {
        "type": str(arr.dtype),
        "arr": arr.tolist(),
    }

    src_key = f"{src.path}"

    if src_key in json_object:
        json_object[src_key][key] = entry
    else:
        json_object[src_key] = {key: entry}

    with open(os.path.join(workdur, "cache.json"), "w") as file:
        file.write(json.dumps(json_object))

    return arr


def audio_levels(
    ensure: Ensure,
    src: FileInfo,
    s: int,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.float_]:

    if s > len(src.audios) - 1:
        if strict:
            log.error(f"Audio stream '{s}' does not exist.")
        return np.zeros(get_media_length(ensure, src, tb, temp, log), dtype=np.float_)

    if (arr := read_cache(src, tb, "audio", {"stream": s}, temp)) is not None:
        return arr

    sr, samples = read(ensure.audio(f"{src.path.resolve()}", src.label, s))

    def get_max_volume(s: np.ndarray) -> float:
        return max(float(np.max(s)), -float(np.min(s)))

    max_volume = get_max_volume(samples)
    log.debug(f"Max volume: {max_volume}")

    samp_count = samples.shape[0]
    samp_per_ticks = sr / tb

    audio_ticks = int(samp_count / samp_per_ticks)
    log.debug(f"analyze: Audio Length: {audio_ticks}")
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
    return cache("audio", tb, {"stream": s}, threshold_list, src, temp)


def subtitle_levels(
    ensure: Ensure,
    src: FileInfo,
    sobj: Any,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.bool_]:

    if sobj.stream >= len(src.subtitles):
        if not strict:
            return np.zeros(
                get_media_length(ensure, src, tb, temp, log), dtype=np.float_
            )
        log.error(f"Subtitle stream '{sobj.stream}' does not exist.")

    try:
        flags = re.IGNORECASE if sobj.ignore_case else 0
        pattern = re.compile(sobj.pattern, flags)
    except re.error as e:
        log.error(e)

    sub_file = ensure.subtitle(f"{src.path.resolve()}", src.label, stream=sobj.stream)
    parser = SubtitleParser(tb)

    with open(sub_file) as file:
        parser.parse(file.read(), "webvtt")

    # stackoverflow.com/questions/9662346/python-code-to-remove-html-tags-from-a-string
    def cleanhtml(raw_html: str) -> str:
        cleanr = re.compile("<.*?>")
        return re.sub(cleanr, "", raw_html)

    if not parser.contents:
        log.error("subtitle has no valid entries")

    result = np.zeros((parser.contents[-1].end), dtype=np.bool_)

    count = 0
    for content in parser.contents:
        if sobj.max_count is not None and count >= sobj.max_count:
            break

        line = cleanhtml(content.after.strip())
        if line and re.search(pattern, line):
            result[content.start : content.end] = 1
            count += 1

    return result


def motion_levels(
    ensure: Ensure,
    src: FileInfo,
    mobj: Any,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.float_]:
    import av
    from PIL import ImageChops, ImageFilter

    av.logging.set_level(av.logging.PANIC)

    if mobj.stream >= len(src.videos):
        if not strict:
            return np.zeros(
                get_media_length(ensure, src, tb, temp, log), dtype=np.float_
            )
        log.error(f"Video stream '{mobj.stream}' does not exist.")

    if (arr := read_cache(src, tb, "motion", mobj, temp)) is not None:
        return arr

    container = av.open(f"{src.path}", "r")

    stream = container.streams.video[mobj.stream]
    stream.thread_type = "AUTO"

    if stream.duration is None:
        inaccurate_dur = 1
    else:
        inaccurate_dur = int(stream.duration * stream.time_base * stream.average_rate)

    bar.start(inaccurate_dur, "Analyzing motion")

    prev_image = None
    image = None
    total_pixels = src.videos[0].width * src.videos[0].height
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

        if mobj.blur > 0:
            image = image.filter(ImageFilter.GaussianBlur(radius=mobj.blur))

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))

            threshold_list[index] = count / total_pixels

    bar.end()
    result = threshold_list[:index]
    del threshold_list

    return cache("motion", tb, mobj, result, src, temp)


def pixeldiff_levels(
    ensure: Ensure,
    src: FileInfo,
    pobj: Any,
    tb: Fraction,
    bar: Bar,
    strict: bool,
    temp: str,
    log: Log,
) -> NDArray[np.uint64]:
    import av
    from PIL import ImageChops

    av.logging.set_level(av.logging.PANIC)

    if pobj.stream >= len(src.videos):
        if not strict:
            return np.zeros(
                get_media_length(ensure, src, tb, temp, log), dtype=np.uint64
            )
        log.error(f"Video stream '{pobj.stream}' does not exist.")

    if (arr := read_cache(src, tb, "pixeldiff", pobj, temp)) is not None:
        return arr

    container = av.open(f"{src.path}", "r")

    stream = container.streams.video[pobj.stream]
    stream.thread_type = "AUTO"

    if stream.duration is None:
        inaccurate_dur = 1
    else:
        inaccurate_dur = int(stream.duration * stream.time_base * stream.average_rate)

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

    return cache("pixeldiff", tb, pobj, result, src, temp)


def edit_method(val: str, filesetup: FileSetup) -> NDArray[np.bool_]:
    src = filesetup.src
    tb = filesetup.tb
    ensure = filesetup.ensure
    strict = filesetup.strict
    bar = filesetup.bar
    temp = filesetup.temp
    log = filesetup.log

    if ":" in val:
        method, attrs = val.split(":", 1)
    else:
        method, attrs = val, ""

    if method == "none":
        return get_none(ensure, src, tb, temp, log)

    if method == "all":
        return get_all(ensure, src, tb, temp, log)

    def my_var_f(name: str, val: str, coerce: Any) -> Any:
        if src.videos:
            if name in ("x", "width"):
                return pos((val, src.videos[0].width))
            if name in ("y", "height"):
                return pos((val, src.videos[0].height))
        return coerce(val)

    if method == "audio":
        try:
            aobj = parse_dataclass(attrs, (Audio, audio_builder))
        except ParserError as e:
            log.error(e)

        s = aobj.stream
        if s == "all":
            total_list: NDArray[np.bool_] | None = None
            for s in range(len(src.audios)):
                audio_list = to_threshold(
                    audio_levels(ensure, src, s, tb, bar, strict, temp, log),
                    aobj.threshold,
                )
                if total_list is None:
                    total_list = audio_list
                else:
                    total_list = boolop(total_list, audio_list, np.logical_or)
            if total_list is None:
                if strict:
                    log.error("Input has no audio streams.")
                stream_data = get_all(ensure, src, tb, temp, log)
            else:
                stream_data = total_list
        else:
            stream_data = to_threshold(
                audio_levels(ensure, src, s, tb, bar, strict, temp, log),
                aobj.threshold,
            )

        def st(val: int | str) -> int:
            if isinstance(val, str):
                return round(float(val) * tb)
            return val

        mut_remove_small(stream_data, st(aobj.minclip), replace=1, with_=0)
        mut_remove_small(stream_data, st(aobj.mincut), replace=0, with_=1)

        return stream_data

    if method == "motion":
        try:
            mobj = parse_dataclass(attrs, (Motion, motion_builder), my_var_f)
        except ParserError as e:
            log.error(e)
        return to_threshold(
            motion_levels(ensure, src, mobj, tb, bar, strict, temp, log),
            mobj.threshold,
        )

    if method == "subtitle":
        try:
            sobj = parse_dataclass(attrs, (Subtitle, subtitle_builder))
        except ParserError as e:
            log.error(e)

        return subtitle_levels(ensure, src, sobj, tb, bar, strict, temp, log)

    if method == "pixeldiff":
        try:
            pobj = parse_dataclass(attrs, (Pixeldiff, pixeldiff_builder), my_var_f)
        except ParserError as e:
            log.error(e)
        return to_threshold(
            pixeldiff_levels(ensure, src, pobj, tb, bar, strict, temp, log),
            pobj.threshold,
        )

    raise ValueError("Unreachable")
