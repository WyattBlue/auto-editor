from __future__ import annotations

import os.path
import subprocess
import sys
from dataclasses import dataclass
from fractions import Fraction
from pathlib import Path
from re import search
from shutil import which
from subprocess import PIPE, Popen
from typing import Any

import av

from auto_editor.utils.func import get_stdout
from auto_editor.utils.log import Log


class FFmpeg:
    __slots__ = ("debug", "show_cmd", "path", "version")

    def __init__(
        self,
        ff_location: str | None = None,
        my_ffmpeg: bool = False,
        show_cmd: bool = False,
        debug: bool = False,
    ):
        def _set_ff_path(ff_location: str | None, my_ffmpeg: bool) -> str:
            if ff_location is not None:
                return ff_location
            if my_ffmpeg:
                return "ffmpeg"

            try:
                import ae_ffmpeg

                return ae_ffmpeg.get_path()
            except ImportError:
                return "ffmpeg"

        self.debug = debug
        self.show_cmd = show_cmd
        _path: str | None = _set_ff_path(ff_location, my_ffmpeg)

        if _path == "ffmpeg":
            _path = which("ffmpeg")

        if _path is None:
            Log().error("Did not find ffmpeg on PATH.")
        self.path = _path

        try:
            _version = get_stdout([self.path, "-version"]).split("\n")[0]
            self.version = _version.replace("ffmpeg version", "").strip().split(" ")[0]
        except FileNotFoundError:
            Log().error("ffmpeg must be installed and on PATH.")

    def print(self, message: str) -> None:
        if self.debug:
            sys.stderr.write(f"FFmpeg: {message}\n")

    def print_cmd(self, cmd: list[str]) -> None:
        if self.show_cmd:
            sys.stderr.write(f"{' '.join(cmd)}\n\n")

    def run(self, cmd: list[str]) -> None:
        cmd = [self.path, "-hide_banner", "-y"] + cmd
        if not self.debug:
            cmd.extend(["-nostats", "-loglevel", "error"])
        self.print_cmd(cmd)
        subprocess.run(cmd)

    def run_check_errors(
        self,
        cmd: list[str],
        log: Log,
        show_out: bool = False,
        path: str | None = None,
    ) -> None:
        process = self.Popen(cmd, stdin=PIPE, stdout=PIPE, stderr=PIPE)
        _, stderr = process.communicate()

        if process.stdin is not None:
            process.stdin.close()
        output = stderr.decode("utf-8", "replace")

        error_list = (
            r"Unknown encoder '.*'",
            r"-q:v qscale not available for encoder\. Use -b:v bitrate instead\.",
            r"Specified sample rate .* is not supported",
            r'Unable to parse option value ".*"',
            r"Error setting option .* to value .*\.",
            r"Undefined constant or missing '.*' in '.*'",
            r"DLL .* failed to open",
            r"Incompatible pixel format '.*' for codec '[A-Za-z0-9_]*'",
            r"Unrecognized option '.*'",
            r"Permission denied",
        )

        if self.debug:
            print(f"stderr: {output}")

        for item in error_list:
            if check := search(item, output):
                log.error(check.group())

        if path is not None and not os.path.isfile(path):
            log.error(f"The file {path} was not created.")
        elif show_out and not self.debug:
            print(f"stderr: {output}")

    def Popen(
        self, cmd: list[str], stdin: Any = None, stdout: Any = PIPE, stderr: Any = None
    ) -> Popen:
        cmd = [self.path] + cmd
        self.print_cmd(cmd)
        return Popen(cmd, stdin=stdin, stdout=stdout, stderr=stderr)

    def pipe(self, cmd: list[str]) -> str:
        cmd = [self.path, "-y"] + cmd

        self.print_cmd(cmd)
        output = get_stdout(cmd)
        self.print(output)
        return output


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
    description: str | None
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

    def __repr__(self) -> str:
        return f"@{self.path.name}"


def initFileInfo(path: str, log: Log) -> FileInfo:
    try:
        cont = av.open(path, "r")
    except av.error.FileNotFoundError:
        log.error(f"Could not find '{path}'")
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
        if (fps is None or fps < 1) and v.name in ("png", "mjpeg", "webp"):
            fps = Fraction(25)
        if fps is None or fps == 0:
            fps = Fraction(30)

        sar = Fraction(1) if v.sample_aspect_ratio is None else v.sample_aspect_ratio
        cc = v.codec_context

        if v.name is None:
            log.error(f"Can't detect codec for video stream {v}")

        videos += (
            VideoStream(
                v.width,
                v.height,
                v.name,
                fps,
                vdur,
                sar,
                v.time_base,
                cc.pix_fmt,
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
                a_cc.name,
                0 if a_cc.sample_rate is None else a_cc.sample_rate,
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

    desc = cont.metadata.get("description", None)
    bitrate = 0 if cont.bit_rate is None else cont.bit_rate
    dur = 0 if cont.duration is None else cont.duration / 1_000_000

    cont.close()

    return FileInfo(Path(path), bitrate, dur, desc, videos, audios, subtitles)
