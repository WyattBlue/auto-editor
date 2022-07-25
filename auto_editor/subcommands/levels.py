from __future__ import annotations

import os
import sys
import tempfile
from dataclasses import dataclass, field

import numpy as np
from numpy.typing import NDArray

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.bar import Bar
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass
class LevelArgs:
    kind: str = "audio"
    track: int = 0
    ffmpeg_location: str | None = None
    my_ffmpeg: bool = False
    help: bool = False
    input: list[str] = field(default_factory=list)


def levels_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_argument(
        "--kind",
        choices=["audio", "motion", "pixeldiff"],
        help="Select the kind of detection to analyze.",
    )
    parser.add_argument(
        "--track",
        type=int,
        help="Select the track to get. If `--kind` is set to motion, track will look "
        "at video tracks instead of audio.",
    )
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file.")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged.",
    )
    parser.add_required(
        "input", nargs="*", help="Path to the file to have its levels dumped."
    )
    return parser


def print_float_list(arr: NDArray[np.float_]) -> None:
    for a in arr:
        sys.stdout.write(f"{a:.20f}\n")


def print_int_list(arr: NDArray[np.uint64]) -> None:
    for a in arr:
        sys.stdout.write(f"{a}\n")


def main(sys_args=sys.argv[1:]) -> None:
    parser = levels_options(ArgumentParser("levels"))
    args = parser.parse_args(LevelArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)

    bar = Bar("none")
    temp = tempfile.mkdtemp()
    log = Log(temp=temp)

    inp = FileInfo(args.input[0], ffmpeg, log)
    timebase = inp.get_fps()

    if args.kind == "audio":
        from auto_editor.analyze.audio import audio_detection
        from auto_editor.wavfile import read

        if args.track >= len(inp.audios):
            log.error(f"Audio track '{args.track}' does not exist.")

        read_track = os.path.join(temp, f"{args.track}.wav")

        ffmpeg.run(
            ["-i", inp.path, "-ac", "2", "-map", f"0:a:{args.track}", read_track]
        )

        if not os.path.isfile(read_track):
            log.error("Audio track file not found!")

        sr, samples = read(read_track)
        print_float_list(audio_detection(samples, sr, timebase, bar, log))

    if args.kind in ("motion", "pixeldiff") and args.track >= len(inp.videos):
        log.error(f"Video stream '{args.track}' does not exist.")

    if args.kind == "motion":
        from auto_editor.analyze.motion import motion_detection

        print_float_list(
            motion_detection(inp.path, args.track, timebase, bar, width=400, blur=9)
        )

    if args.kind == "pixeldiff":
        from auto_editor.analyze.pixeldiff import pixel_difference

        print_int_list(pixel_difference(inp.path, args.track, timebase, bar))

    log.cleanup()


if __name__ == "__main__":
    main()
