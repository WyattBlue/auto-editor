from __future__ import annotations

import os.path
from dataclasses import dataclass, field

import av
from av.audio.resampler import AudioResampler

from auto_editor.ffwrapper import FileInfo
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.utils.types import _split_num_str


def parse_bitrate(input_: str, log: Log) -> int:
    try:
        val, unit = _split_num_str(input_)
    except Exception as e:
        log.error(e)

    if unit.lower() == "k":
        return int(val * 1000)
    if unit == "M":
        return int(val * 1_000_000)
    if unit == "G":
        return int(val * 1_000_000_000)
    if unit == "":
        return int(val)

    log.error(f"Unknown bitrate: {input_}")


@dataclass(slots=True)
class Ensure:
    _bar: Bar
    _sr: int
    log: Log
    _audios: list[tuple[FileInfo, int]] = field(default_factory=list)

    def audio(self, src: FileInfo, stream: int) -> str:
        try:
            label = self._audios.index((src, stream))
            first_time = False
        except ValueError:
            self._audios.append((src, stream))
            label = len(self._audios) - 1
            first_time = True

        out_path = os.path.join(self.log.temp, f"{label:x}.wav")

        if first_time:
            sample_rate = self._sr
            bar = self._bar
            self.log.debug(f"Making external audio: {out_path}")

            in_container = av.open(src.path, "r")
            out_container = av.open(
                out_path, "w", format="wav", options={"rf64": "always"}
            )
            astream = in_container.streams.audio[stream]

            if astream.duration is None or astream.time_base is None:
                dur = 1.0
            else:
                dur = float(astream.duration * astream.time_base)

            bar.start(dur, "Extracting audio")

            output_astream = out_container.add_stream(
                "pcm_s16le", layout="stereo", rate=sample_rate
            )
            resampler = AudioResampler(format="s16", layout="stereo", rate=sample_rate)
            for i, frame in enumerate(in_container.decode(astream)):
                if i % 1500 == 0 and frame.time is not None:
                    bar.tick(frame.time)

                for new_frame in resampler.resample(frame):
                    out_container.mux(output_astream.encode(new_frame))

            out_container.mux(output_astream.encode(None))

            out_container.close()
            in_container.close()
            bar.end()

        return out_path
