import os
from typing import List, Optional, Type

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.timeline import Timeline, make_timeline
from auto_editor.utils.container import get_rules
from auto_editor.utils.log import Log
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.utils.types import Chunk, Chunks, MainArgs


def set_output_name(path: str, inp_ext: str, export: str) -> str:
    root, ext = os.path.splitext(path)

    if export == "json":
        return f"{root}.json"
    if export == "final-cut-pro":
        return f"{root}.fcpxml"
    if export == "shotcut":
        return f"{root}.mlt"
    if export == "premiere":
        return f"{root}.xml"
    if export == "audio":
        return f"{root}_ALTERED.wav"
    if ext == "":
        return root + inp_ext

    return f"{root}_ALTERED{ext}"


def edit_media(
    path_list: List[str], ffmpeg: FFmpeg, args: Type[MainArgs], temp: str, log: Log
) -> Optional[str]:

    progress = ProgressBar(args.progress)
    timeline = None

    path_ext = os.path.splitext(path_list[0])[1]
    if path_ext == ".json":
        from auto_editor.formats.json import read_json

        timeline = read_json(path_list[0], ffmpeg, log)
        inputs: List[FileInfo] = timeline.inputs
    else:
        inputs = []
        for path in path_list:
            inputs.append(FileInfo(path, ffmpeg, log))

    del path_list
    inp = inputs[0]

    if args.output_file is None:
        output = set_output_name(inp.path, inp.ext, args.export)
    else:
        output = args.output_file
        if os.path.splitext(output)[1] == "":
            output = set_output_name(output, inp.ext, args.export)

    output_container = os.path.splitext(output)[1].replace(".", "")

    # Check if export options make sense.
    rules = get_rules(output_container)
    codec_error = "'{}' codec is not supported in '{}' container."

    if not (args.sample_rate is None or args.sample_rate == "unset"):
        if rules.samplerate is not None and args.sample_rate not in rules.samplerate:
            log.error(
                f"'{output_container}' container only supports samplerates: {rules.samplerate}"
            )

    vcodec = args.video_codec
    if vcodec == "uncompressed":
        vcodec = "mpeg4"
    if vcodec == "copy":
        vcodec = inp.videos[0].codec

    if vcodec != "auto":
        if rules.vstrict:
            assert rules.vcodecs is not None
            if vcodec not in rules.vcodecs:
                log.error(codec_error.format(vcodec, output_container))

        if vcodec in rules.disallow_v:
            log.error(codec_error.format(vcodec, output_container))

    acodec = args.audio_codec
    if acodec == "copy":
        acodec = inp.audios[0].codec
        log.debug(f"Settings acodec to {acodec}")

    if acodec not in ("unset", "auto"):
        if rules.astrict:
            assert rules.acodecs is not None
            if acodec not in rules.acodecs:
                log.error(codec_error.format(acodec, output_container))

        if acodec in rules.disallow_a:
            log.error(codec_error.format(acodec, output_container))

    if args.keep_tracks_separate and rules.max_audios == 1:
        log.warning(
            f"'{output_container}' container doesn't support multiple audio tracks."
        )

    if not args.preview and not args.timeline:
        if os.path.isdir(output):
            log.error("Output path already has an existing directory!")

        if os.path.isfile(output) and inputs[0].path != output:
            log.debug(f"Removing already existing file: {output}")
            os.remove(output)

    # Extract subtitles in their native format.
    if len(inp.subtitles) > 0:
        cmd = ["-i", inp.path, "-hide_banner"]
        for s, sub in enumerate(inp.subtitles):
            cmd.extend(["-map", f"0:s:{s}"])
        for s, sub in enumerate(inp.subtitles):
            cmd.extend([os.path.join(temp, f"{s}s.{sub.ext}")])
        ffmpeg.run(cmd)

    log.conwrite("Extracting audio")

    cmd = []
    for i, inp in enumerate(inputs):
        cmd.extend(["-i", inp.path])
    cmd.append("-hide_banner")

    if args.sample_rate is None:
        samplerate = inputs[0].get_samplerate()
    else:
        samplerate = args.sample_rate

    for i, inp in enumerate(inputs):
        for s in range(len(inp.audios)):
            cmd.extend(
                [
                    "-map",
                    f"{i}:a:{s}",
                    "-ac",
                    "2",
                    "-ar",
                    f"{samplerate}",
                    "-rf64",
                    "always",
                    os.path.join(temp, f"{i}-{s}.wav"),
                ]
            )

    ffmpeg.run(cmd)

    if timeline is None:
        timeline = make_timeline(inputs, args, samplerate, progress, temp, log)

    if args.timeline:
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(args.api, 0, timeline, log)
        return None

    if args.preview:
        from auto_editor.preview import preview

        preview(timeline, temp, log)
        return None

    if args.export == "json":
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(args.api, output, timeline, log)
        return output

    if args.export == "premiere":
        from auto_editor.formats.premiere import premiere_xml

        premiere_xml(temp, output, timeline)
        return output

    if args.export == "final-cut-pro":
        from auto_editor.formats.final_cut_pro import fcp_xml

        fcp_xml(output, timeline)
        return output

    if args.export == "shotcut":
        from auto_editor.formats.shotcut import shotcut_xml

        shotcut_xml(output, timeline)
        return output

    def make_media(inp: FileInfo, timeline: Timeline, output: str) -> None:
        from auto_editor.output import mux_quality_media
        from auto_editor.render.video import render_av

        if rules.allow_subtitle:
            from auto_editor.render.subtitle import cut_subtitles

            cut_subtitles(ffmpeg, timeline, temp, log)

        if rules.allow_audio:
            from auto_editor.render.audio import make_new_audio

            for t in range(len(inp.audios)):
                make_new_audio(t, temp, timeline, progress, log)

        video_output = []

        if rules.allow_video:
            for v, vid in enumerate(inp.videos):
                if vid.codec not in ("png", "mjpeg", "webp") and v == 0:
                    out_path, apply_later = render_av(
                        ffmpeg, timeline, args, progress, rules, temp, log
                    )
                    video_output.append((v, True, out_path, apply_later))
                elif rules.allow_image:
                    out_path = os.path.join(temp, f"{v}.{vid.codec}")
                    # fmt: off
                    ffmpeg.run(["-i", inp.path, "-map", "0:v", "-map", "-0:V",
                        "-c", "copy", out_path])
                    # fmt: on
                    video_output.append((v, False, out_path, False))

        log.conwrite("Writing output file")

        mux_quality_media(
            ffmpeg, video_output, rules, output, output_container, args, inp, temp, log
        )

    if args.export == "clip-sequence":
        chunks = timeline.chunks
        if chunks is None:
            log.error("Timeline to complex to use clip-sequence export")

        total_frames = chunks[-1][1] - 1
        from auto_editor.timeline import clipify, make_av
        from auto_editor.utils.func import append_filename

        def pad_chunk(chunk: Chunk, total_frames: int) -> Chunks:
            start = [] if chunk[0] == 0 else [(0, chunk[0], 99999.0)]
            end = (
                [] if chunk[1] == total_frames else [(chunk[1], total_frames, 99999.0)]
            )
            return start + [chunk] + end

        clip_num = 0
        for chunk in chunks:
            if chunk[2] == 99999:
                continue

            _c = pad_chunk(chunk, total_frames)
            vspace, aspace = make_av(clipify(_c, 0), inp)
            my_timeline = Timeline(
                timeline.inputs,
                timeline.fps,
                timeline.samplerate,
                timeline.res,
                "#000",
                vspace,
                aspace,
                _c,
            )

            make_media(
                inp,
                my_timeline,
                append_filename(output, f"-{clip_num}"),
            )
            clip_num += 1
    else:
        make_media(inp, timeline, output)
    return output
