from __future__ import annotations

import os.path
from dataclasses import dataclass, field
from fractions import Fraction
from re import search
from subprocess import PIPE

import av
from av.audio.resampler import AudioResampler

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.bar import Bar
from auto_editor.utils.container import Container
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


@dataclass(slots=True)
class Ensure:
    _bar: Bar
    _sr: int
    log: Log
    _audios: list[tuple[FileInfo, int]] = field(default_factory=list)

    def audio(self, src: FileInfo, stream: int) -> str:
        try:
            label = self._audios.index((src, stream))
            first_time = False
        except ValueError:
            self._audios.append((src, stream))
            label = len(self._audios) - 1
            first_time = True

        out_path = os.path.join(self.log.temp, f"{label:x}.wav")

        if first_time:
            sample_rate = self._sr
            bar = self._bar
            self.log.debug(f"Making external audio: {out_path}")

            in_container = av.open(src.path, "r")
            out_container = av.open(
                out_path, "w", format="wav", options={"rf64": "always"}
            )
            astream = in_container.streams.audio[stream]

            if astream.duration is None or astream.time_base is None:
                dur = 1.0
            else:
                dur = float(astream.duration * astream.time_base)

            bar.start(dur, "Extracting audio")

            # PyAV always uses "stereo" layout, which is what we want.
            output_astream = out_container.add_stream("pcm_s16le", rate=sample_rate)
            assert isinstance(output_astream, av.audio.stream.AudioStream)

            resampler = AudioResampler(format="s16", layout="stereo", rate=sample_rate)
            for i, frame in enumerate(in_container.decode(astream)):
                if i % 1500 == 0 and frame.time is not None:
                    bar.tick(frame.time)

                for new_frame in resampler.resample(frame):
                    for packet in output_astream.encode(new_frame):
                        out_container.mux_one(packet)

            for packet in output_astream.encode():
                out_container.mux_one(packet)

            out_container.close()
            in_container.close()
            bar.end()

        return out_path


def _ffset(option: str, value: str | None) -> list[str]:
    if value is None or value == "unset" or value == "reserved":
        return []
    return [option] + [value]


def mux_quality_media(
    ffmpeg: FFmpeg,
    visual_output: list[tuple[bool, str]],
    audio_output: list[str],
    sub_output: list[str],
    ctr: Container,
    output_path: str,
    tb: Fraction,
    args: Args,
    src: FileInfo,
    log: Log,
) -> None:
    v_tracks = len(visual_output)
    a_tracks = len(audio_output)
    s_tracks = 0 if args.sn else len(sub_output)

    cmd = ["-hide_banner", "-y"]

    same_container = src.path.suffix == os.path.splitext(output_path)[1]

    for is_video, path in visual_output:
        if is_video or ctr.allow_image:
            cmd.extend(["-i", path])
        else:
            v_tracks -= 1

    for audfile in audio_output:
        cmd.extend(["-i", audfile])

    for subfile in sub_output:
        cmd.extend(["-i", subfile])

    for i in range(v_tracks + s_tracks + a_tracks):
        cmd.extend(["-map", f"{i}:0"])

    cmd.extend(["-map_metadata", "0"])

    track = 0
    for is_video, path in visual_output:
        if is_video:
            cmd += [f"-c:v:{track}", "copy"]
        elif ctr.allow_image:
            ext = os.path.splitext(path)[1][1:]
            cmd += [f"-c:v:{track}", ext, f"-disposition:v:{track}", "attached_pic"]

        track += 1
    del track

    for i, vstream in enumerate(src.videos):
        if i > v_tracks:
            break
        if vstream.lang is not None:
            cmd.extend([f"-metadata:s:v:{i}", f"language={vstream.lang}"])
    for i, astream in enumerate(src.audios):
        if i > a_tracks:
            break
        if astream.lang is not None:
            cmd.extend([f"-metadata:s:a:{i}", f"language={astream.lang}"])
    for i, sstream in enumerate(src.subtitles):
        if i > s_tracks:
            break
        if sstream.lang is not None:
            cmd.extend([f"-metadata:s:s:{i}", f"language={sstream.lang}"])

    if s_tracks > 0:
        scodec = src.subtitles[0].codec
        if same_container:
            cmd.extend(["-c:s", scodec])
        elif ctr.scodecs is not None:
            if scodec not in ctr.scodecs:
                scodec = ctr.default_sub
            cmd.extend(["-c:s", scodec])

    if a_tracks > 0:
        cmd += _ffset("-c:a", args.audio_codec) + _ffset("-b:a", args.audio_bitrate)

    if same_container and v_tracks > 0:
        color_range = src.videos[0].color_range
        colorspace = src.videos[0].color_space
        color_prim = src.videos[0].color_primaries
        color_trc = src.videos[0].color_transfer

        if color_range == 1 or color_range == 2:
            cmd.extend(["-color_range", f"{color_range}"])
        if colorspace in (0, 1) or (colorspace >= 3 and colorspace < 16):
            cmd.extend(["-colorspace", f"{colorspace}"])
        if color_prim == 1 or (color_prim >= 4 and color_prim < 17):
            cmd.extend(["-color_primaries", f"{color_prim}"])
        if color_trc == 1 or (color_trc >= 4 and color_trc < 22):
            cmd.extend(["-color_trc", f"{color_trc}"])

    cmd.extend(["-strict", "-2"])  # Allow experimental codecs.

    if s_tracks > 0:
        cmd.extend(["-map", "0:t?"])  # Add input attachments to output.

    if not args.dn:
        cmd.extend(["-map", "0:d?"])

    cmd.append(output_path)

    process = ffmpeg.Popen(cmd, stdout=PIPE, stderr=PIPE)
    stderr = process.communicate()[1].decode("utf-8", "replace")
    error_list = (
        r"Unknown encoder '.*'",
        r"-q:v qscale not available for encoder\. Use -b:v bitrate instead\.",
        r"Specified sample rate .* is not supported",
        r'Unable to parse option value ".*"',
        r"Error setting option .* to value .*\.",
        r"DLL .* failed to open",
        r"Incompatible pixel format '.*' for codec '[A-Za-z0-9_]*'",
        r"Unrecognized option '.*'",
        r"Permission denied",
    )
    for item in error_list:
        if check := search(item, stderr):
            log.error(check.group())

    if not os.path.isfile(output_path):
        log.error(f"The file {output_path} was not created.")
