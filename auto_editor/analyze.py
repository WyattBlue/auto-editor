from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import TYPE_CHECKING

import numpy as np

from auto_editor import version
from auto_editor.objs.edit import (
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
    from auto_editor.output import Ensure
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


@dataclass
class FileSetup:
    src: FileInfo
    ensure: Ensure
    strict: bool
    tb: Fraction
    bar: Bar
    temp: str
    log: Log


class LevelError(Exception):
    pass


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
        elif active:
            if j - start_p < lim:
                arr[start_p:j] = with_
            active = False


def obj_tag(tag: str, tb: Fraction, obj: dict[str, Any]) -> str:
    key = f"{tag}:{tb}:"
    for k, v in obj.items():
        key += f"{k}={v},"

    key = key[:-1]  # remove unnecessary char
    return key


class Levels:
    def __init__(
        self, ensure: Ensure, src: FileInfo, tb: Fraction, bar: Bar, temp: str, log: Log
    ):
        self.ensure = ensure
        self.src = src
        self.tb = tb
        self.bar = bar
        self.temp = temp
        self.log = log

    @property
    def media_length(self) -> int:
        if self.src.audios:
            if (arr := self.read_cache("audio", {"stream": 0})) is not None:
                return len(arr)

            sr, samples = read(
                self.ensure.audio(
                    f"{self.src.path.resolve()}", self.src.label, stream=0
                )
            )
            samp_count = len(samples)
            del samples

            samp_per_ticks = sr / self.tb
            ticks = int(samp_count / samp_per_ticks)
            self.log.debug(f"Audio Length: {ticks}")
            self.log.debug(
                f"... without rounding: {float(samp_count / samp_per_ticks)}"
            )
            return ticks

        # If there's no audio, get length in video metadata.
        import av

        av.logging.set_level(av.logging.PANIC)

        with av.open(f"{self.src.path}") as cn:
            if len(cn.streams.video) < 1:
                self.log.error("Could not get media duration")

            video = cn.streams.video[0]
            dur = int(video.duration * video.time_base * self.tb)
            self.log.debug(f"Video duration: {dur}")

        return dur

    def none(self) -> NDArray[np.bool_]:
        return np.ones(self.media_length, dtype=np.bool_)

    def all(self) -> NDArray[np.bool_]:
        return np.zeros(self.media_length, dtype=np.bool_)

    def read_cache(self, tag: str, obj: dict[str, Any]) -> None | np.ndarray:
        workfile = os.path.join(
            os.path.dirname(self.temp), f"ae-{version}", "cache.json"
        )

        try:
            with open(workfile) as file:
                cache = json.load(file)
        except Exception:
            return None

        if f"{self.src.path.resolve()}" not in cache:
            return None

        key = obj_tag(tag, self.tb, obj)

        if key not in (root := cache[f"{self.src.path.resolve()}"]):
            return None

        return np.asarray(root[key]["arr"], dtype=root[key]["type"])

    def cache(self, tag: str, obj: dict[str, Any], arr: np.ndarray) -> np.ndarray:
        workdur = os.path.join(os.path.dirname(self.temp), f"ae-{version}")
        workfile = os.path.join(workdur, "cache.json")
        if not os.path.exists(workdur):
            os.mkdir(workdur)

        key = obj_tag(tag, self.tb, obj)

        try:
            with open(workfile) as file:
                json_object = json.load(file)
        except Exception:
            json_object = {}

        entry = {
            "type": str(arr.dtype),
            "arr": arr.tolist(),
        }

        src_key = f"{self.src.path}"

        if src_key in json_object:
            json_object[src_key][key] = entry
        else:
            json_object[src_key] = {key: entry}

        with open(os.path.join(workdur, "cache.json"), "w") as file:
            file.write(json.dumps(json_object))

        return arr

    def audio(self, s: int) -> NDArray[np.float_]:
        if s > len(self.src.audios) - 1:
            raise LevelError(f"audio: audio stream '{s}' does not exist.")

        if (arr := self.read_cache("audio", {"stream": s})) is not None:
            return arr

        sr, samples = read(
            self.ensure.audio(f"{self.src.path.resolve()}", self.src.label, s)
        )

        if len(samples) == 0:
            raise LevelError(f"audio: audio stream '{s}' has length of 0.")

        def get_max_volume(s: np.ndarray) -> float:
            return max(float(np.max(s)), -float(np.min(s)))

        max_volume = get_max_volume(samples)
        self.log.debug(f"Max volume: {max_volume}")

        samp_count = samples.shape[0]
        samp_per_ticks = sr / self.tb

        audio_ticks = int(samp_count / samp_per_ticks)
        self.log.debug(f"analyze: Audio Length: {audio_ticks}")
        self.log.debug(f"... no rounding: {float(samp_count / samp_per_ticks)}")

        self.bar.start(audio_ticks, "Analyzing audio volume")

        threshold_list = np.zeros((audio_ticks), dtype=np.float_)

        if max_volume == 0:  # Prevent dividing by zero
            return threshold_list

        # Determine when audio is silent or loud.
        for i in range(audio_ticks):
            if i % 500 == 0:
                self.bar.tick(i)

            start = int(i * samp_per_ticks)
            end = min(int((i + 1) * samp_per_ticks), samp_count)

            threshold_list[i] = get_max_volume(samples[start:end]) / max_volume

        self.bar.end()
        return self.cache("audio", {"stream": s}, threshold_list)

    def subtitle(
        self,
        patterns: str,
        stream: int,
        ignore_case: bool,
        max_count: int | None,
    ) -> NDArray[np.bool_]:
        if stream >= len(self.src.subtitles):
            raise LevelError(f"subtitle: subtitle stream '{stream}' does not exist.")

        try:
            flags = re.IGNORECASE if ignore_case else 0
            pattern = re.compile(patterns, flags)
            del patterns  # make sure we don't accidentally use it
        except re.error as e:
            self.log.error(e)

        sub_file = self.ensure.subtitle(
            f"{self.src.path.resolve()}", self.src.label, stream=stream
        )
        parser = SubtitleParser(self.tb)

        with open(sub_file) as file:
            parser.parse(file.read(), "webvtt")

        # stackoverflow.com/questions/9662346/python-code-to-remove-html-tags-from-a-string
        def cleanhtml(raw_html: str) -> str:
            cleanr = re.compile("<.*?>")
            return re.sub(cleanr, "", raw_html)

        if not parser.contents:
            self.log.error("subtitle has no valid entries")

        result = np.zeros((parser.contents[-1].end), dtype=np.bool_)

        count = 0
        for content in parser.contents:
            if max_count is not None and count >= max_count:
                break

            line = cleanhtml(content.after.strip())
            if line and re.search(pattern, line):
                result[content.start : content.end] = 1
                count += 1

        return result

    def motion(self, s: int, blur: int, width: int) -> NDArray[np.float_]:
        import av
        from PIL import ImageChops, ImageFilter

        av.logging.set_level(av.logging.PANIC)

        mobj = {"stream": s, "width": width, "blur": blur}

        if s >= len(self.src.videos):
            raise LevelError(f"motion: video stream '{s}' does not exist.")

        if (arr := self.read_cache("motion", mobj)) is not None:
            return arr

        container = av.open(f"{self.src.path}", "r")

        stream = container.streams.video[s]
        stream.thread_type = "AUTO"

        if stream.duration is None:
            inaccurate_dur = 1
        else:
            inaccurate_dur = int(
                stream.duration * stream.time_base * stream.average_rate
            )

        self.bar.start(inaccurate_dur, "Analyzing motion")

        prev_image = None
        image = None
        total_pixels = self.src.videos[0].width * self.src.videos[0].height
        index = 0

        graph = av.filter.Graph()
        link_nodes(
            graph.add_buffer(template=stream),
            graph.add("scale", f"{width}:-1"),
            graph.add("buffersink"),
        )
        graph.configure()

        threshold_list = np.zeros((1024), dtype=np.float_)

        for unframe in container.decode(stream):
            graph.push(unframe)
            frame = graph.pull()

            prev_image = image

            index = int(frame.time * self.tb)
            self.bar.tick(index)

            if index > len(threshold_list) - 1:
                threshold_list = np.concatenate(
                    (threshold_list, np.zeros((len(threshold_list)), dtype=np.float_)),
                    axis=0,
                )

            image = frame.to_image().convert("L")

            if blur > 0:
                image = image.filter(ImageFilter.GaussianBlur(radius=blur))

            if prev_image is not None:
                count = np.count_nonzero(ImageChops.difference(prev_image, image))

                threshold_list[index] = count / total_pixels

        self.bar.end()
        result = threshold_list[:index]
        del threshold_list

        return self.cache("motion", mobj, result)

    def pixeldiff(self, s: int) -> NDArray[np.uint64]:
        import av
        from PIL import ImageChops

        av.logging.set_level(av.logging.PANIC)

        pobj = {"stream": s}

        if s >= len(self.src.videos):
            raise LevelError(f"pixeldiff: video stream '{s}' does not exist.")

        if (arr := self.read_cache("pixeldiff", pobj)) is not None:
            return arr

        container = av.open(f"{self.src.path}", "r")

        stream = container.streams.video[s]
        stream.thread_type = "AUTO"

        if stream.duration is None:
            inaccurate_dur = 1
        else:
            inaccurate_dur = int(
                stream.duration * stream.time_base * stream.average_rate
            )

        self.bar.start(inaccurate_dur, "Analyzing pixel diffs")

        prev_image = None
        image = None
        index = 0

        threshold_list = np.zeros((1024), dtype=np.uint64)

        for frame in container.decode(stream):
            prev_image = image

            index = int(frame.time * self.tb)
            self.bar.tick(index)

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

        self.bar.end()
        result = threshold_list[:index]
        del threshold_list

        return self.cache("pixeldiff", pobj, result)


def edit_method(val: str, filesetup: FileSetup) -> NDArray[np.bool_]:
    assert isinstance(filesetup, FileSetup)
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

    def my_var_f(name: str, val: str, coerce: Any) -> Any:
        if src.videos:
            if name in ("x", "width"):
                return pos((val, src.videos[0].width))
            if name in ("y", "height"):
                return pos((val, src.videos[0].height))
        return coerce(val)

    builder_map = {
        "audio": audio_builder,
        "motion": motion_builder,
        "pixeldiff": pixeldiff_builder,
        "subtitle": subtitle_builder,
    }

    levels = Levels(ensure, src, tb, bar, temp, log)

    if method == "none":
        return levels.none()
    if method == "all":
        return levels.all()

    try:
        obj = parse_dataclass(attrs, builder_map[method])
    except ParserError as e:
        log.error(e)

    try:
        if method == "audio":
            s = obj["stream"]
            if s == "all":
                total_list: NDArray[np.bool_] | None = None
                for s in range(len(src.audios)):
                    audio_list = to_threshold(levels.audio(s), obj["threshold"])
                    if total_list is None:
                        total_list = audio_list
                    else:
                        total_list = boolop(total_list, audio_list, np.logical_or)

                if total_list is None:
                    if strict:
                        log.error("Input has no audio streams.")
                    stream_data = levels.all()
                else:
                    stream_data = total_list
            else:
                stream_data = to_threshold(levels.audio(s), obj["threshold"])

            def st(val: int | str) -> int:
                if isinstance(val, str):
                    return round(float(val) * tb)
                return val

            mut_remove_small(stream_data, st(obj["minclip"]), replace=1, with_=0)
            mut_remove_small(stream_data, st(obj["mincut"]), replace=0, with_=1)

            return stream_data

        if method == "motion":
            return to_threshold(
                levels.motion(obj["stream"], obj["blur"], obj["width"]),
                obj["threshold"],
            )
        if method == "pixeldiff":
            return to_threshold(levels.pixeldiff(obj["stream"]), obj["threshold"])

        if method == "subtitle":
            return levels.subtitle(
                obj["pattern"],
                obj["stream"],
                obj["ignore_case"],
                obj["max_count"],
            )
    except LevelError as e:
        if strict:
            log.error(e)

        return levels.all()
    raise ValueError("Unreachable")
