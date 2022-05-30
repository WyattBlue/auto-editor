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


# Lookup table: subtitle-codex_name to subtitle-file-extension
sub_exts = {"mov_text": "srt", "ass": "ass", "webvtt": "vtt"}


def regex_match(regex: str, text: str) -> Optional[str]:
    match = re.search(regex, text)
    if match:
        return match.groupdict()["match"]
    return None


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


def to_fdur(dur: Optional[str]) -> float:
    if dur is None:
        return 0
    nums = dur.split(":")
    while len(nums) < 3:
        nums.insert(0, "0")

    hours, minutes, seconds = nums
    try:
        return int(hours) * 3600 + int(minutes) * 60 + float(seconds)
    except ValueError:
        return 0


class FileInfo:
    __slots__ = (
        "path",
        "abspath",
        "basename",
        "dirname",
        "name",
        "ext",
        "duration",
        "fdur",
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
        self.path = path
        self.abspath = os.path.abspath(path)
        self.basename = os.path.basename(path)
        self.dirname = os.path.dirname(os.path.abspath(path))
        self.name, self.ext = os.path.splitext(path)

        info = get_stdout([ffmpeg.path, "-hide_banner", "-i", path])

        self.duration = regex_match(r"Duration:\s(?P<match>[0-9:.]+),", info)
        self.fdur = to_fdur(self.duration)
        self.bitrate = regex_match(r"bitrate:\s(?P<match>[0-9]+\skb\/s)", info)

        self.metadata = {}
        active = False
        active_key = None

        for line in info.split("\n"):
            if active:
                if re.search(r"^\s*[A-Z][a-z_]*", line):
                    break

                key = regex_match(r"^\s*(?P<match>[a-z_]+)", line)
                body = regex_match(r"^\s*[a-z_]*\s*:\s(?P<match>[\w\W]*)", line)

                if body is not None:
                    if key is None:
                        if active_key is not None:
                            self.metadata[active_key] += f"\n{body}"
                    else:
                        self.metadata[key] = body
                        active_key = key

            if re.search(r"^\s\sMetadata:", line):
                active = True

        fps = None
        lang_regex = r"Stream #[0-9]+:[0-9](?:[\[\]a-z0-9]|)+\((?P<match>\w+)\)"

        self.videos = []
        self.audios = []
        self.subtitles = []

        for line in info.split("\n"):
            if re.search(r"Stream #", line):
                if re.search(r"Video:", line):
                    codec = regex_match(r"Video:\s(?P<match>\w+)", line)
                    if codec is None:
                        log.error("Auto-Editor got 'None' when probing video codec")

                    w = regex_match(r"(?P<match>[0-9]+)x[0-9]+[\s,]", line)
                    h = regex_match(r"[0-9]+x(?P<match>[0-9]+)[\s,]", line)
                    _fps = regex_match(r"\s(?P<match>[0-9\.]+)\stbr", line)

                    if w is None or h is None:
                        log.error("Auto-Editor got 'None' when probing resolution")
                    if _fps is None:
                        if codec not in ("png", "mjpeg", "webp"):
                            log.error("Auto-Editor got 'None' when probing fps")
                        _fps = "25"

                    try:
                        fps = float(_fps)
                    except ValueError:
                        log.error(f"Couldn't convert '{_fps}' to float")

                    if fps < 1:
                        log.error(
                            f"{self.basename}: Frame rate cannot be below 1. fps: {fps}"
                        )

                    self.videos.append(
                        VideoStream(
                            int(w),
                            int(h),
                            codec,
                            fps,
                            bitrate=regex_match(r"\s(?P<match>[0-9]+\skb\/s)", line),
                            lang=regex_match(lang_regex, line),
                        )
                    )
                elif re.search(r"Audio:", line):
                    _sr = regex_match(r"(?P<match>[0-9]+)\sHz", line)
                    if _sr is None:
                        log.error("Auto-Editor got 'None' when probing samplerate")

                    codec = regex_match(r"Audio:\s(?P<match>\w+)", line)
                    if codec is None:
                        log.error("Auto-Editor got 'None' when probing audio codec")

                    self.audios.append(
                        AudioStream(
                            codec,
                            int(_sr),
                            bitrate=regex_match(r"\s(?P<match>[0-9]+\skb\/s)", line),
                            lang=regex_match(lang_regex, line),
                        )
                    )
                elif re.search(r"Subtitle:", line):
                    codec = regex_match(r"Subtitle:\s(?P<match>\w+)", line)
                    if codec is None:
                        log.error("Auto-Editor got 'None' when probing subtitle codec")

                    ext = sub_exts.get(codec, "vtt")

                    self.subtitles.append(
                        SubtitleStream(codec, ext, regex_match(lang_regex, line))
                    )


def run_ffprobe(key_options, input_file) -> dict:
    ffprobe_with__default_options = [
        "FFprobe",
        "-hide_banner",
        "-loglevel",
        "quiet",
        "-print_format",
        "json",
    ]

    command_list = ffprobe_with__default_options + key_options + ["-i", input_file]

    p = subprocess.Popen(command_list, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    out, err = p.communicate()

    if err:
        log.warning(f"Command: {command_list}\nIncluded in stderr: {err}")

    if len(out) > 0:
        return json.loads(out)
    else:
        log.error("Auto-Editor could not read the media information.")


class FFprobe:
    __slots__ = (
        "path",
        "abspath",
        "basename",
        "dirname",
        "name",
        "ext",
        "duration",
        "fdur",
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
        self.videos = []
        self.audios = []
        self.subtitles = []

        self.path = path  # The media file location
        self.abspath = os.path.abspath(path)
        self.basename = os.path.basename(path)
        self.dirname = os.path.dirname(os.path.abspath(path))
        self.name, self.ext = os.path.splitext(path)

        # Collect data about the container
        container_keys = "format=duration,bit_rate,nb_streams:format_tags"
        ffprobe_options = ["-show_entries", container_keys]
        media_container_data = run_ffprobe(ffprobe_options, path)

        self.duration = media_container_data["format"]["duration"]
        self.fdur = float(self.duration)
        self.bitrate = media_container_data["format"]["bit_rate"]

        try:
            self.metadata = media_container_data["format"]["tags"]
        except KeyError:
            self.metadata = None

        # Collect data about each stream
        stream_keys_all_codecs = "stream=avg_frame_rate,bit_rate,codec_name,codec_type,height,index,sample_rate,width:stream_tags=language"

        streams_in_container = media_container_data["format"]["nb_streams"]
        stream_index = 0
        while stream_index < streams_in_container:
            ffprobe_options = [
                "-select_streams",
                str(stream_index),
                "-show_entries",
                stream_keys_all_codecs,
            ]
            stream_data = run_ffprobe(ffprobe_options, path)

            # [0] is the list index, not stream_index. It is always [0].
            stream_type = stream_data["streams"][0]["codec_type"]
            # Can collect: audio, subtitle, video. Cannot collect: attachments, data.
            if stream_type == "audio":
                samplerate = stream_data["streams"][0]["sample_rate"]
                int(samplerate)

                codec = stream_data["streams"][0]["codec_name"]

                try:
                    bitrate = stream_data["streams"][0]["bit_rate"]
                except KeyError:
                    bitrate = None
                if bitrate == "N/A":
                    bitrate = None

                try:
                    lang = stream_data["streams"][0]["tags"]["language"]
                except KeyError:
                    lang = None
                if lang == "und":
                    lang = None

                self.audios.append(AudioStream(codec, samplerate, bitrate, lang))
            elif stream_type == "subtitle":
                codec = stream_data["streams"][0]["codec_name"]

                ext = sub_exts.get(codec, "vtt")

                try:
                    lang = stream_data["streams"][0]["tags"]["language"]
                except KeyError:
                    lang = None
                if lang == "und":
                    lang = None

                self.subtitles.append(SubtitleStream(codec, ext, lang))
            elif stream_type == "video":
                codec = stream_data["streams"][0]["codec_name"]
                w = stream_data["streams"][0]["width"]
                h = stream_data["streams"][0]["height"]

                # fps = None
                try:
                    _fps = stream_data["streams"][0]["avg_frame_rate"]
                except KeyError:
                    _fps = None
                if _fps == "0/0":
                    _fps = None
                if _fps is not None:
                    _fps = Fraction(_fps)
                    _fps = float(_fps)
                if _fps is None:
                    if codec not in ("png", "mjpeg", "webp"):
                        log.error("Auto-Editor got 'None' when probing fps")
                    else:
                        fps = 25.00
                else:
                    fps = round(_fps, 2)
                if fps < 1:
                    log.error(
                        f"{self.basename}: Frame rate cannot be below 1. fps: {fps}"
                    )

                try:
                    bitrate = stream_data["streams"][0]["bit_rate"]
                except KeyError:
                    bitrate = None
                if bitrate == "N/A":
                    bitrate = None

                try:
                    lang = stream_data["streams"][0]["tags"]["language"]
                except KeyError:
                    lang = None
                if lang == "und":
                    lang = None

                self.videos.append(VideoStream(w, h, codec, fps, bitrate, lang))
            else:
                log.warning(f"Unknown codec_type in stream #{stream_index}.")

            stream_index += 1  # End of while loop
