from __future__ import annotations

from dataclasses import dataclass, field
from typing import TypedDict


class DictContainer(TypedDict, total=False):
    allow_video: bool
    allow_audio: bool
    allow_subtitle: bool
    allow_image: bool
    max_videos: int | None
    max_audios: int | None
    max_subtitles: int | None
    vcodecs: list[str] | None
    acodecs: list[str] | None
    scodecs: list[str] | None
    vstrict: bool
    sstrict: bool
    disallow_v: list[str]
    samplerate: list[int] | None


@dataclass(slots=True)
class Container:
    allow_video: bool = False
    allow_audio: bool = False
    allow_subtitle: bool = False
    allow_image: bool = False
    max_videos: int | None = None
    max_audios: int | None = None
    max_subtitles: int | None = None
    vcodecs: list[str] | None = None
    acodecs: list[str] | None = None
    scodecs: list[str] | None = None
    vstrict: bool = False
    sstrict: bool = False
    disallow_v: list[str] = field(default_factory=list)
    samplerate: list[int] | None = None  # Any samplerate is allowed


h264_en = [
    "h264",
    "libx264",
    "libx264rgb",
    "libopenh264",
    "h264_videotoolbox",
    "h264_amf",
    "h264_nvenc",
    "h264_qsv",
]
hevc_en = ["hevc", "libx265", "hevc_videotoolbox", "hevc_amf", "hevc_nvenc", "hevc_qsv"]
av1_en = ["av1", "libaom-av1", "av1_nvenc", "av1_amf"]
prores_en = ["prores", "prores_videotoolbox", "prores_aw", "prores_ks"]
aac_en = ["aac", "aac_at", "libfdk_aac"]
opus_en = ["opus", "libopus"]

h265: DictContainer = {
    "allow_video": True,
    "vcodecs": hevc_en + ["mpeg4"] + h264_en,
}
h264: DictContainer = {
    "allow_video": True,
    "vcodecs": h264_en + ["mpeg4"] + hevc_en,
}
aac: DictContainer = {
    "allow_audio": True,
    "max_audios": 1,
    "acodecs": aac_en,
}
ass: DictContainer = {
    "allow_subtitle": True,
    "scodecs": ["ass", "ssa"],
    "max_subtitles": 1,
    "sstrict": True,
}
mp4: DictContainer = {
    "allow_video": True,
    "allow_audio": True,
    "allow_subtitle": True,
    "allow_image": True,
    "vcodecs": h264_en + hevc_en + av1_en + ["vp9", "mpeg4", "mpeg2video", "mjpeg"],
    "acodecs": aac_en + opus_en + ["mp3", "flac", "vorbis", "libvorbis", "ac3", "mp2"],
    "vstrict": True,
}
ogg: DictContainer = {
    "allow_video": True,
    "allow_audio": True,
    "allow_subtitle": True,
    "vcodecs": ["libtheora", "theora"],
    "acodecs": opus_en + ["libvorbis", "vorbis", "flac", "speex"],
    "vstrict": True,
}

mka_audio = (
    ["libvorbis", "vorbis"]
    + aac_en
    + opus_en
    + [
        "mp3",
        "flac",
        "ac3",
        "mp2",
        "wmav2",
        "pcm_s16le",
        "pcm_alaw",
        "pcm_f32le",
        "pcm_f64le",
        "pcm_mulaw",
        "pcm_s16be",
        "pcm_s24be",
        "pcm_s24le",
        "pcm_s32be",
        "pcm_s32le",
        "pcm_u8",
    ]
)

containers: dict[str, DictContainer] = {
    # Aliases section
    "aac": aac,
    "adts": aac,
    "ass": ass,
    "ssa": ass,
    "264": h264,
    "h264": h264,
    "265": h265,
    "h265": h265,
    "hevc": h265,
    "mp4": mp4,
    "m4a": mp4,
    "ogg": ogg,
    "ogv": ogg,
    "apng": {
        "allow_video": True,
        "max_videos": 1,
        "vcodecs": ["apng"],
        "vstrict": True,
    },
    "gif": {
        "allow_video": True,
        "max_videos": 1,
        "vcodecs": ["gif"],
        "vstrict": True,
    },
    "wav": {
        "allow_audio": True,
        "max_audios": 1,
        "acodecs": [
            "pcm_s16le",
            "mp3",
            "mp2",
            "wmav2",
            "pcm_alaw",
            "pcm_f32le",
            "pcm_f64le",
            "pcm_mulaw",
            "pcm_s24le",
            "pcm_s32le",
            "pcm_u8",
        ],
    },
    "ast": {
        "allow_audio": True,
        "max_audios": 1,
        "acodecs": ["pcm_s16be_planar"],
    },
    "mp3": {
        "allow_audio": True,
        "max_audios": 1,
        "acodecs": ["mp3"],
    },
    "opus": {
        "allow_audio": True,
        "acodecs": opus_en + ["flac", "libvorbis", "vorbis", "speex"],
    },
    "oga": {
        "allow_audio": True,
        "acodecs": opus_en + ["flac", "libvorbis", "vorbis", "speex"],
    },
    "flac": {
        "allow_audio": True,
        "max_audios": 1,
        "acodecs": ["flac"],
    },
    "webm": {
        "allow_video": True,
        "allow_audio": True,
        "allow_subtitle": True,
        "vcodecs": ["vp9", "vp8"] + av1_en,
        "acodecs": opus_en + ["vorbis", "libvorbis"],
        "scodecs": ["webvtt"],
        "vstrict": True,
        "sstrict": True,
    },
    "srt": {
        "allow_subtitle": True,
        "scodecs": ["srt"],
        "max_subtitles": 1,
        "sstrict": True,
    },
    "vtt": {
        "allow_subtitle": True,
        "scodecs": ["webvtt"],
        "max_subtitles": 1,
        "sstrict": True,
    },
    "avi": {
        "allow_video": True,
        "allow_audio": True,
        "vcodecs": ["mpeg4"] + h264_en + ["prores", "mjpeg", "mpeg2video", "rawvideo"],
        "acodecs": ["mp3"]
        + aac_en
        + [
            "flac",
            "vorbis",
            "libvorbis",
            "mp2",
            "wmav2",
            "pcm_s16le",
            "pcm_alaw",
            "pcm_f32le",
            "pcm_f64le",
            "pcm_mulaw",
            "pcm_s24le",
            "pcm_s32le",
            "pcm_u8",
        ],
        "disallow_v": hevc_en + ["apng", "gif"],
    },
    "wmv": {
        "allow_video": True,
        "allow_audio": True,
        "vcodecs": ["msmpeg4v3"]
        + h264_en
        + ["mpeg4", "mpeg2video", "mjpeg", "rawvideo"],
        "acodecs": ["wmav2"]
        + aac_en
        + [
            "mp3",
            "flac",
            "vorbis",
            "libvorbis",
            "ac3",
            "mp2",
            "pcm_s16le",
            "pcm_alaw",
            "pcm_f32le",
            "pcm_f64le",
            "pcm_mulaw",
            "pcm_s24le",
            "pcm_s32le",
            "pcm_u8",
        ],
        "vstrict": True,
    },
    "mkv": {
        "allow_video": True,
        "allow_audio": True,
        "allow_subtitle": True,
        "allow_image": True,
        "vcodecs": h264_en
        + hevc_en
        + prores_en
        + [
            "vp9",
            "vp8",
            "mpeg4",
            "mpeg2video",
            "msmpeg4v3",
            "mjpeg",
            "gif",
            "rawvideo",
        ],
        "acodecs": mka_audio,
        "disallow_v": ["apng"],
    },
    "mka": {
        "allow_audio": True,
        "acodecs": mka_audio,
    },
    "mov": {
        "allow_video": True,
        "allow_audio": True,
        "allow_subtitle": True,
        "vcodecs": h264_en
        + hevc_en
        + prores_en
        + [
            "mpeg4",
            "mpeg2video",
            "msmpeg4v3",
            "mjpeg",
            "gif",
            "flv1",
            "dvvideo",
            "rawvideo",
        ],
        "acodecs": aac_en
        + [
            "mp3",
            "vorbis",
            "libvorbis",
            "ac3",
            "mp2",
            "wmav2",
            "pcm_s16le",
            "pcm_alaw",
            "pcm_f32be",
            "pcm_f32le",
            "pcm_f64be",
            "pcm_f64le",
            "pcm_mulaw",
            "pcm_s16be",
            "pcm_s24be",
            "pcm_s24le",
            "pcm_s32be",
            "pcm_s32le",
            "pcm_s8",
            "pcm_u8",
        ],
        "disallow_v": ["apng", "vp9", "vp8"],
    },
    "swf": {
        "allow_video": True,
        "allow_audio": True,
        "vcodecs": ["flv1", "mjpeg"],
        "acodecs": ["mp3"],
        "vstrict": True,
        "samplerate": [44100, 22050, 11025],
    },
}


def container_constructor(key: str) -> Container:
    if key in containers:
        return Container(**containers[key])
    return Container(allow_video=True, allow_audio=True, allow_subtitle=True)
