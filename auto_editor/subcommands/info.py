from __future__ import annotations

import os.path
import sys
from dataclasses import dataclass, field
from typing import Any, Literal, TypedDict

from auto_editor.ffwrapper import initFileInfo
from auto_editor.lang.json import dump
from auto_editor.make_layers import make_sane_timebase
from auto_editor.timeline import v3
from auto_editor.utils.func import aspect_ratio
from auto_editor.utils.log import Log
from auto_editor.vanparse import ArgumentParser


@dataclass(slots=True)
class InfoArgs:
    json: bool = False
    help: bool = False
    input: list[str] = field(default_factory=list)


def info_options(parser: ArgumentParser) -> ArgumentParser:
    parser.add_required("input", nargs="*")
    parser.add_argument("--json", flag=True, help="Export info in JSON format")
    return parser


class VideoJson(TypedDict):
    codec: str
    fps: str
    resolution: list[int]
    aspect_ratio: list[int]
    pixel_aspect_ratio: str
    duration: float
    pix_fmt: str | None
    color_range: int
    color_space: int
    color_primaries: int
    color_transfer: int
    timebase: str
    bitrate: int
    lang: str | None


class AudioJson(TypedDict):
    codec: str
    samplerate: int
    channels: int
    duration: float
    bitrate: int
    lang: str | None


class SubtitleJson(TypedDict):
    codec: str
    lang: str | None


class ContainerJson(TypedDict):
    duration: float
    bitrate: int


class MediaJson(TypedDict, total=False):
    video: list[VideoJson]
    audio: list[AudioJson]
    subtitle: list[SubtitleJson]
    container: ContainerJson
    type: Literal["media", "timeline", "unknown"]
    recommendedTimebase: str
    version: Literal["v1", "v3"]
    clips: int


def main(sys_args: list[str] = sys.argv[1:]) -> None:
    args = info_options(ArgumentParser("info")).parse_args(InfoArgs, sys_args)

    log = Log(quiet=not args.json)

    file_info: dict[str, MediaJson] = {}

    for file in args.input:
        if not os.path.isfile(file):
            log.error(f"Could not find '{file}'")

        ext = os.path.splitext(file)[1]
        if ext == ".json":
            from auto_editor.formats.json import read_json

            tl = read_json(file, log)
            file_info[file] = {"type": "timeline"}
            file_info[file]["version"] = "v3" if isinstance(tl, v3) else "v1"

            clip_lens = [clip.dur / clip.speed for clip in tl.a[0]]
            file_info[file]["clips"] = len(clip_lens)

            continue

        if ext in (".xml", ".fcpxml", ".mlt"):
            file_info[file] = {"type": "timeline"}
            continue

        src = initFileInfo(file, log)

        if len(src.videos) + len(src.audios) + len(src.subtitles) == 0:
            file_info[file] = {"type": "unknown"}
            continue

        file_info[file] = {
            "type": "media",
            "recommendedTimebase": "30/1",
            "video": [],
            "audio": [],
            "subtitle": [],
            "container": {
                "duration": src.duration,
                "bitrate": src.bitrate,
            },
        }

        if src.videos:
            recTb = make_sane_timebase(src.videos[0].fps)
            file_info[file]["recommendedTimebase"] = (
                f"{recTb.numerator}/{recTb.denominator}"
            )

        for track, v in enumerate(src.videos):
            w, h = v.width, v.height

            vid: VideoJson = {
                "codec": v.codec,
                "fps": str(v.fps),
                "resolution": [w, h],
                "aspect_ratio": list(aspect_ratio(w, h)),
                "pixel_aspect_ratio": str(v.sar).replace("/", ":"),
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

    if args.json:
        dump(file_info, sys.stdout, indent=4)
        return

    def is_null(key: str, val: object) -> bool:
        return val is None or (key in ("bitrate", "duration") and val == 0.0)

    def stream_to_text(text: str, label: str, streams: list[dict[str, Any]]) -> str:
        if len(streams) > 0:
            text += f" - {label}:\n"

        for s, stream in enumerate(streams):
            text += f"   - track {s}:\n"
            for key, value in stream.items():
                if not is_null(key, value):
                    if isinstance(value, list):
                        sep = "x" if key == "resolution" else ":"
                        value = sep.join(f"{x}" for x in value)

                    if key in (
                        "color_range",
                        "color_space",
                        "color_transfer",
                        "color_primaries",
                    ):
                        if key == "color_range":
                            if value == 1:
                                text += "     - color range: 1 (tv)\n"
                            elif value == 2:
                                text += "     - color range: 2 (pc)\n"
                        elif value == 1:
                            text += f"     - {key.replace('_', ' ')}: 1 (bt709)\n"
                        elif value != 2:
                            text += f"     - {key.replace('_', ' ')}: {value}\n"
                    else:
                        text += f"     - {key.replace('_', ' ')}: {value}\n"
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
