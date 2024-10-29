from __future__ import annotations

from dataclasses import dataclass
from typing import TypedDict

import av
from av.codec import Codec


class DictContainer(TypedDict, total=False):
    max_videos: int | None
    max_audios: int | None
    max_subtitles: int | None
    samplerate: list[int] | None


@dataclass(slots=True)
class Container:
    allow_image: bool
    vcodecs: set[str]
    acodecs: set[str]
    scodecs: set[str]
    default_vid: str
    default_aud: str
    default_sub: str
    max_videos: int | None = None
    max_audios: int | None = None
    max_subtitles: int | None = None
    samplerate: list[int] | None = None  # Any samplerate is allowed


containers: dict[str, DictContainer] = {
    "aac": {"max_audios": 1},
    "adts": {"max_audios": 1},
    "ass": {"max_subtitles": 1},
    "ssa": {"max_subtitles": 1},
    "apng": {"max_videos": 1},
    "gif": {"max_videos": 1},
    "wav": {"max_audios": 1},
    "ast": {"max_audios": 1},
    "mp3": {"max_audios": 1},
    "flac": {"max_audios": 1},
    "srt": {"max_subtitles": 1},
    "vtt": {"max_subtitles": 1},
    "swf": {"samplerate": [44100, 22050, 11025]},
}


def codec_type(x: str) -> str:
    if x in ("vp9", "vp8", "h264", "hevc", "av1", "gif", "apng"):
        return "video"
    if x in ("aac", "flac", "mp3"):
        return "audio"
    if x in ("ass", "ssa", "srt"):
        return "subtitle"

    try:
        return Codec(x, "w").type
    except Exception:
        return ""


def container_constructor(ext: str) -> Container:
    with av.open(f".{ext}", "w") as container:
        codecs = container.supported_codecs
        if ext == "webm":
            vdefault = "vp9"
        else:
            vdefault = container.default_video_codec
        adefault = container.default_audio_codec
        sdefault = container.default_subtitle_codec
        if sdefault == "none" and ext == "mp4":
            sdefault = "srt"

    vcodecs = set()
    acodecs = set()
    scodecs = set()

    for codec in codecs:
        if ext == "wav" and codec == "aac":
            continue
        kind = codec_type(codec)
        if kind == "video":
            vcodecs.add(codec)
            if codec == "h264":
                vcodecs.add("libx264")
            if codec == "av1":
                vcodecs.add("libsvtav1")
            if codec == "hevc":
                vcodecs.add("hevc_nvenc")
        if kind == "audio":
            acodecs.add(codec)
        if kind == "subtitle":
            scodecs.add(codec)

    allow_image = ext in ("mp4", "mkv")
    kwargs = containers[ext] if ext in containers else {}

    return Container(
        allow_image, vcodecs, acodecs, scodecs, vdefault, adefault, sdefault, **kwargs
    )
