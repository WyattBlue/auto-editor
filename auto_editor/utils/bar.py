from __future__ import annotations

import sys
from dataclasses import dataclass
from math import floor
from shutil import get_terminal_size
from time import localtime, time

from .func import get_stdout_bytes


def initBar(bar_type: str) -> Bar:
    icon = "⏳"
    chars: tuple[str, ...] = (" ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█")
    brackets = ("|", "|")
    machine = hide = False

    if bar_type == "classic":
        icon = "⏳"
        chars = ("░", "█")
        brackets = ("[", "]")
    if bar_type == "ascii":
        icon = "& "
        chars = ("-", "#")
        brackets = ("[", "]")
    if bar_type == "machine":
        machine = True
    if bar_type == "none":
        hide = True

    part_width = len(chars) - 1

    ampm = True
    if sys.platform == "darwin" and bar_type in {"modern", "classic", "ascii"}:
        try:
            date_format = get_stdout_bytes(
                ["defaults", "read", "com.apple.menuextra.clock", "Show24Hour"]
            )
            ampm = date_format == b"0\n"
        except FileNotFoundError:
            pass

    return Bar(icon, chars, brackets, machine, hide, part_width, ampm, [])


@dataclass(slots=True)
class Bar:
    icon: str
    chars: tuple[str, ...]
    brackets: tuple[str, str]
    machine: bool
    hide: bool
    part_width: int
    ampm: bool
    stack: list[tuple[str, int, float, float]]

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

        title, len_title, total, begin = self.stack[-1]
        progress = 0.0 if total == 0 else min(1, max(0, index / total))
        rate = 0.0 if progress == 0 else (time() - begin) / progress

        if self.machine:
            index = min(index, total)
            secs_til_eta = round(begin + rate - time(), 2)
            print(f"{title}~{index}~{total}~{secs_til_eta}", end="\r", flush=True)
            return

        new_time = self.pretty_time(begin + rate, self.ampm)

        percent = round(progress * 100, 1)
        p_pad = " " * (4 - len(str(percent)))
        columns = get_terminal_size().columns
        bar_len = max(1, columns - len_title - 35)
        bar_str = self._bar_str(progress, bar_len)

        bar = f"  {self.icon}{title} {bar_str} {p_pad}{percent}%  ETA {new_time}    \r"
        sys.stdout.write(bar)

    def start(self, total: float, title: str = "Please wait") -> None:
        len_title = 0
        in_escape = False

        for char in title:
            if not in_escape:
                if char == "\033":
                    in_escape = True
                else:
                    len_title += 1
            elif char == "m":
                in_escape = False

        self.stack.append((title, len_title, total, time()))

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

    def end(self) -> None:
        sys.stdout.write(" " * (get_terminal_size().columns - 2) + "\r")
        if self.stack:
            self.stack.pop()
