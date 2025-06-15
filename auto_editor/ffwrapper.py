from __future__ import annotations

from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path

import bv

from auto_editor.utils.log import Log


def mux(input: Path, output: Path, stream: int) -> None:
    input_container = bv.open(input, "r")
    output_container = bv.open(output, "w")

    input_audio_stream = input_container.streams.audio[stream]
    output_audio_stream = output_container.add_stream("pcm_s16le")

    for frame in input_container.decode(input_audio_stream):
        output_container.mux(output_audio_stream.encode(frame))

    output_container.mux(output_audio_stream.encode(None))

    output_container.close()
    input_container.close()


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
    ext: str
    lang: str | None


@dataclass(slots=True, frozen=True)
class FileInfo:
    path: Path
    bitrate: int
    duration: float
    timecode: str  # in SMPTE
    videos: tuple[VideoStream, ...]
    audios: tuple[AudioStream, ...]
    subtitles: tuple[SubtitleStream, ...]

    def get_res(self) -> tuple[int, int]:
        if self.videos:
            return self.videos[0].width, self.videos[0].height
        return 1920, 1080

    def get_fps(self) -> Fraction:
        if self.videos:
            return self.videos[0].fps
        return Fraction(30)

    def get_sr(self) -> int:
        if self.audios:
            return self.audios[0].samplerate
        return 48000

    @classmethod
    def init(self, path: str, log: Log) -> FileInfo:
        try:
            cont = bv.open(path, "r")
        except bv.error.FileNotFoundError:
            log.error(f"Input file doesn't exist: {path}")
        except bv.error.IsADirectoryError:
            log.error(f"Expected a media file, but got a directory: {path}")
        except bv.error.InvalidDataError:
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
            sub_exts = {"mov_text": "srt", "ass": "ass", "webvtt": "vtt"}
            ext = sub_exts.get(codec, "vtt")
            subtitles += (SubtitleStream(codec, ext, s.language),)

        def get_timecode() -> str:
            for d in cont.streams.data:
                if (result := d.metadata.get("timecode")) is not None:
                    return result
            for v in cont.streams.video:
                if (result := v.metadata.get("timecode")) is not None:
                    return result
            return "00:00:00:00"

        timecode = get_timecode()
        bitrate = 0 if cont.bit_rate is None else cont.bit_rate
        dur = 0 if cont.duration is None else cont.duration / bv.time_base

        cont.close()

        return FileInfo(Path(path), bitrate, dur, timecode, videos, audios, subtitles)

    def __repr__(self) -> str:
        return f"@{self.path.name}"
