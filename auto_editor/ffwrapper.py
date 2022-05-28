# Internal Libraries
import json
import os.path
import re
import subprocess
import sys
from dataclasses import dataclass
from fractions import Fraction
from platform import system
from subprocess import Popen, PIPE

# Typing
from typing import List, Tuple, Optional

# Included Libraries
from auto_editor.utils.func import get_stdout
from auto_editor.utils.log import Log


class FFmpeg:
    __slots__ = ("debug", "path", "version")

    @staticmethod
    def _set_ff_path(ff_location: Optional[str], my_ffmpeg: bool) -> str:
        if ff_location is not None:
            return ff_location
        if my_ffmpeg or system() not in ("Windows", "Darwin"):
            return "ffmpeg"
        program = "ffmpeg" if system() == "Darwin" else "ffmpeg.exe"
        dirpath = os.path.dirname(os.path.realpath(__file__))
        return os.path.join(dirpath, "ffmpeg", system(), program)

    def __init__(
        self,
        ff_location: Optional[str] = None,
        my_ffmpeg: bool = False,
        debug: bool = False,
    ) -> None:

        self.debug = debug
        self.path = self._set_ff_path(ff_location, my_ffmpeg)
        try:
            _version = get_stdout([self.path, "-version"]).split("\n")[0]
            _version = _version.replace("ffmpeg version", "").strip()
            self.version = _version.split(" ")[0]
        except FileNotFoundError:
            if system() == "Darwin":
                Log().error(
                    "No ffmpeg found, download via homebrew or restore the "
                    "included binary."
                )
            if system() == "Windows":
                Log().error(
                    "No ffmpeg found, download ffmpeg with your favorite package "
                    "manager (ex chocolatey), or restore the included binary."
                )

            Log().error("ffmpeg must be installed and on PATH.")

    def print(self, message: str) -> None:
        if self.debug:
            print(f"FFmpeg: {message}", file=sys.stderr)

    def print_cmd(self, cmd: List[str]) -> None:
        if self.debug:
            print(f"FFmpeg run: {' '.join(cmd)}\n", file=sys.stderr)

    def run(self, cmd: List[str]) -> None:
        cmd = [self.path, "-y", "-hide_banner"] + cmd
        if not self.debug:
            cmd.extend(["-nostats", "-loglevel", "error"])
        self.print_cmd(cmd)
        subprocess.run(cmd)

    def run_check_errors(
        self,
        cmd: List[str],
        log: Log,
        show_out: bool = False,
        path: Optional[str] = None,
    ) -> None:
        def _run(cmd: List[str]) -> str:
            process = self.Popen(cmd, stdin=PIPE, stdout=PIPE, stderr=PIPE)

            _, stderr = process.communicate()

            if process.stdin is not None:
                process.stdin.close()
            return stderr.decode("utf-8", "replace")

        output = _run(cmd)

        if "Try -allow_sw 1" in output:
            cmd.insert(-1, "-allow_sw")
            cmd.insert(-1, "1")
            output = _run(cmd)

        error_list = [
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
        ]

        if self.debug:
            print(f"stderr: {output}")

        for item in error_list:
            check = re.search(item, output)
            if check:
                log.error(check.group())

        if path is not None and not os.path.isfile(path):
            log.error(f"The file {path} was not created.")
        elif show_out and not self.debug:
            print(f"stderr: {output}")

    def Popen(self, cmd: List[str], stdin=None, stdout=PIPE, stderr=None) -> Popen:
        cmd = [self.path] + cmd
        self.print_cmd(cmd)
        return Popen(cmd, stdin=stdin, stdout=stdout, stderr=stderr)

    def pipe(self, cmd: List[str]) -> str:
        cmd = [self.path, "-y"] + cmd

        self.print_cmd(cmd)
        output = get_stdout(cmd)
        self.print(output)
        return output


@dataclass
class VideoStream:
    width: int
    height: int
    codec: str
    fps: float
    bitrate: Optional[str]
    lang: Optional[str]


@dataclass
class AudioStream:
    codec: str
    samplerate: int
    bitrate: Optional[str]
    lang: Optional[str]


@dataclass
class SubtitleStream:
    codec: str
    ext: str
    lang: Optional[str]


class FileInfo:
    __slots__ = (
        "path",
        "abspath",
        "basename",
        "dirname",
        "name",
        "ext",
        "duration",
        "duration_float",
        "bitrate",
        "metadata",
        "videos",
        "audios",
        "subtitles",
    )

    def get_res(self) -> Tuple[int, int]:
        if len(self.videos) > 0:
            return self.videos[0].width, self.videos[0].height
        return 1920, 1080

    def get_fps(self) -> float:
        fps = None
        if len(self.videos) > 0:
            fps = self.videos[0].fps

        return 30 if fps is None else fps

    def get_samplerate(self) -> int:
        if len(self.audios) > 0:
            return self.audios[0].samplerate
        return 48000

    def __init__(self, path: str, ffmpeg: FFmpeg, log: Log):
        self.path = path  # The media file location
        self.abspath = os.path.abspath(path)
        self.basename = os.path.basename(path)
        self.dirname = os.path.dirname(os.path.abspath(path))
        self.name, self.ext = os.path.splitext(path)

        # What does the container look like?
        command_with_options = [
            "FFprobe",
            "-hide_banner",
            "-loglevel",
            "quiet",
            "-print_format",
            "json",
            "-show_entries",
            "format=duration,bit_rate,nb_streams:format_tags",
            "-i",
            path,
        ]
        _raw = subprocess.Popen(
            command_with_options, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        out, err = _raw.communicate()
        if err:
            log.warning(
                "The command, "
                + command_with_options
                + ", included an error from stderr: "
                + err
            )

        if len(out) > 0:
            media_format_data = json.loads(out)
        else:
            log.error("Auto-Editor could not read the media information.")

        self.duration = media_format_data["format"]["duration"]
        self.duration_float = float(self.duration)
        self.bitrate = media_format_data["format"]["bit_rate"]

        # Simple dictionary of the container's Metadata
        self.metadata = media_format_data["format"]["tags"]
        # Lookup table: subtitle-codex_name to subtitle-file-extension
        sub_exts = {
            "mov_text": "srt",
            "ass": "ass",
            "webvtt": "vtt",
        }

        streams_in_container = media_format_data["format"]["nb_streams"]
        self.videos = []  # initialize
        self.audios = []  # initialize
        self.subtitles = []  # initialize
        stream_keys_all_codecs = "stream=avg_frame_rate,bit_rate,codec_name,codec_type,height,index,sample_rate,width:stream_tags=language"

        stream_index = 0  # initialize
        while stream_index < streams_in_container:
            fps = None  # initialize

            command_with_options = [
                "FFprobe",
                "-hide_banner",
                "-loglevel",
                "quiet",
                "-print_format",
                "json",
                "-select_streams",
                str(stream_index),
                "-show_entries",
                stream_keys_all_codecs,
                "-i",
                path,
            ]
            _raw = subprocess.Popen(
                command_with_options, stdout=subprocess.PIPE, stderr=subprocess.PIPE
            )
            out, err = _raw.communicate()
            if err:
                log.warning(
                    "The command, "
                    + command_with_options
                    + ", included an error from stderr: "
                    + err
                )

            if len(out) > 0:
                stream_data = json.loads(out)
            else:
                log.error(
                    "Auto-Editor could not read the information about stream #"
                    + stream_index
                )

            # What type of stream is this?
            # Stream types not accounted for here: attachments, data
            # The data is always in list index [0]. This value is not the stream_index: the location/syntax is a confusing coincidence.
            stream_type = stream_data["streams"][0]["codec_type"]
            # In this elif chain, the values for stream_type are in alphabetical order. To wit: audio, subtitle, video
            if stream_type == "audio":
                _sr = stream_data["streams"][0]["sample_rate"]
                if _sr is None:
                    log.error("Auto-Editor got 'None' when probing samplerate")

                codec = stream_data["streams"][0]["codec_name"]
                if codec is None:
                    log.error("Auto-Editor got 'None' when probing audio codec")

                self.audios.append(
                    AudioStream(
                        codec,
                        int(_sr),
                        bitrate=stream_data["streams"][0]["bit_rate"],
                        lang=stream_data["streams"][0]["tags"]["language"],
                    )
                )
            elif stream_type == "subtitle":
                codec = stream_data["streams"][0]["codec_name"]
                if codec is None:
                    log.error("Auto-Editor got 'None' when probing subtitle codec")

                ext = sub_exts.get(codec, "vtt")

                self.subtitles.append(
                    SubtitleStream(
                        codec, ext, lang=stream_data["streams"][0]["tags"]["language"]
                    )
                )
            elif stream_type == "video":
                codec = stream_data["streams"][0]["codec_name"]
                if codec is None:
                    log.error("Auto-Editor got 'None' when probing video codec")

                w = stream_data["streams"][0]["width"]
                h = stream_data["streams"][0]["height"]
                if w is None or h is None:
                    log.error("Auto-Editor got 'None' when probing resolution")

                _fps = stream_data["streams"][0]["avg_frame_rate"]
                if _fps is None:
                    if codec not in ("png", "mjpeg", "webp"):
                        log.error("Auto-Editor got 'None' when probing fps")
                    _fps = "25"
                try:
                    _fps = Fraction(_fps)
                except ValueError:
                    log.error(f"Couldn't convert '{_fps}' to Fraction")
                _fps = float(_fps)
                fps = round(_fps, 2)
                if fps < 1:
                    log.error(
                        f"{self.basename}: Frame rate cannot be below 1. fps: {fps}"
                    )

                self.videos.append(
                    VideoStream(
                        w,
                        h,
                        codec,
                        fps,
                        bitrate=stream_data["streams"][0]["bit_rate"],
                        lang=stream_data["streams"][0]["tags"]["language"],
                    )
                )
            else:
                log.warning("Unknown codec_type in stream #" + stream_index)

            stream_index += 1  # End of while loop
