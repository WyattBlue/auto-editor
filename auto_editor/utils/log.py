from __future__ import annotations

import sys
from datetime import timedelta
from shutil import get_terminal_size, rmtree
from tempfile import mkdtemp
from time import perf_counter, sleep
from typing import TYPE_CHECKING, NoReturn

if TYPE_CHECKING:
    import av


class Log:
    __slots__ = ("is_debug", "quiet", "machine", "no_color", "_temp", "_ut", "_s")

    def __init__(
        self,
        is_debug: bool = False,
        quiet: bool = False,
        temp_dir: str | None = None,
        machine: bool = False,
        no_color: bool = True,
    ):
        self.is_debug = is_debug
        self.quiet = quiet
        self.machine = machine
        self.no_color = no_color
        self._temp: str | None = None
        self._ut = temp_dir
        self._s = 0 if self.quiet or self.machine else perf_counter()

    def debug(self, message: object) -> None:
        if self.is_debug:
            self.conwrite("")
            sys.stderr.write(f"Debug: {message}\n")

    @property
    def temp(self) -> str:
        if self._temp is not None:
            return self._temp

        if self._ut is None:
            result = mkdtemp()
        else:
            import os.path
            from os import listdir, mkdir

            if os.path.isfile(self._ut):
                self.error("Temp directory cannot be an already existing file.")

            if os.path.isdir(self._ut):
                if len(listdir(self._ut)) != 0:
                    self.error("Temp directory should be empty!")
            else:
                mkdir(self._ut)
            result = self._ut

        self.debug(f"Temp Directory: {result}")
        self._temp = result
        return result

    def cleanup(self) -> None:
        if self._temp is None:
            return
        try:
            rmtree(self._temp)
            self.debug("Removed Temp Directory.")
        except FileNotFoundError:
            pass
        except PermissionError:
            sleep(0.1)
            try:
                rmtree(self._temp)
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
            second_len = round(perf_counter() - self._s, 2)
            minute_len = timedelta(seconds=round(second_len))

            sys.stdout.write(f"Finished. took {second_len} seconds ({minute_len})\n")

    def experimental(self, codec: av.Codec) -> None:
        if codec.experimental:
            self.error(f"`{codec.name}` is an experimental codec")

    @staticmethod
    def deprecated(message: str) -> None:
        sys.stderr.write(f"\033[1m\033[33m{message}\033[0m\n")

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
