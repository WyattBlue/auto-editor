from __future__ import annotations

import os
import re
from dataclasses import dataclass
from fractions import Fraction
from hashlib import sha1
from math import ceil
from tempfile import gettempdir
from typing import TYPE_CHECKING

import av
import numpy as np
from av.audio.fifo import AudioFifo
from av.subtitles.subtitle import AssSubtitle

from auto_editor import __version__

if TYPE_CHECKING:
    from collections.abc import Iterator, Sequence
    from fractions import Fraction
    from pathlib import Path

    from numpy.typing import NDArray

    from auto_editor.ffwrapper import FileInfo
    from auto_editor.utils.bar import Bar
    from auto_editor.utils.log import Log


__all__ = ("LevelError", "Levels", "iter_audio", "iter_motion")


class LevelError(Exception):
    pass


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

            if j == len(arr) - 1 and j - start_p < lim:
                arr[start_p:] = with_
        elif active:
            if j - start_p < lim:
                arr[start_p:j] = with_
            active = False


def mut_remove_large(
    arr: NDArray[np.bool_], lim: int, replace: int, with_: int
) -> None:
    start_p = 0
    active = False
    for j, item in enumerate(arr):
        if item == replace:
            if not active:
                start_p = j
                active = True

            if j == len(arr) - 1 and j - start_p >= lim:
                arr[start_p:] = with_
        elif active:
            if j - start_p > lim:
                arr[start_p:j] = with_
            active = False


def iter_audio(audio_stream: av.AudioStream, tb: Fraction) -> Iterator[np.float32]:
    fifo = AudioFifo()
    sr = audio_stream.rate

    exact_size = (1 / tb) * sr
    accumulated_error = Fraction(0)

    # Resample so that audio data is between [-1, 1]
    resampler = av.AudioResampler(av.AudioFormat("flt"), audio_stream.layout, sr)

    container = audio_stream.container
    assert isinstance(container, av.container.InputContainer)

    for frame in container.decode(audio_stream):
        frame.pts = None  # Skip time checks

        for reframe in resampler.resample(frame):
            fifo.write(reframe)

        while fifo.samples >= ceil(exact_size):
            size_with_error = exact_size + accumulated_error
            current_size = round(size_with_error)
            accumulated_error = size_with_error - current_size

            audio_chunk = fifo.read(current_size)
            assert audio_chunk is not None
            arr = audio_chunk.to_ndarray().flatten()
            yield np.max(np.abs(arr))


def iter_motion(
    video: av.VideoStream, tb: Fraction, blur: int, width: int
) -> Iterator[np.float32]:
    video.thread_type = "AUTO"

    prev_frame = None
    current_frame = None
    total_pixels = None
    index = 0
    prev_index = -1

    graph = av.filter.Graph()
    graph.link_nodes(
        graph.add_buffer(template=video),
        graph.add("scale", f"{width}:-1"),
        graph.add("format", "gray"),
        graph.add("gblur", f"sigma={blur}"),
        graph.add("buffersink"),
    ).configure()

    container = video.container
    assert isinstance(container, av.container.InputContainer)

    for unframe in container.decode(video):
        if unframe.pts is None:
            continue

        graph.push(unframe)
        frame = graph.vpull()
        assert frame.time is not None
        index = round(frame.time * tb)

        if total_pixels is None:
            total_pixels = frame.width * frame.height

        current_frame = frame.to_ndarray()
        if prev_frame is None:
            value = np.float32(0.0)
        else:
            # Use `int16` to avoid underflow with `uint8` datatype
            diff = np.abs(prev_frame.astype(np.int16) - current_frame.astype(np.int16))
            value = np.float32(np.count_nonzero(diff) / total_pixels)

        for _ in range(index - prev_index):
            yield value

        prev_frame = current_frame
        prev_index = index


def obj_tag(path: Path, kind: str, tb: Fraction, obj: Sequence[object]) -> str:
    mod_time = int(path.stat().st_mtime)
    key = f"{path.name}:{mod_time:x}:{tb}:" + ",".join(f"{v}" for v in obj)
    part1 = sha1(key.encode()).hexdigest()[:16]

    return f"{part1}{kind}"


@dataclass(slots=True)
class Levels:
    src: FileInfo
    tb: Fraction
    bar: Bar
    no_cache: bool
    log: Log
    strict: bool

    @property
    def media_length(self) -> int:
        if self.src.audios:
            if (arr := self.read_cache("audio", (0,))) is not None:
                return len(arr)

            with av.open(self.src.path, "r") as container:
                audio_stream = container.streams.audio[0]
                self.log.experimental(audio_stream.codec)
                result = sum(1 for _ in iter_audio(audio_stream, self.tb))

            self.log.debug(f"Audio Length: {result}")
            return result

        # If there's no audio, get length in video metadata.
        with av.open(self.src.path) as container:
            if len(container.streams.video) == 0:
                self.log.error("Could not get media duration")

            video = container.streams.video[0]

            if video.duration is None or video.time_base is None:
                dur = 0
            else:
                dur = int(video.duration * video.time_base * self.tb)
            self.log.debug(f"Video duration: {dur}")

        return dur

    def none(self) -> NDArray[np.bool_]:
        return np.ones(self.media_length, dtype=np.bool_)

    def all(self) -> NDArray[np.bool_]:
        return np.zeros(self.media_length, dtype=np.bool_)

    def read_cache(self, kind: str, obj: Sequence[object]) -> None | np.ndarray:
        if self.no_cache:
            return None

        key = obj_tag(self.src.path, kind, self.tb, obj)
        cache_file = os.path.join(gettempdir(), f"ae-{__version__}", f"{key}.npz")

        try:
            with np.load(cache_file, allow_pickle=False) as npzfile:
                return npzfile["data"]
        except Exception as e:
            self.log.debug(e)
            return None

    def cache(self, arr: np.ndarray, kind: str, obj: Sequence[object]) -> np.ndarray:
        if self.no_cache:
            return arr

        workdir = os.path.join(gettempdir(), f"ae-{__version__}")
        if not os.path.exists(workdir):
            os.mkdir(workdir)

        key = obj_tag(self.src.path, kind, self.tb, obj)
        cache_file = os.path.join(workdir, f"{key}.npz")

        try:
            np.savez(cache_file, data=arr)
        except Exception as e:
            self.log.warning(f"Cache write failed: {e}")

        cache_entries = []
        with os.scandir(workdir) as entries:
            for entry in entries:
                if entry.name.endswith(".npz"):
                    cache_entries.append((entry.path, entry.stat().st_mtime))

        if len(cache_entries) > 10:
            # Sort by modification time, oldest first
            cache_entries.sort(key=lambda x: x[1])
            # Remove oldest files until we're back to 10
            for filepath, _ in cache_entries[:-10]:
                try:
                    os.remove(filepath)
                except OSError:
                    pass

        return arr

    def audio(self, stream: int) -> NDArray[np.float32]:
        if stream >= len(self.src.audios):
            raise LevelError(f"audio: audio stream '{stream}' does not exist.")

        if (arr := self.read_cache("audio", (stream,))) is not None:
            return arr

        container = av.open(self.src.path, "r")
        audio = container.streams.audio[stream]

        if audio.codec.experimental:
            self.log.error(f"`{audio.codec.name}` is an experimental codec")

        if audio.duration is not None and audio.time_base is not None:
            inaccurate_dur = int(audio.duration * audio.time_base * self.tb)
        elif container.duration is not None:
            inaccurate_dur = int(container.duration / av.time_base * self.tb)
        else:
            inaccurate_dur = 1024

        bar = self.bar
        bar.start(inaccurate_dur, "Analyzing audio volume")

        result: NDArray[np.float32] = np.zeros(inaccurate_dur, dtype=np.float32)
        index = 0

        for value in iter_audio(audio, self.tb):
            if index > len(result) - 1:
                result = np.concatenate(
                    (result, np.zeros(len(result), dtype=np.float32))
                )

            result[index] = value
            bar.tick(index)
            index += 1

        bar.end()
        assert len(result) > 0
        return self.cache(result[:index], "audio", (stream,))

    def motion(self, stream: int, blur: int, width: int) -> NDArray[np.float32]:
        if stream >= len(self.src.videos):
            raise LevelError(f"motion: video stream '{stream}' does not exist.")

        mobj = (stream, width, blur)
        if (arr := self.read_cache("motion", mobj)) is not None:
            return arr

        container = av.open(self.src.path, "r")
        video = container.streams.video[stream]

        if video.codec.experimental:
            self.log.experimental(video.codec)

        inaccurate_dur = (
            1024
            if video.duration is None or video.time_base is None
            else int(video.duration * video.time_base * self.tb)
        )

        bar = self.bar
        bar.start(inaccurate_dur, "Analyzing motion")

        result: NDArray[np.float32] = np.zeros(inaccurate_dur, dtype=np.float32)
        index = 0

        for value in iter_motion(video, self.tb, blur, width):
            if index > len(result) - 1:
                result = np.concatenate(
                    (result, np.zeros(len(result), dtype=np.float32))
                )
            result[index] = value
            bar.tick(index)
            index += 1

        bar.end()
        return self.cache(result[:index], "motion", mobj)

    def subtitle(
        self,
        pattern: str,
        stream: int,
        ignore_case: bool,
        max_count: int | None,
    ) -> NDArray[np.bool_]:
        if stream >= len(self.src.subtitles):
            raise LevelError(f"subtitle: subtitle stream '{stream}' does not exist.")

        try:
            flags = re.IGNORECASE if ignore_case else 0
            re_pattern = re.compile(pattern, flags)
        except re.error as e:
            self.log.error(e)

        try:
            container = av.open(self.src.path, "r")
            subtitle_stream = container.streams.subtitles[stream]
            assert isinstance(subtitle_stream.time_base, Fraction)
        except Exception as e:
            self.log.error(e)

        # Get the length of the subtitle stream.
        sub_length = 0
        for packet in container.demux(subtitle_stream):
            if packet.pts is None or packet.duration is None:
                continue
            for subset in packet.decode():
                # See definition of `AVSubtitle`
                # in: https://ffmpeg.org/doxygen/trunk/avcodec_8h_source.html
                start = float(packet.pts * subtitle_stream.time_base)
                dur = float(packet.duration * subtitle_stream.time_base)

                end = round((start + dur) * self.tb)
                sub_length = max(sub_length, end)

        result = np.zeros((sub_length), dtype=np.bool_)
        del sub_length

        count = 0
        early_exit = False
        container.seek(0)
        for packet in container.demux(subtitle_stream):
            if packet.pts is None or packet.duration is None:
                continue
            if early_exit:
                break
            for subset in packet.decode():
                if max_count is not None and count >= max_count:
                    early_exit = True
                    break

                start = float(packet.pts * subtitle_stream.time_base)
                dur = float(packet.duration * subtitle_stream.time_base)

                san_start = round(start * self.tb)
                san_end = round((start + dur) * self.tb)

                for sub in subset:
                    if not isinstance(sub, AssSubtitle):
                        continue

                    line = sub.dialogue.decode(errors="ignore")
                    if line and re.search(re_pattern, line):
                        result[san_start:san_end] = 1
                        count += 1

        container.close()

        return result
