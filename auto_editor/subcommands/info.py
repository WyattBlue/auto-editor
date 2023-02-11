from __future__ import annotations

import json
import os.path
import sys
from dataclasses import dataclass, field
from typing import Any, Literal, TypedDict

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.timeline import v3
from auto_editor.utils.func import aspect_ratio
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass
class InfoArgs:
    json: bool = False
    include_vfr: bool = False
    ffmpeg_location: str | None = None
    my_ffmpeg: bool = False
    help: bool = False
    input: list[str] = field(default_factory=list)


def info_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
    parser.add_argument("--json", flag=True, help="Export info in JSON format")
    parser.add_argument(
        "--include-vfr",
        "--has-vfr",
        flag=True,
        help="Display the number of Variable Frame Rate (VFR) frames",
    )
    parser.add_argument("--ffmpeg-location", help="Point to your custom ffmpeg file")
    parser.add_argument(
        "--my-ffmpeg",
        flag=True,
        help="Use the ffmpeg on your PATH instead of the one packaged",
    )
    return parser


class VideoJson(TypedDict):
    codec: str
    fps: str
    resolution: list[int]
    aspect_ratio: list[int]
    pixel_aspect_ratio: str | None
    duration: str | None
    pix_fmt: str
    color_range: str | None
    color_space: str | None
    color_primaries: str | None
    color_transfer: str | None
    timebase: str
    bitrate: str | None
    lang: str | None


class AudioJson(TypedDict):
    codec: str
    samplerate: int
    channels: int
    duration: str | None
    bitrate: str | None
    lang: str | None


class SubtitleJson(TypedDict):
    codec: str
    lang: str | None


class ContainerJson(TypedDict):
    duration: str
    bitrate: str | None
    fps_mode: str | None


class MediaJson(TypedDict, total=False):
    video: list[VideoJson]
    audio: list[AudioJson]
    subtitle: list[SubtitleJson]
    container: ContainerJson
    type: Literal["media", "timeline", "unknown"]
    version: Literal["v1", "v2", "v3"]
    clips: int


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    args = info_options(ArgumentParser("info")).parse_args(InfoArgs, sys_args)

    ffmpeg = FFmpeg(args.ffmpeg_location, args.my_ffmpeg)
    log = Log(quiet=not args.json)

    file_info: dict[str, MediaJson] = {}

    for file in args.input:
        if not os.path.isfile(file):
            log.nofile(file)

        ext = os.path.splitext(file)[1]
        if ext == ".json":
            from auto_editor.formats.json import read_json

            tl = read_json(file, ffmpeg, log)
            file_info[file] = {"type": "timeline"}
            file_info[file]["version"] = "v3" if isinstance(tl, v3) else "v1"

            clip_lens = [clip.dur / clip.speed for clip in tl.a[0]]
            file_info[file]["clips"] = len(clip_lens)

            continue

        if ext in (".xml", ".fcpxml", ".mlt"):
            file_info[file] = {"type": "timeline"}
            continue

        src = FileInfo(file, ffmpeg, log)

        if len(src.videos) + len(src.audios) + len(src.subtitles) == 0:
            file_info[file] = {"type": "unknown"}
            continue

        file_info[file] = {
            "type": "media",
            "video": [],
            "audio": [],
            "subtitle": [],
            "container": {
                "duration": src.duration,
                "bitrate": src.bitrate,
                "fps_mode": None,
            },
        }

        for track, v in enumerate(src.videos):
            w, h = v.width, v.height

            vid: VideoJson = {
                "codec": v.codec,
                "fps": str(v.fps),
                "resolution": [w, h],
                "aspect_ratio": list(aspect_ratio(w, h)),
                "pixel_aspect_ratio": v.sar,
                "duration": v.duration,
                "pix_fmt": v.pix_fmt,
                "color_range": v.color_range,
                "color_space": v.color_space,
                "color_primaries": v.color_primaries,
                "color_transfer": v.color_transfer,
                "timebase": str(v.time_base),
                "bitrate": v.bitrate,
                "lang": v.lang,
            }
            file_info[file]["video"].append(vid)

        for track, a in enumerate(src.audios):
            aud: AudioJson = {
                "codec": a.codec,
                "samplerate": a.samplerate,
                "channels": a.channels,
                "duration": a.duration,
                "bitrate": a.bitrate,
                "lang": a.lang,
            }
            file_info[file]["audio"].append(aud)

        for track, s_stream in enumerate(src.subtitles):
            sub: SubtitleJson = {"codec": s_stream.codec, "lang": s_stream.lang}
            file_info[file]["subtitle"].append(sub)

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

            file_info[file]["container"]["fps_mode"] = fps_mode

    if args.json:
        print(json.dumps(file_info, indent=4))
        return

    def stream_to_text(text: str, label: str, streams: list[dict[str, Any]]) -> str:
        if len(streams) > 0:
            text += f" - {label}:\n"

        for s, stream in enumerate(streams):
            text += f"   - track {s}:\n"
            for key, value in stream.items():
                if value is not None:
                    key = key.replace("_", " ")
                    if isinstance(value, list):
                        sep = "x" if key == "resolution" else ":"
                        value = sep.join([str(x) for x in value])

                    text += f"     - {key}: {value}\n"
        return text

    text = ""
    for name, info in file_info.items():
        text += f"{name}:\n"

        for label, streams in info.items():
            if isinstance(streams, list):
                text = stream_to_text(text, label, streams)
                continue
            elif isinstance(streams, dict):
                text += " - container:\n"
                for key, value in streams.items():
                    if value is not None:
                        text += f"   - {key}: {value}\n"
            elif label != "type" or streams != "media":
                text += f" - {label}: {streams}\n"
        text += "\n"

    sys.stdout.write(text)


if __name__ == "__main__":
    main()
