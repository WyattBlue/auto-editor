import os
import re
import subprocess
from typing import List

from auto_editor.utils.log import Log
from auto_editor.utils.func import get_stdout
from auto_editor.ffwrapper import FFmpeg


def get_domain(url: str) -> str:
    from urllib.parse import urlparse

    t = urlparse(url).netloc
    return ".".join(t.split(".")[-2:])


def download_video(my_input: str, args, ffmpeg: FFmpeg, log: Log) -> str:
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

    location = get_stdout(
        [yt_dlp_path, "--get-filename", "--no-warnings"] + cmd
    ).strip()

    if not os.path.isfile(location):
        subprocess.run([yt_dlp_path] + cmd)

    if not os.path.isfile(location):
        log.error(f"Download file wasn't created: {location}")

    return location


def valid_input(inputs: List[str], ffmpeg: FFmpeg, args, log: Log) -> List[str]:
    new_inputs = []

    for my_input in inputs:
        if os.path.isfile(my_input):
            _, ext = os.path.splitext(my_input)
            if ext == "":
                log.error("File must have an extension.")
            new_inputs.append(my_input)

        elif my_input.startswith("http://") or my_input.startswith("https://"):
            new_inputs.append(download_video(my_input, args, ffmpeg, log))
        else:
            if os.path.isdir(my_input):
                log.error("Input must be a file or a URL.")
            log.error(f"Could not find file: {my_input}")

    return new_inputs
