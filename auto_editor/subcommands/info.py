import json
import os.path
import sys
from dataclasses import dataclass, field
from typing import List, Optional

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.func import aspect_ratio
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass
class InfoArgs:
    json: bool = False
    include_vfr: bool = False
    ffmpeg_location: Optional[str] = None
    my_ffmpeg: bool = False
    help: bool = False
    input: List[str] = field(default_factory=list)


def info_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_argument("--json", flag=True, help="Export info in JSON format.")
    parser.add_argument(
        "--include-vfr",
        "--has-vfr",
        flag=True,
        help="Display the number of Variable Frame Rate (VFR) frames.",
    )
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file.")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged.",
    )
    parser.add_required(
        "input", nargs="*", help="The path to a file you want inspected."
    )
    return parser


def main(sys_args=sys.argv[1:]):
    args = info_options(ArgumentParser("info")).parse_args(InfoArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg, False)
    log = Log(quiet=not args.json)

    file_info = {}

    for file in args.input:
        if not os.path.isfile(file):
            Log().error(f"Could not find file: {file}")

        inp = FileInfo(file, ffmpeg, log)

        if len(inp.videos) + len(inp.audios) + len(inp.subtitles) == 0:
            file_info[file] = {"media": "invalid"}
            continue

        file_info[file] = {
            "video": [],
            "audio": [],
            "subtitle": [],
            "container": {},
        }

        for track, stream in enumerate(inp.videos):
            w, h = stream.width, stream.height
            w_, h_ = aspect_ratio(w, h)

            fps = stream.fps
            if fps is not None and int(fps) == float(fps):
                fps = int(fps)

            vid = {
                "codec": stream.codec,
                "fps": fps,
                "resolution": [w, h],
                "aspect ratio": [w_, h_],
                "pix_fmt": stream.pix_fmt,
                "color_range": stream.color_range,
                "color_space": stream.color_space,
                "color_primaries": stream.color_primaries,
                "color_transfer": stream.color_transfer,
                "timebase": str(stream.time_base),
                "bitrate": stream.bitrate,
                "lang": stream.lang,
            }
            file_info[file]["video"].append(vid)

        for track, stream in enumerate(inp.audios):
            aud = {
                "codec": stream.codec,
                "samplerate": stream.samplerate,
                "bitrate": stream.bitrate,
                "lang": stream.lang,
            }
            file_info[file]["audio"].append(aud)

        for track, stream in enumerate(inp.subtitles):
            sub = {"codec": stream.codec, "lang": stream.lang}
            file_info[file]["subtitle"].append(sub)

        cont = {"bitrate": inp.bitrate}

        if args.include_vfr:
            fps_mode = ffmpeg.pipe(
                [
                    "-i",
                    file,
                    "-hide_banner",
                    "-vf",
                    "vfrdet",
                    "-an",
                    "-f",
                    "null",
                    "-",
                ]
            ).strip()
            if "VFR:" in fps_mode:
                fps_mode = (fps_mode[fps_mode.index("VFR:") :]).strip()

            cont["fps_mode"] = fps_mode

        file_info[file]["container"] = cont

    if args.json:
        print(json.dumps(file_info, indent=4))
        return

    def stream_to_text(text: str, label: str, streams) -> str:
        if len(streams) > 0:
            text += f" - {label}:\n"

        for s, stream in enumerate(streams):
            text += f"   - track {s}:\n"
            for key, value in stream.items():
                if value is not None:
                    if isinstance(value, list):
                        sep = "x" if key == "resolution" else ":"
                        value = sep.join([str(x) for x in value])

                    text += f"     - {key}: {value}\n"
        return text

    text = ""
    for name, info in file_info.items():
        text += f"{name}:\n"
        if "media" in info:
            text += " - invalid media\n\n"
            continue

        for label, streams in info.items():
            if isinstance(streams, dict):
                text += " - container:\n"
                for key, value in streams.items():
                    text += f"   - {key}: {value}\n"
            else:
                text = stream_to_text(text, label, streams)
        text += "\n"

    sys.stdout.write(text)


if __name__ == "__main__":
    main()
