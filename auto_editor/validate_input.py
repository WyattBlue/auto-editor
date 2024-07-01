from __future__ import annotations

import os
import re
import subprocess
import sys

from auto_editor.ffwrapper import FFmpeg
from auto_editor.utils.func import get_stdout
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


def get_domain(url: str) -> str:
    from urllib.parse import urlparse

    t = urlparse(url).netloc
    return ".".join(t.split(".")[-2:])


def download_video(my_input: str, args: Args, ffmpeg: FFmpeg, log: Log) -> str:
    log.conwrite("Downloading video...")

    download_format = args.download_format

    if download_format is None and get_domain(my_input) == "youtube.com":
        download_format = "bestvideo[ext=mp4]+bestaudio[ext=m4a]"

    if args.output_format is None:
        output_format = re.sub(r"\W+", "-", os.path.splitext(my_input)[0]) + ".%(ext)s"
    else:
        output_format = args.output_format

    yt_dlp_path = args.yt_dlp_location

    cmd = ["--ffmpeg-location", ffmpeg.path]

    if download_format is not None:
        cmd.extend(["-f", download_format])

    cmd.extend(["-o", output_format, my_input])

    if args.yt_dlp_extras is not None:
        cmd.extend(args.yt_dlp_extras.split(" "))

    try:
        location = get_stdout(
            [yt_dlp_path, "--get-filename", "--no-warnings"] + cmd
        ).strip()
    except FileNotFoundError:
        msg = "Could not find program 'yt-dlp' when attempting to download a URL. Install yt-dlp with "
        if sys.platform == "win32":
            msg += "your favorite package manager (pip, choco, winget)."
        elif sys.platform == "darwin":
            msg += "brew or pip and make sure it's in PATH."
        else:
            msg += "pip or your favorite package manager and make sure it's in PATH."
        log.error(msg)

    if not os.path.isfile(location):
        subprocess.run([yt_dlp_path] + cmd)

    if not os.path.isfile(location):
        log.error(f"Download file wasn't created: {location}")

    return location


def valid_input(inputs: list[str], ffmpeg: FFmpeg, args: Args, log: Log) -> list[str]:
    result = []

    for my_input in inputs:
        if my_input.startswith("http://") or my_input.startswith("https://"):
            result.append(download_video(my_input, args, ffmpeg, log))
        else:
            _, ext = os.path.splitext(my_input)
            if ext == "":
                if os.path.isdir(my_input):
                    log.error("Input must be a file or a URL, not a directory.")
                log.error("Input file must have an extension.")
            result.append(my_input)

    return result
