from __future__ import annotations

from dataclasses import dataclass, field
from typing import TypedDict


class DictContainer(TypedDict, total=False):
    name: str | None
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


@dataclass
class Container:
    name: str | None = None
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


# Define aliases
h265: DictContainer = {
    "name": "H.265 / High Efficiency Video Coding (HEVC) / MPEG-H Part 2",
    "allow_video": True,
    "vcodecs": ["hevc", "mpeg4", "h264"],
}
h264: DictContainer = {
    "name": "H.264 / Advanced Video Coding (AVC) / MPEG-4 Part 10",
    "allow_video": True,
    "vcodecs": ["h264", "mpeg4", "hevc"],
}
aac: DictContainer = {
    "name": "Advanced Audio Coding",
    "allow_audio": True,
    "max_audios": 1,
    "acodecs": ["aac"],
}
ass: DictContainer = {
    "name": "SubStation Alpha",
    "allow_subtitle": True,
    "scodecs": ["ass", "ssa"],
    "max_subtitles": 1,
    "sstrict": True,
}
mp4: DictContainer = {
    "name": "MP4 / MPEG-4 Part 14",
    "allow_video": True,
    "allow_audio": True,
    "allow_subtitle": True,
    "allow_image": True,
    "vcodecs": ["h264", "hevc", "vp9", "av1", "mpeg4", "mpeg2video", "mjpeg"],
    "acodecs": ["aac", "mp3", "opus", "flac", "vorbis", "libvorbis", "ac3", "mp2"],
    "vstrict": True,
    # "disallow_v": ["prores", "apng", "gif", "msmpeg4v3", "flv1", "vp8", "dvvideo", "rawvideo"],
}
ogg: DictContainer = {
    "allow_video": True,
    "allow_audio": True,
    "allow_subtitle": True,
    "vcodecs": ["libtheora", "theora"],
    "acodecs": ["libvorbis", "vorbis", "flac", "opus", "speex"],
    "vstrict": True,
}

mka_audio = [
    "libvorbis",
    "vorbis",
    "aac",
    "mp3",
    "opus",
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
        "name": "Animated Portable Network Graphics",
        "allow_video": True,
        "max_videos": 1,
        "vcodecs": ["apng"],
        "vstrict": True,
    },
    "gif": {
        "name": "Graphics Interchange Format",
        "allow_video": True,
        "max_videos": 1,
        "vcodecs": ["gif"],
        "vstrict": True,
    },
    "wav": {
        "name": "Waveform Audio File Format",
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
        "name": "AST / Audio Stream",
        "allow_audio": True,
        "max_audios": 1,
        "acodecs": ["pcm_s16be_planar"],
    },
    "mp3": {
        "name": "MP3 / MPEG-2 Audio Layer 3",
        "allow_audio": True,
        "max_audios": 1,
        "acodecs": ["mp3"],
    },
    "opus": {
        "name": "Opus",
        "allow_audio": True,
        "acodecs": ["opus", "flac", "libvorbis", "vorbis", "speex"],
    },
    "oga": {
        "allow_audio": True,
        "acodecs": ["flac", "libvorbis", "vorbis", "opus", "speex"],
    },
    "flac": {
        "name": "Free Lossless Audio Codec",
        "allow_audio": True,
        "max_audios": 1,
        "acodecs": ["flac"],
    },
    "webm": {
        "name": "WebM",
        "allow_video": True,
        "allow_audio": True,
        "allow_subtitle": True,
        "vcodecs": ["vp9", "vp8", "av1", "libaom-av1"],
        "acodecs": ["opus", "vorbis", "libvorbis"],
        "scodecs": ["webvtt"],
        "vstrict": True,
        "sstrict": True,
    },
    "srt": {
        "name": "SubRip Text / Subtitle Resource Tracks",
        "allow_subtitle": True,
        "scodecs": ["srt"],
        "max_subtitles": 1,
        "sstrict": True,
    },
    "vtt": {
        "name": "Web Video Text Track",
        "allow_subtitle": True,
        "scodecs": ["webvtt"],
        "max_subtitles": 1,
        "sstrict": True,
    },
    "avi": {
        "name": "Audio Video Interleave",
        "allow_video": True,
        "allow_audio": True,
        "vcodecs": ["mpeg4", "h264", "prores", "mjpeg", "mpeg2video", "rawvideo"],
        "acodecs": [
            "mp3",
            "aac",
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
        "disallow_v": ["hevc", "apng", "gif"],
    },
    "wmv": {
        "name": "Windows Media Video",
        "allow_video": True,
        "allow_audio": True,
        "vcodecs": ["msmpeg4v3", "h264", "mpeg4", "mpeg2video", "mjpeg", "rawvideo"],
        "acodecs": [
            "wmav2",
            "aac",
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
        "name": "Matroska",
        "allow_video": True,
        "allow_audio": True,
        "allow_subtitle": True,
        "allow_image": True,
        "vcodecs": [
            "h264",
            "hevc",
            "vp9",
            "vp8",
            "prores",
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
        "name": "Matroska Audio",
        "allow_audio": True,
        "acodecs": mka_audio,
    },
    "mov": {
        "name": "QuickTime / MOV",
        "allow_video": True,
        "allow_audio": True,
        "allow_subtitle": True,
        "vcodecs": [
            "h264",
            "hevc",
            "prores",
            "mpeg4",
            "mpeg2video",
            "msmpeg4v3",
            "mjpeg",
            "gif",
            "flv1",
            "dvvideo",
            "rawvideo",
        ],
        "acodecs": [
            "aac",
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
        "name": "ShockWave Flash / Small Web Format",
        "allow_video": True,
        "allow_audio": True,
        "vcodecs": ["flv1", "mjpeg"],
        "acodecs": ["mp3"],
        "vstrict": True,
        "samplerate": [44100, 22050, 11025],
    },
    "not_in_here": {
        "allow_video": True,
        "allow_audio": True,
        "allow_subtitle": True,
    },
}


def container_constructor(key: str) -> Container:
    if key in containers:
        return Container(**containers[key])
    return Container(**containers["not_in_here"])
