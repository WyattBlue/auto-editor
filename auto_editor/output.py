import os.path
from typing import List, Optional, Tuple

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.utils.container import Container
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


def fset(cmd: List[str], option: str, value: Optional[str]) -> List[str]:
    if value is None or value == "unset":
        return cmd
    return cmd + [option] + [value]


def get_vcodec(vcodec: str, inp: FileInfo, ctr: Container) -> str:
    if vcodec == "auto":
        vcodec = inp.videos[0].codec

        if ctr.vcodecs is not None:
            if ctr.vstrict and vcodec not in ctr.vcodecs:
                return ctr.vcodecs[0]

            if vcodec in ctr.disallow_v:
                return ctr.vcodecs[0]

    if vcodec == "copy":
        return inp.videos[0].codec

    if vcodec == "uncompressed":
        return "mpeg4"
    return vcodec


def get_acodec(acodec: str, inp: FileInfo, ctr: Container) -> str:
    if acodec == "auto":
        acodec = inp.audios[0].codec

        if ctr.acodecs is not None:  # Just in case, but shouldn't happen
            if ctr.astrict and acodec not in ctr.acodecs:
                # Input codec can't be used for output, so use a new safe codec.
                return ctr.acodecs[0]

            if acodec in ctr.disallow_a:
                return ctr.acodecs[0]

    if acodec == "copy":
        return inp.audios[0].codec
    return acodec


def video_quality(
    cmd: List[str], args: Args, inp: FileInfo, ctr: Container
) -> List[str]:
    cmd = fset(cmd, "-b:v", args.video_bitrate)

    qscale = args.video_quality_scale
    if args.video_codec == "uncompressed" and qscale == "unset":
        qscale = "1"

    vcodec = get_vcodec(args.video_codec, inp, ctr)

    cmd.extend(["-c:v", vcodec])
    cmd = fset(cmd, "-qscale:v", qscale)
    cmd.extend(["-movflags", "faststart"])
    return cmd


def mux_quality_media(
    ffmpeg: FFmpeg,
    visual_output: List[Tuple[bool, str]],
    audio_output: List[str],
    apply_v: bool,
    ctr: Container,
    output_path: str,
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
                cmd.extend([f"-c:v:{track}", "copy"])
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
        acodec = get_acodec(args.audio_codec, inp, ctr)

        cmd = fset(cmd, "-c:a", acodec)
        cmd = fset(cmd, "-b:a", args.audio_bitrate)

    if same_container and v_tracks > 0:
        cmd = fset(cmd, "-color_range", inp.videos[0].color_range)
        cmd = fset(cmd, "-colorspace", inp.videos[0].color_space)
        cmd = fset(cmd, "-color_primaries", inp.videos[0].color_primaries)
        cmd = fset(cmd, "-color_trc", inp.videos[0].color_transfer)

    if args.extras is not None:
        cmd.extend(args.extras.split(" "))
    cmd.extend(["-strict", "-2"])  # Allow experimental codecs.
    cmd.extend(["-map", "0:t?"])  # Add input attachments to output.

    # This was causing a crash for 'example.mp4 multi-track.mov'
    # cmd.extend(["-map", "0:d?"])

    cmd.append(output_path)
    ffmpeg.run_check_errors(cmd, log, path=output_path)
