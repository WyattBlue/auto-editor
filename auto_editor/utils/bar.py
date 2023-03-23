from __future__ import annotations

import sys
from math import floor
from shutil import get_terminal_size
from time import localtime, time

from .func import get_stdout_bytes


class Bar:
    def __init__(self, bar_type: str) -> None:
        self.machine = False
        self.hide = False

        self.icon = "⏳"
        self.chars: tuple[str, ...] = (" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█")
        self.brackets = ("|", "|")

        if bar_type == "classic":
            self.icon = "⏳"
            self.chars = ("░", "█")
            self.brackets = ("[", "]")
        if bar_type == "ascii":
            self.icon = "& "
            self.chars = ("-", "#")
            self.brackets = ("[", "]")
        if bar_type == "machine":
            self.machine = True
        if bar_type == "none":
            self.hide = True

        self.part_width = len(self.chars) - 1

        self.ampm = True
        if sys.platform == "darwin" and bar_type in ("modern", "classic", "ascii"):
            try:
                date_format = get_stdout_bytes(
                    ["defaults", "read", "com.apple.menuextra.clock", "Show24Hour"]
                )
                self.ampm = date_format == b"0\n"
            except FileNotFoundError:
                pass

    @staticmethod
    def pretty_time(my_time: float, ampm: bool) -> str:
        new_time = localtime(my_time)

        hours = new_time.tm_hour
        minutes = new_time.tm_min

        if ampm:
            if hours == 0:
                hours = 12
            if hours > 12:
                hours -= 12
            ampm_marker = "PM" if new_time.tm_hour >= 12 else "AM"
            return f"{hours:02}:{minutes:02} {ampm_marker}"
        return f"{hours:02}:{minutes:02}"

    def tick(self, index: float) -> None:
        if self.hide:
            return

        progress = 0.0 if self.total == 0 else min(1, max(0, index / self.total))
        rate = 0.0 if progress == 0 else (time() - self.begin_time) / progress

        if self.machine:
            index = min(index, self.total)
            raw = int(self.begin_time + rate)
            print(
                f"{self.title}~{index}~{self.total}~{self.begin_time}~{raw}",
                end="\r",
                flush=True,
            )
            return

        new_time = self.pretty_time(self.begin_time + rate, self.ampm)

        percent = round(progress * 100, 1)
        p_pad = " " * (4 - len(str(percent)))
        columns = get_terminal_size().columns
        bar_len = max(1, columns - (self.len_title + 32))
        bar_str = self._bar_str(progress, bar_len)

        bar = f"  {self.icon}{self.title} {bar_str} {p_pad}{percent}%  ETA {new_time}"

        if len(bar) > columns - 2:
            bar = bar[: columns - 2]
        else:
            bar += " " * (columns - len(bar) - 4)

        sys.stdout.write(bar + "\r")

    def start(self, total: float, title: str = "Please wait") -> None:
        self.title = title
        self.len_title = len(title)
        self.total = total
        self.begin_time = time()

        try:
            self.tick(0)
        except UnicodeEncodeError:
            self.icon = "& "
            self.chars = ("-", "#")
            self.brackets = ("[", "]")
            self.part_width = 1

    def _bar_str(self, progress: float, width: int) -> str:
        whole_width = floor(progress * width)
        remainder_width = (progress * width) % 1
        part_width = floor(remainder_width * self.part_width)
        part_char = self.chars[part_width]

        if width - whole_width - 1 < 0:
            part_char = ""

        line = (
            self.brackets[0]
            + self.chars[-1] * whole_width
            + part_char
            + self.chars[0] * (width - whole_width - 1)
            + self.brackets[1]
        )
        return line

    @staticmethod
    def end() -> None:
        sys.stdout.write(" " * (get_terminal_size().columns - 2) + "\r")
