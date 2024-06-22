from __future__ import annotations

import sys
from datetime import timedelta
from shutil import get_terminal_size, rmtree
from time import perf_counter, sleep
from typing import NoReturn


class Log:
    __slots__ = ("is_debug", "quiet", "temp", "machine", "start_time", "no_color")

    def __init__(
        self,
        is_debug: bool = False,
        quiet: bool = False,
        temp: str | None = None,
        machine: bool = False,
        no_color: bool = True,
    ):
        self.is_debug = is_debug
        self.quiet = quiet
        self.temp = temp
        self.machine = machine
        self.no_color = no_color
        self.start_time = 0 if self.quiet or self.machine else perf_counter()

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
        if self.machine:
            print(message, flush=True)
        elif not self.quiet:
            buffer = " " * (get_terminal_size().columns - len(message) - 3)
            sys.stdout.write(f"  {message}{buffer}\r")

    def print(self, message: str) -> None:
        if not self.quiet:
            self.conwrite("")
            sys.stdout.write(f"{message}\n")

    def warning(self, message: str) -> None:
        if not self.quiet:
            self.conwrite("")
            sys.stderr.write(f"Warning! {message}\n")

    def stop_timer(self) -> None:
        if not self.quiet and not self.machine:
            second_len = round(perf_counter() - self.start_time, 2)
            minute_len = timedelta(seconds=round(second_len))

            sys.stdout.write(f"Finished. took {second_len} seconds ({minute_len})\n")

    def error(self, message: str | Exception) -> NoReturn:
        if self.is_debug and isinstance(message, Exception):
            self.cleanup()
            raise message

        self.conwrite("")
        if self.no_color:
            sys.stderr.write(f"Error! {message}\n")
        else:
            sys.stderr.write(f"\033[31;40mError! {message}\033[0m\n")

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
