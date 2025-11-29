from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

import av

from log import Log


@dataclass(slots=True, frozen=True)
class VideoStream:
    width: int
    height: int
    codec: str
    fps: Fraction
    duration: float
    sar: Fraction
    time_base: Fraction | None
    pix_fmt: str | None
    color_range: int
    color_space: int
    color_primaries: int
    color_transfer: int
    bitrate: int
    lang: str | None


@dataclass(slots=True, frozen=True)
class AudioStream:
    codec: str
    samplerate: int
    layout: str
    channels: int
    duration: float
    bitrate: int
    lang: str | None


@dataclass(slots=True, frozen=True)
class SubtitleStream:
    codec: str
    lang: str | None


@dataclass(slots=True, frozen=True)
class FileInfo:
    path: Path
    bitrate: int
    duration: float
    videos: tuple[VideoStream, ...]
    audios: tuple[AudioStream, ...]
    subtitles: tuple[SubtitleStream, ...]

    @classmethod
    def init(self, path: str, log: Log) -> FileInfo:
        try:
            cont = av.open(path, "r")
        except av.error.FileNotFoundError:
            log.error(f"Input file doesn't exist: {path}")
        except av.error.IsADirectoryError:
            log.error(f"Expected a media file, but got a directory: {path}")
        except av.error.InvalidDataError:
            log.error(f"Invalid data when processing: {path}")

        videos: tuple[VideoStream, ...] = ()
        audios: tuple[AudioStream, ...] = ()
        subtitles: tuple[SubtitleStream, ...] = ()

        for v in cont.streams.video:
            if v.duration is not None and v.time_base is not None:
                vdur = float(v.duration * v.time_base)
            else:
                vdur = 0.0

            fps = v.average_rate
            if (fps is None or fps < 1) and v.name in {"png", "mjpeg", "webp"}:
                fps = Fraction(25)
            if fps is None or fps == 0:
                fps = Fraction(30)

            if v.sample_aspect_ratio is None:
                sar = Fraction(1)
            else:
                sar = v.sample_aspect_ratio

            cc = v.codec_context

            if v.name is None:
                log.error(f"Can't detect codec for video stream {v}")

            videos += (
                VideoStream(
                    v.width,
                    v.height,
                    v.codec.canonical_name,
                    fps,
                    vdur,
                    sar,
                    v.time_base,
                    getattr(v.format, "name", None),
                    cc.color_range,
                    cc.colorspace,
                    cc.color_primaries,
                    cc.color_trc,
                    0 if v.bit_rate is None else v.bit_rate,
                    v.language,
                ),
            )

        for a in cont.streams.audio:
            adur = 0.0
            if a.duration is not None and a.time_base is not None:
                adur = float(a.duration * a.time_base)

            a_cc = a.codec_context
            audios += (
                AudioStream(
                    a_cc.codec.canonical_name,
                    0 if a_cc.sample_rate is None else a_cc.sample_rate,
                    a.layout.name,
                    a_cc.channels,
                    adur,
                    0 if a_cc.bit_rate is None else a_cc.bit_rate,
                    a.language,
                ),
            )

        for s in cont.streams.subtitles:
            codec = s.codec_context.name
            subtitles += (SubtitleStream(codec, s.language),)

        bitrate = 0 if cont.bit_rate is None else cont.bit_rate
        dur = 0 if cont.duration is None else cont.duration / av.time_base

        cont.close()

        return FileInfo(Path(path), bitrate, dur, videos, audios, subtitles)
