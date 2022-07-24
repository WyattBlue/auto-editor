from __future__ import annotations

import os
import re
from dataclasses import dataclass
from fractions import Fraction

from auto_editor.ffwrapper import FFmpeg
from auto_editor.timeline import Timeline
from auto_editor.utils.chunks import Chunks
from auto_editor.utils.func import to_timecode
from auto_editor.utils.log import Log


@dataclass
class SerialSub:
    start: int
    end: int
    before: str
    middle: str
    after: str


class SubtitleParser:
    def __init__(self) -> None:
        self.supported_codecs = ("ass", "webvtt", "mov_text")

    def parse(self, text, timebase: Fraction, codec: str) -> None:

        if codec not in self.supported_codecs:
            raise ValueError(f"codec {codec} not supported.")

        self.timebase = timebase
        self.codec = codec
        self.contents: list[SerialSub] = []

        if codec == "ass":
            time_code = re.compile(r"(.*)(\d+:\d+:[\d.]+)(.*)(\d+:\d+:[\d.]+)(.*)")
        if codec == "webvtt":
            time_code = re.compile(r"()(\d+:[\d.]+)( --> )(\d+:[\d.]+)(\n.*)")
        if codec == "mov_text":
            time_code = re.compile(r"()(\d+:\d+:[\d,]+)( --> )(\d+:\d+:[\d,]+)(\n.*)")

        i = 0
        for reg in re.finditer(time_code, text):
            i += 1
            if i == 1:
                self.header = text[: reg.span()[0]]

            self.contents.append(
                SerialSub(
                    self.to_frame(reg.group(2)),
                    self.to_frame(reg.group(4)),
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
        with open(file_path, "w") as file:
            file.write(self.header)
            for c in self.contents:
                file.write(
                    f"{c.before}{to_timecode(c.start / self.timebase, self.codec)}"
                    f"{c.middle}{to_timecode(c.end / self.timebase, self.codec)}"
                    f"{c.after}"
                )
            file.write(self.footer)

    def to_frame(self, text: str) -> int:
        if self.codec == "mov_text":
            time_format = r"(\d+):?(\d+):([\d,]+)"
        else:
            time_format = r"(\d+):?(\d+):([\d.]+)"

        nums = re.match(time_format, text)
        assert nums is not None

        hours, minutes, seconds = nums.groups()
        seconds = seconds.replace(",", ".", 1)
        return round(
            (int(hours) * 3600 + int(minutes) * 60 + float(seconds)) * self.timebase
        )


def cut_subtitles(
    ffmpeg: FFmpeg,
    timeline: Timeline,
    temp: str,
    log: Log,
) -> None:
    inp = timeline.inp
    chunks = timeline.chunks

    for s, sub in enumerate(inp.subtitles):
        if chunks is None:
            log.error("Timeline too complex for subtitles")

        file_path = os.path.join(temp, f"{s}s.{sub.ext}")
        new_path = os.path.join(temp, f"new{s}s.{sub.ext}")

        parser = SubtitleParser()

        if sub.codec in parser.supported_codecs:
            with open(file_path) as file:
                parser.parse(file.read(), timeline.timebase, sub.codec)
        else:
            convert_path = os.path.join(temp, f"{s}s_convert.vtt")
            ffmpeg.run(["-i", file_path, convert_path])
            with open(convert_path) as file:
                parser.parse(file.read(), timeline.timebase, "webvtt")

        parser.edit(chunks)
        parser.write(new_path)
