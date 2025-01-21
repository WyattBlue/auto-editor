import glob
import os
import sys
from shutil import rmtree
from tempfile import gettempdir

import numpy as np

from auto_editor import __version__


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    cache_dir = os.path.join(gettempdir(), f"ae-{__version__}")

    if sys_args and sys_args[0] in {"clean", "clear"}:
        rmtree(cache_dir, ignore_errors=True)
        return

    if not os.path.exists(cache_dir):
        print("Empty cache")
        return

    cache_files = glob.glob(os.path.join(cache_dir, "*.npz"))
    if not cache_files:
        print("Empty cache")
        return

    def format_bytes(size: float) -> str:
        for unit in {"B", "KiB", "MiB", "GiB", "TiB"}:
            if size < 1024:
                return f"{size:.2f} {unit}"
            size /= 1024
        return f"{size:.2f} PiB"

    GRAY = "\033[90m"
    GREEN = "\033[32m"
    BLUE = "\033[34m"
    YELLOW = "\033[33m"
    RESET = "\033[0m"

    total_size = 0
    for cache_file in cache_files:
        try:
            with np.load(cache_file, allow_pickle=False) as npzfile:
                array = npzfile["data"]
                key = os.path.basename(cache_file)[:-4]  # Remove .npz extension

                hash_part = key[:16]
                rest_part = key[16:]

                size = array.nbytes
                total_size += size
                size_str = format_bytes(size)
                size_num, size_unit = size_str.rsplit(" ", 1)

                print(
                    f"{YELLOW}entry: {GRAY}{hash_part}{RESET}{rest_part}  "
                    f"{YELLOW}size: {GREEN}{size_num} {BLUE}{size_unit}{RESET}"
                )
        except Exception as e:
            print(f"Error reading {cache_file}: {e}")

    total_str = format_bytes(total_size)
    total_num, total_unit = total_str.rsplit(" ", 1)
    print(f"\n{YELLOW}total cache size: {GREEN}{total_num} {BLUE}{total_unit}{RESET}")


if __name__ == "__main__":
    main()
