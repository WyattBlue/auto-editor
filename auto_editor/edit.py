from __future__ import annotations

import os

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.output import Ensure
from auto_editor.timeline import Timeline, make_timeline
from auto_editor.utils.bar import Bar
from auto_editor.utils.chunks import Chunk, Chunks
from auto_editor.utils.container import Container, container_constructor
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


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


codec_error = "'{}' codec is not supported in '{}' container."


def set_video_codec(
    codec: str, inp: FileInfo | None, out_ext: str, ctr: Container, log: Log
) -> str:
    if codec == "auto":
        codec = "h264" if (inp is None or not inp.videos) else inp.videos[0].codec
        if ctr.vcodecs is not None:
            if ctr.vstrict and codec not in ctr.vcodecs:
                return ctr.vcodecs[0]

            if codec in ctr.disallow_v:
                return ctr.vcodecs[0]
        return codec

    if codec == "copy":
        if inp is None:
            log.error("No input to copy its codec from.")
        if not inp.videos:
            log.error("Input file does not have a video stream to copy codec from.")
        codec = inp.videos[0].codec

    if ctr.vstrict:
        assert ctr.vcodecs is not None
        if codec not in ctr.vcodecs:
            log.error(codec_error.format(codec, out_ext))

    if codec in ctr.disallow_v:
        log.error(codec_error.format(codec, out_ext))

    return codec


def set_audio_codec(
    codec: str, inp: FileInfo | None, out_ext: str, ctr: Container, log: Log
) -> str:
    if codec == "auto":
        codec = "aac" if (inp is None or not inp.audios) else inp.audios[0].codec
        if ctr.acodecs is not None:
            if ctr.astrict and codec not in ctr.acodecs:
                return ctr.acodecs[0]

            if codec in ctr.disallow_a:
                return ctr.acodecs[0]
        return codec

    if codec == "copy":
        if inp is None:
            log.error("No input to copy its codec from.")
        if not inp.audios:
            log.error("Input file does not have an audio stream to copy codec from.")
        codec = inp.audios[0].codec

    if codec != "unset":
        if ctr.astrict:
            assert ctr.acodecs is not None
            if codec not in ctr.acodecs:
                log.error(codec_error.format(codec, out_ext))

        if codec in ctr.disallow_a:
            log.error(codec_error.format(codec, out_ext))

    return codec


def edit_media(
    paths: list[str], ffmpeg: FFmpeg, args: Args, temp: str, log: Log
) -> str | None:

    bar = Bar(args.progress)
    timeline = None

    if paths:
        path_ext = os.path.splitext(paths[0])[1]
        if path_ext == ".json":
            from auto_editor.formats.json import read_json

            timeline = read_json(paths[0], ffmpeg, log)
            inputs: list[FileInfo] = timeline.inputs
        else:
            inputs = [FileInfo(i, istr, ffmpeg, log) for i, istr in enumerate(paths)]
    else:
        inputs = []
    del paths

    inp = None if not inputs else inputs[0]

    if inp is None:
        output = "out.mp4" if args.output_file is None else args.output_file
    else:
        if args.output_file is None:
            output = set_output_name(inp.path, inp.ext, args.export)
        else:
            output = args.output_file
            if os.path.splitext(output)[1] == "":
                output = set_output_name(output, inp.ext, args.export)

    out_ext = os.path.splitext(output)[1].replace(".", "")

    # Check if export options make sense.
    ctr = container_constructor(out_ext)

    if ctr.samplerate is not None and args.sample_rate not in ctr.samplerate:
        log.error(f"'{out_ext}' container only supports samplerates: {ctr.samplerate}")

    args.video_codec = set_video_codec(args.video_codec, inp, out_ext, ctr, log)
    args.audio_codec = set_audio_codec(args.audio_codec, inp, out_ext, ctr, log)

    if args.keep_tracks_separate and ctr.max_audios == 1:
        log.warning(f"'{out_ext}' container doesn't support multiple audio tracks.")

    if not args.preview and not args.timeline:
        if os.path.isdir(output):
            log.error("Output path already has an existing directory!")

        if os.path.isfile(output) and inputs[0].path != output:
            log.debug(f"Removing already existing file: {output}")
            os.remove(output)

    # Extract subtitles in their native format.
    if inp is not None and len(inp.subtitles) > 0:
        cmd = ["-i", inp.path, "-hide_banner"]
        for s, sub in enumerate(inp.subtitles):
            cmd.extend(["-map", f"0:s:{s}"])
        for s, sub in enumerate(inp.subtitles):
            cmd.extend([os.path.join(temp, f"{s}s.{sub.ext}")])
        ffmpeg.run(cmd)
        del inp

    if args.sample_rate is None:
        if inputs:
            samplerate = inputs[0].get_samplerate()
        else:
            samplerate = 48000
    else:
        samplerate = args.sample_rate

    ensure = Ensure(ffmpeg, samplerate, temp, log)

    if timeline is None:
        timeline = make_timeline(inputs, ensure, args, samplerate, bar, temp, log)

    if args.timeline:
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(args.api, 0, timeline, log)
        return None

    if args.preview:
        from auto_editor.preview import preview

        preview(ensure, timeline, temp, log)
        return None

    if out_ext == "json":
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(args.api, output, timeline, log)
        args.no_open = True
        return output

    if args.export == "premiere":
        from auto_editor.formats.premiere import premiere_xml

        premiere_xml(ensure, output, timeline)
        return output

    if args.export == "final-cut-pro":
        from auto_editor.formats.final_cut_pro import fcp_xml

        fcp_xml(output, timeline)
        return output

    if args.export == "shotcut":
        from auto_editor.formats.shotcut import shotcut_xml

        shotcut_xml(output, timeline)
        return output

    def make_media(timeline: Timeline, output: str) -> None:
        from auto_editor.output import mux_quality_media
        from auto_editor.render.video import render_av

        visual_output = []
        audio_output = []
        apply_later = False
        inp = timeline.inputs[0]

        if ctr.allow_subtitle:
            from auto_editor.render.subtitle import cut_subtitles

            cut_subtitles(ffmpeg, timeline, temp, log)

        if ctr.allow_audio:
            from auto_editor.render.audio import make_new_audio

            audio_output = make_new_audio(timeline, ensure, ffmpeg, bar, temp, log)

        if ctr.allow_video:
            if len(timeline.v) > 0:
                out_path, apply_later = render_av(
                    ffmpeg, timeline, args, bar, ctr, temp, log
                )
                visual_output.append((True, out_path))

            for v, vid in enumerate(inp.videos, start=1):
                if ctr.allow_image and vid.codec in ("png", "mjpeg", "webp"):
                    out_path = os.path.join(temp, f"{v}.{vid.codec}")
                    # fmt: off
                    ffmpeg.run(["-i", inp.path, "-map", "0:v", "-map", "-0:V",
                        "-c", "copy", out_path])
                    # fmt: on
                    visual_output.append((False, out_path))

        log.conwrite("Writing output file")
        mux_quality_media(
            ffmpeg,
            visual_output,
            audio_output,
            apply_later,
            ctr,
            output,
            timeline.timebase,
            args,
            inp,
            temp,
            log,
        )

    if args.export == "clip-sequence":
        chunks = timeline.chunks
        if chunks is None:
            log.error("Timeline to complex to use clip-sequence export")

        from auto_editor.make_layers import clipify, make_av
        from auto_editor.utils.func import append_filename

        def pad_chunk(chunk: Chunk, total: int) -> Chunks:
            start = [] if chunk[0] == 0 else [(0, chunk[0], 99999.0)]
            end = [] if chunk[1] == total else [(chunk[1], total, 99999.0)]
            return start + [chunk] + end

        total_frames = chunks[-1][1] - 1
        clip_num = 0
        for chunk in chunks:
            if chunk[2] == 99999:
                continue

            _c = pad_chunk(chunk, total_frames)
            vspace, aspace = make_av([clipify(_c, 0)], [timeline.inputs[0]])
            my_timeline = Timeline(
                timeline.inputs,
                timeline.timebase,
                timeline.samplerate,
                timeline.res,
                "#000",
                vspace,
                aspace,
                _c,
            )

            make_media(my_timeline, append_filename(output, f"-{clip_num}"))
            clip_num += 1
    else:
        make_media(timeline, output)
    return output
