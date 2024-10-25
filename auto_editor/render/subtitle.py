from __future__ import annotations

import io
import os
import re
from dataclasses import dataclass
from typing import TYPE_CHECKING

import av

from auto_editor.utils.func import to_timecode

if TYPE_CHECKING:
    from fractions import Fraction

    from auto_editor.timeline import v3
    from auto_editor.utils.chunks import Chunks
    from auto_editor.utils.log import Log

    Input = av.container.InputContainer


@dataclass(slots=True)
class SerialSub:
    start: int
    end: int
    before: str
    middle: str
    after: str


class SubtitleParser:
    def __init__(self, tb: Fraction) -> None:
        self.tb = tb
        self.contents: list[SerialSub] = []
        self.header = ""
        self.footer = ""

    @staticmethod
    def to_tick(text: str, codec: str, tb: Fraction) -> int:
        boxes = text.replace(",", ".").split(":")
        assert len(boxes) < 4

        boxes.reverse()
        multiply = (1, 60, 3600)
        seconds = 0.0
        for box, mul in zip(boxes, multiply):
            seconds += float(box) * mul

        return round(seconds * tb)

    def parse(self, text: str, codec: str) -> None:
        self.codec = codec
        self.contents = []

        if codec == "ass" or codec == "ssa":
            time_code = re.compile(r"(.*)(\d+:\d+:[\d.]+)(.*)(\d+:\d+:[\d.]+)(.*)")
        elif codec == "webvtt":
            time_code = re.compile(r"()(\d+:[\d.]+)( --> )(\d+:[\d.]+)(\n.*)")
        elif codec == "mov_text":
            time_code = re.compile(r"()(\d+:\d+:[\d,]+)( --> )(\d+:\d+:[\d,]+)(\n.*)")
        else:
            raise ValueError(f"codec {codec} not supported.")

        i = 0
        for reg in re.finditer(time_code, text):
            i += 1
            if i == 1:
                self.header = text[: reg.span()[0]]

            self.contents.append(
                SerialSub(
                    self.to_tick(reg.group(2), self.codec, self.tb),
                    self.to_tick(reg.group(4), self.codec, self.tb),
                    reg.group(1),
                    reg.group(3),
                    f"{reg.group(5)}\n",
                )
            )

        if i == 0:
            self.header = ""
            self.footer = ""
        else:
            self.footer = text[reg.span()[1] :]

    def edit(self, chunks: Chunks) -> None:
        for cut in reversed(chunks):
            the_speed = cut[2]
            speed_factor = (
                1 if (the_speed == 0 or the_speed >= 99999) else 1 - (1 / the_speed)
            )

            new_content = []
            for content in self.contents:
                if cut[0] <= content.end and cut[1] > content.start:
                    diff = int(
                        (min(cut[1], content.end) - max(cut[0], content.start))
                        * speed_factor
                    )
                    if content.start > cut[0]:
                        content.start -= diff
                        content.end -= diff

                    content.end -= diff

                elif content.start >= cut[0]:
                    diff = int((cut[1] - cut[0]) * speed_factor)

                    content.start -= diff
                    content.end -= diff

                if content.start != content.end:
                    new_content.append(content)

        self.contents = new_content

    def write(self, file_path: str) -> None:
        codec = self.codec
        with open(file_path, "w", encoding="utf-8") as file:
            file.write(self.header)
            for c in self.contents:
                file.write(
                    f"{c.before}{to_timecode(c.start / self.tb, codec)}"
                    + f"{c.middle}{to_timecode(c.end / self.tb, codec)}"
                    + c.after
                    + ("\n" if codec == "webvtt" else "")
                )
            file.write(self.footer)


def make_srt(input_: Input, stream: int) -> str:
    output_bytes = io.StringIO()
    input_stream = input_.streams.subtitles[stream]
    assert input_stream.time_base is not None
    s = 1
    for packet in input_.demux(input_stream):
        if packet.dts is None or packet.pts is None or packet.duration is None:
            continue

        start = packet.pts * input_stream.time_base
        end = start + packet.duration * input_stream.time_base

        for subset in packet.decode():
            start_time = to_timecode(start, "srt")
            end_time = to_timecode(end, "srt")

            sub = subset[0]
            assert len(subset) == 1
            assert isinstance(sub, av.subtitles.subtitle.AssSubtitle)

            output_bytes.write(f"{s}\n{start_time} --> {end_time}\n")
            output_bytes.write(sub.dialogue.decode("utf-8", errors="ignore") + "\n\n")
            s += 1

    output_bytes.seek(0)
    return output_bytes.getvalue()


def _ensure(input_: Input, format: str, stream: int) -> str:
    output_bytes = io.BytesIO()
    output = av.open(output_bytes, "w", format=format)

    in_stream = input_.streams.subtitles[stream]
    out_stream = output.add_stream(template=in_stream)

    for packet in input_.demux(in_stream):
        if packet.dts is None:
            continue
        packet.stream = out_stream
        output.mux(packet)

    output.close()
    output_bytes.seek(0)
    return output_bytes.getvalue().decode("utf-8", errors="ignore")


def make_new_subtitles(tl: v3, log: Log) -> list[str]:
    if tl.v1 is None:
        return []

    input_ = av.open(tl.v1.source.path)
    new_paths = []

    for s, sub in enumerate(tl.v1.source.subtitles):
        if sub.codec == "mov_text":
            continue

        parser = SubtitleParser(tl.tb)
        if sub.codec == "ssa":
            format = "ass"
        elif sub.codec in ("webvtt", "ass"):
            format = sub.codec
        else:
            log.error(f"Unknown subtitle codec: {sub.codec}")

        if sub.codec == "mov_text":
            ret = make_srt(input_, s)
        else:
            ret = _ensure(input_, format, s)
        parser.parse(ret, format)
        parser.edit(tl.v1.chunks)

        new_path = os.path.join(log.temp, f"new{s}s.{sub.ext}")
        parser.write(new_path)
        new_paths.append(new_path)

    input_.close()
    return new_paths
