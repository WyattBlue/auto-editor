from __future__ import annotations

import os
import re
from dataclasses import dataclass
from typing import TYPE_CHECKING

from auto_editor.utils.func import to_timecode

if TYPE_CHECKING:
    from fractions import Fraction

    from auto_editor.output import Ensure
    from auto_editor.timeline import v3
    from auto_editor.utils.chunks import Chunks


@dataclass(slots=True)
class SerialSub:
    start: int
    end: int
    before: str
    middle: str
    after: str


class SubtitleParser:
    def __init__(self, tb: Fraction) -> None:
        self.supported_codecs = ("ass", "webvtt", "mov_text")
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

        if codec == "ass":
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
            speed_factor = 1 if the_speed == 99999 else 1 - (1 / the_speed)

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
        with open(file_path, "w", encoding="utf-8") as file:
            file.write(self.header)
            for c in self.contents:
                file.write(
                    f"{c.before}{to_timecode(c.start / self.tb, self.codec)}"
                    f"{c.middle}{to_timecode(c.end / self.tb, self.codec)}"
                    f"{c.after}"
                )
            file.write(self.footer)


def make_new_subtitles(tl: v3, ensure: Ensure, temp: str) -> list[str]:
    if tl.v1 is None:
        return []

    new_paths = []

    for s, sub in enumerate(tl.v1.source.subtitles):
        new_path = os.path.join(temp, f"new{s}s.{sub.ext}")
        parser = SubtitleParser(tl.tb)

        ext = sub.ext if sub.codec in parser.supported_codecs else "vtt"
        file_path = ensure.subtitle(tl.v1.source, s, ext)

        with open(file_path, encoding="utf-8") as file:
            parser.parse(file.read(), sub.codec)

        parser.edit(tl.v1.chunks)
        parser.write(new_path)
        new_paths.append(new_path)

    return new_paths
