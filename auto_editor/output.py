# Internal Libraries
import os.path

# Typing
from typing import List, Tuple, Optional

# Included Libraries
from auto_editor.utils.log import Log
from auto_editor.utils.func import fnone
from auto_editor.utils.container import Container
from auto_editor.ffwrapper import FFmpeg, FileInfo


def fset(cmd: List[str], option: str, value: str) -> List[str]:
    if fnone(value):
        return cmd
    return cmd + [option] + [value]


def get_vcodec(args, inp: FileInfo, rules: Container) -> str:
    vcodec = args.video_codec
    if vcodec == "auto":
        vcodec = inp.videos[0].codec

        if rules.vcodecs is not None:
            if rules.vstrict and vcodec not in rules.vcodecs:
                return rules.vcodecs[0]

            if vcodec in rules.disallow_v:
                return rules.vcodecs[0]

    if vcodec == "copy":
        return inp.videos[0].codec

    if vcodec == "uncompressed":
        return "mpeg4"
    return vcodec


def get_acodec(args, inp: FileInfo, rules: Container) -> str:
    acodec = args.audio_codec
    if acodec == "auto":
        acodec = inp.audios[0].codec

        if rules.acodecs is not None:  # Just in case, but shouldn't happen
            if rules.astrict and acodec not in rules.acodecs:
                # Input codec can't be used for output, so use a new safe codec.
                return rules.acodecs[0]

            if acodec in rules.disallow_a:
                return rules.acodecs[0]

    if acodec == "copy":
        return inp.audios[0].codec
    return acodec


def video_quality(cmd: List[str], args, inp: FileInfo, rules: Container) -> List[str]:
    cmd = fset(cmd, "-b:v", args.video_bitrate)

    qscale = args.video_quality_scale

    if args.video_codec == "uncompressed" and fnone(qscale):
        qscale = "1"

    vcodec = get_vcodec(args, inp, rules)

    cmd.extend(["-c:v", vcodec])

    cmd = fset(cmd, "-qscale:v", qscale)

    cmd.extend(["-movflags", "faststart"])
    return cmd


def mux_quality_media(
    ffmpeg: FFmpeg,
    video_output: List[Tuple[int, bool, str, bool]],
    rules: Container,
    write_file: str,
    container: str,
    args,
    inp: FileInfo,
    temp: str,
    log: Log,
) -> None:
    s_tracks = 0 if not rules.allow_subtitle else len(inp.subtitles)
    a_tracks = 0 if not rules.allow_audio else len(inp.audios)
    v_tracks = 0 if not rules.allow_video else len(video_output)

    cmd = ["-hide_banner", "-y", "-i", inp.path]

    # fmt: off
    for _, is_video, path, _, in video_output:
        if is_video or rules.allow_image:
            cmd.extend(["-i", path])
        else:
            v_tracks -= 1
    # fmt: on

    if a_tracks > 0:
        if args.keep_tracks_seperate and rules.max_audios is None:
            for t in range(a_tracks):
                cmd.extend(["-i", os.path.join(temp, f"new{t}.wav")])
        else:
            # Merge all the audio a_tracks into one.
            new_a_file = os.path.join(temp, "new_audio.wav")
            if a_tracks > 1:
                new_cmd = []
                for t in range(a_tracks):
                    new_cmd.extend(["-i", os.path.join(temp, f"new{t}.wav")])
                new_cmd.extend(
                    [
                        "-filter_complex",
                        f"amerge=inputs={a_tracks}",
                        "-ac",
                        "2",
                        new_a_file,
                    ]
                )
                ffmpeg.run(new_cmd)
                a_tracks = 1
            else:
                new_a_file = os.path.join(temp, "new0.wav")
            cmd.extend(["-i", new_a_file])

    if s_tracks > 0:
        for s, sub in enumerate(inp.subtitles):
            cmd.extend(["-i", os.path.join(temp, f"new{s}s.{sub.ext}")])

    total_streams = v_tracks + s_tracks + a_tracks

    for i in range(total_streams):
        cmd.extend(["-map", f"{i+1}:0"])

    cmd.extend(["-map_metadata", "0"])

    for track, is_video, path, apply_video in video_output:
        if is_video:
            if apply_video:
                cmd = video_quality(cmd, args, inp, rules)
            else:
                cmd.extend([f"-c:v:{track}", "copy"])
        elif rules.allow_image:
            ext = os.path.splitext(path)[1][1:]
            cmd.extend(
                [f"-c:v:{track}", ext, f"-disposition:v:{track}", "attached_pic"]
            )

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
        if inp.ext == f".{container}":
            cmd.extend(["-c:s", scodec])
        elif rules.scodecs is not None:
            if scodec not in rules.scodecs:
                scodec = rules.scodecs[0]
            cmd.extend(["-c:s", scodec])

    if a_tracks > 0:
        acodec = get_acodec(args, inp, rules)

        cmd = fset(cmd, "-c:a", acodec)
        cmd = fset(cmd, "-b:a", args.audio_bitrate)

        if fnone(args.sample_rate):
            if rules.samplerate is not None:
                cmd.extend(["-ar", str(rules.samplerate[0])])
        else:
            cmd.extend(["-ar", str(args.sample_rate)])

    if args.extras is not None:
        cmd.extend(args.extras.split(" "))
    cmd.extend(["-strict", "-2"])  # Allow experimental codecs.
    cmd.extend(
        ["-map", "0:t?", "-map", "0:d?"]
    )  # Add input attachments and data to output.
    cmd.append(write_file)
    ffmpeg.run_check_errors(cmd, log, path=write_file)
