# Internal Libraries
import os.path
import re
import subprocess
import sys
from dataclasses import dataclass
from decimal import *
from fractions import Fraction
from platform import system
from subprocess import Popen, PIPE

# Typing
from typing import List, Tuple, Optional

# Included Libraries
from auto_editor.utils.func import get_stdout
from auto_editor.utils.log import Log


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


# Converts a sexagesimal duration stored in a string to seconds stored in a float 
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


# This is where FFprobe goes 
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

# The following code is halfway to getting the values from FFprobe
# The variable 'path' seems to be the path/file.ext of the input file
    # command_line = ['FFprobe -hide_banner -loglevel quiet -print_format flat=sep_char=_ -show_entries stream=avg_frame_rate,bit_rate,codec_name,codec_type,height,index,sample_rate,width:stream_tags=language:format=duration -i', path]
     
    # FFprobe_return = subprocess.Popen(command_line, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    # out, err =  FFprobe_return.communicate()

# doSomething.intelligent(out)
# doSomething.intelligent(err)
# ??????
# profit()

# Pretend I extracted the data from 'out' and loaded these variables with these values
    streams_stream_0_index=0
    streams_stream_0_codec_name="h264"
    streams_stream_0_codec_type="video"
    streams_stream_0_width=1080
    streams_stream_0_height=1920
    streams_stream_0_avg_frame_rate="30000/1001"
    streams_stream_0_bit_rate="1757923"
# N.B. format_bit_rate is b/s not kb/s
    streams_stream_0_tags_language="eng"
    streams_stream_1_index=1
    streams_stream_1_codec_name="aac"
    streams_stream_1_codec_type="audio"
    streams_stream_1_sample_rate="48000"
    streams_stream_1_avg_frame_rate="0/0"
    streams_stream_1_bit_rate="381375"
# N.B. format_bit_rate is b/s not kb/s
    streams_stream_1_tags_language="und"
    format_duration="100.587000"
    
# After assigning the variables with the assignments above, I need to 
# convert the variable-type of some variables, therefore:
# Is there a more elegant way to do the following on streams_stream_0_avg_frame_rate?
    streams_stream_0_avg_frame_rate=Fraction(streams_stream_0_avg_frame_rate)
    streams_stream_0_avg_frame_rate_float=float(streams_stream_0_avg_frame_rate)
    streams_stream_0_avg_frame_rate_rounded=round(streams_stream_0_avg_frame_rate_float, 2)
    format_duration=float(format_duration)

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

        self.duration = format_duration
        # self.fdur = to_fdur(self.duration)
        self.bitrate = format_bit_rate

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
        sub_exts = {"mov_text": "srt", "ass": "ass", "webvtt": "vtt"}

        self.videos = []
        self.audios = []
        self.subtitles = []

        for line in info.split("\n"):
            if re.search(r"Stream #", line):
                if re.search(r"Video:", line):
                    codec = streams_stream_0_codec_name
                    if codec is None:
                        log.error("Auto-Editor got 'None' when probing video codec")

                    w = streams_stream_0_width
                    h = streams_stream_0_height
                    _fps = streams_stream_0_avg_frame_rate_rounded

                    if w is None or h is None:
                        log.error("Auto-Editor got 'None' when probing resolution")
                    if _fps is None:
                        if codec not in ("png", "mjpeg", "webp"):
                            log.error("Auto-Editor got 'None' when probing fps")
                        _fps = "25"

                    try:
                        fps = float(_fps)
                    except ValueError:
                        log.error(f"Couldn't convert '{fps}' to float")

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
                            # the 
                            bitrate=streams_stream_0_bit_rate + 'b/s'
                            lang=streams_stream_0_tags_language,
                        )
                    )
                elif re.search(r"Audio:", line):
                    _sr = streams_stream_1_sample_rate
                    if _sr is None:
                        log.error("Auto-Editor got 'None' when probing samplerate")

                    codec = streams_stream_1_codec_name
                    if codec is None:
                        log.error("Auto-Editor got 'None' when probing audio codec")

                    self.audios.append(
                        AudioStream(
                            codec,
                            int(_sr),
                            bitrate=streams_stream_1_bit_rate + 'b/s',
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
