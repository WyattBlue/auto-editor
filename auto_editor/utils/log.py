from __future__ import annotations

import sys
from datetime import timedelta
from pathlib import Path
from shutil import get_terminal_size, rmtree
from time import perf_counter, sleep
from typing import NoReturn


class Timer:
    __slots__ = ("start_time", "quiet")

    def __init__(self, quiet: bool = False):
        self.start_time = perf_counter()
        self.quiet = quiet

    def stop(self) -> None:
        if not self.quiet:
            second_len = round(perf_counter() - self.start_time, 2)
            minute_len = timedelta(seconds=round(second_len))

            sys.stdout.write(f"Finished. took {second_len} seconds ({minute_len})\n")


class Log:
    __slots__ = ("is_debug", "quiet", "temp")

    def __init__(
        self, show_debug: bool = False, quiet: bool = False, temp: str | None = None
    ):
        self.is_debug = show_debug
        self.quiet = quiet
        self.temp = temp

    def debug(self, message: object) -> None:
        if self.is_debug:
            self.conwrite("")
            sys.stderr.write(f"Debug: {message}\n")

    def cleanup(self) -> None:
        if self.temp is None:
            return
        try:
            rmtree(self.temp)
            self.debug("Removed Temp Directory.")
        except FileNotFoundError:
            pass
        except PermissionError:
            sleep(0.1)
            try:
                rmtree(self.temp)
                self.debug("Removed Temp Directory.")
            except Exception as e:
                self.debug(f"Failed to delete temp dir:\n{e}")

    def conwrite(self, message: str) -> None:
        if not self.quiet:
            buffer = " " * (get_terminal_size().columns - len(message) - 3)
            sys.stdout.write(f"  {message}{buffer}\r")

    def error(self, message: str | Exception) -> NoReturn:
        if self.is_debug and isinstance(message, Exception):
            self.cleanup()
            raise message

        self.conwrite("")
        sys.stderr.write(f"Error! {message}\n")
        self.cleanup()
        from platform import system

        if system() == "Linux":
            sys.exit(1)
        else:
            try:
                sys.exit(1)
            except SystemExit:
                import os

                os._exit(1)

    def nofile(self, path: str | Path) -> NoReturn:
        self.error(f"Could not find '{path}'")

    def warning(self, message: str) -> None:
        if not self.quiet:
            self.conwrite("")
            sys.stderr.write(f"Warning! {message}\n")

    def print(self, message: str) -> None:
        if not self.quiet:
            self.conwrite("")
            sys.stdout.write(f"{message}\n")
