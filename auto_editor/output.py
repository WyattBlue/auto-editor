from __future__ import annotations

import os.path
from fractions import Fraction

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.container import Container
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


class Ensure:
    __slots__ = ("_ffmpeg", "_sr", "temp", "log")

    def __init__(self, ffmpeg: FFmpeg, sr: int, temp: str, log: Log) -> None:
        self._ffmpeg = ffmpeg
        self._sr = sr
        self.temp = temp
        self.log = log

    def audio(self, path: str, index: int, stream: int) -> str:
        out_path = os.path.join(self.temp, f"{index}-{stream}.wav")

        if not os.path.isfile(out_path):
            self.log.conwrite("Extracting audio")

            cmd = ["-i", path, "-map", f"0:a:{stream}"]
            cmd += ["-ac", "2", "-ar", f"{self._sr}", "-rf64", "always", out_path]
            self._ffmpeg.run(cmd)

        return out_path


def _ffset(cmd: list[str], option: str, value: str | None) -> list[str]:
    if value is None or value == "unset":
        return cmd
    return cmd + [option] + [value]


def video_quality(
    cmd: list[str], args: Args, inp: FileInfo, ctr: Container
) -> list[str]:
    cmd = _ffset(cmd, "-b:v", args.video_bitrate)
    cmd.extend(["-c:v", args.video_codec])
    cmd = _ffset(cmd, "-qscale:v", args.video_quality_scale)
    cmd.extend(["-movflags", "faststart"])
    return cmd


def mux_quality_media(
    ffmpeg: FFmpeg,
    visual_output: list[tuple[bool, str]],
    audio_output: list[str],
    apply_v: bool,
    ctr: Container,
    output_path: str,
    tb: Fraction,
    args: Args,
    inp: FileInfo,
    temp: str,
    log: Log,
) -> None:

    s_tracks = 0 if not ctr.allow_subtitle else len(inp.subtitles)
    a_tracks = 0 if not ctr.allow_audio else len(audio_output)
    v_tracks = 0 if not ctr.allow_video else len(visual_output)

    cmd = ["-hide_banner", "-y", "-i", inp.path]

    same_container = inp.ext == os.path.splitext(output_path)[1]

    for is_video, path in visual_output:
        if is_video or ctr.allow_image:
            cmd.extend(["-i", path])
        else:
            v_tracks -= 1

    if a_tracks > 0:
        if args.keep_tracks_separate and ctr.max_audios is None:
            for path in audio_output:
                cmd.extend(["-i", path])
        else:
            # Merge all the audio a_tracks into one.
            new_a_file = os.path.join(temp, "new_audio.wav")
            if a_tracks > 1:
                new_cmd = []
                for path in audio_output:
                    new_cmd.extend(["-i", path])
                new_cmd.extend(
                    [
                        "-filter_complex",
                        f"amix=inputs={a_tracks}:duration=longest",
                        "-ac",
                        "2",
                        new_a_file,
                    ]
                )
                ffmpeg.run(new_cmd)
                a_tracks = 1
            else:
                new_a_file = audio_output[0]
            cmd.extend(["-i", new_a_file])

    if s_tracks > 0:
        for s, sub in enumerate(inp.subtitles):
            cmd.extend(["-i", os.path.join(temp, f"new{s}s.{sub.ext}")])

    total_streams = v_tracks + s_tracks + a_tracks

    for i in range(total_streams):
        cmd.extend(["-map", f"{i+1}:0"])

    cmd.extend(["-map_metadata", "0"])

    track = 0
    for is_video, path in visual_output:
        if is_video:
            if apply_v:
                cmd = video_quality(cmd, args, inp, ctr)
            else:
                # Real video is only allowed on track 0
                cmd.extend(["-c:v:0", "copy"])

            if float(tb).is_integer():
                cmd.extend(["-video_track_timescale", f"{tb}"])

        elif ctr.allow_image:
            ext = os.path.splitext(path)[1][1:]
            cmd.extend(
                [f"-c:v:{track}", ext, f"-disposition:v:{track}", "attached_pic"]
            )
        track += 1
    del track

    for i, vstream in enumerate(inp.videos):
        if i > v_tracks:
            break
        if vstream.lang is not None:
            cmd.extend([f"-metadata:s:v:{i}", f"language={vstream.lang}"])
    for i, astream in enumerate(inp.audios):
        if i > a_tracks:
            break
        if astream.lang is not None:
            cmd.extend([f"-metadata:s:a:{i}", f"language={astream.lang}"])
    for i, sstream in enumerate(inp.subtitles):
        if i > s_tracks:
            break
        if sstream.lang is not None:
            cmd.extend([f"-metadata:s:s:{i}", f"language={sstream.lang}"])

    if s_tracks > 0:
        scodec = inp.subtitles[0].codec
        if same_container:
            cmd.extend(["-c:s", scodec])
        elif ctr.scodecs is not None:
            if scodec not in ctr.scodecs:
                scodec = ctr.scodecs[0]
            cmd.extend(["-c:s", scodec])

    if a_tracks > 0:
        cmd = _ffset(cmd, "-c:a", args.audio_codec)
        cmd = _ffset(cmd, "-b:a", args.audio_bitrate)

    if same_container and v_tracks > 0:
        cmd = _ffset(cmd, "-color_range", inp.videos[0].color_range)
        cmd = _ffset(cmd, "-colorspace", inp.videos[0].color_space)
        cmd = _ffset(cmd, "-color_primaries", inp.videos[0].color_primaries)
        cmd = _ffset(cmd, "-color_trc", inp.videos[0].color_transfer)

    if args.extras is not None:
        cmd.extend(args.extras.split(" "))
    cmd.extend(["-strict", "-2"])  # Allow experimental codecs.
    cmd.extend(["-map", "0:t?"])  # Add input attachments to output.

    # This was causing a crash for 'example.mp4 multi-track.mov'
    # cmd.extend(["-map", "0:d?"])

    cmd.append(output_path)
    ffmpeg.run_check_errors(cmd, log, path=output_path)
