from __future__ import annotations

import os
from typing import Any

from auto_editor.ffwrapper import FFmpeg, FileInfo, initFileInfo
from auto_editor.lib.contracts import is_int, is_str
from auto_editor.make_layers import make_timeline
from auto_editor.output import Ensure, mux_quality_media
from auto_editor.render.audio import make_new_audio
from auto_editor.render.subtitle import make_new_subtitles
from auto_editor.render.video import render_av
from auto_editor.timeline import v1, v3
from auto_editor.utils.bar import Bar
from auto_editor.utils.chunks import Chunk, Chunks
from auto_editor.utils.cmdkw import ParserError, parse_with_palet, pAttr, pAttrs
from auto_editor.utils.container import Container, container_constructor
from auto_editor.utils.log import Log
from auto_editor.utils.types import Args


def set_output(
    out: str | None, _export: str | None, src: FileInfo | None, log: Log
) -> tuple[str, dict[str, Any]]:
    if src is None:
        root, ext = "out", ".mp4"
    else:
        root, ext = os.path.splitext(str(src.path) if out is None else out)
        if ext == "":
            ext = src.path.suffix

    if _export is None:
        if ext == ".xml":
            export = {"export": "premiere"}
        elif ext == ".fcpxml":
            export = {"export": "final-cut-pro"}
        elif ext == ".mlt":
            export = {"export": "shotcut"}
        elif ext == ".json":
            export = {"export": "json"}
        else:
            export = {"export": "default"}
    else:
        export = parse_export(_export, log)

    ext_map = {
        "premiere": ".xml",
        "resolve": ".fcpxml",
        "final-cut-pro": ".fcpxml",
        "shotcut": ".mlt",
        "json": ".json",
        "audio": ".wav",
    }
    if export["export"] in ext_map:
        ext = ext_map[export["export"]]

    if out is None:
        return f"{root}_ALTERED{ext}", export

    return f"{root}{ext}", export


codec_error = "'{}' codec is not supported in '{}' container."


def set_video_codec(
    codec: str, src: FileInfo | None, out_ext: str, ctr: Container, log: Log
) -> str:
    if codec == "auto":
        codec = "h264" if (src is None or not src.videos) else src.videos[0].codec
        if ctr.vcodecs is not None:
            if ctr.vstrict and codec not in ctr.vcodecs:
                return ctr.vcodecs[0]

            if codec in ctr.disallow_v:
                return ctr.vcodecs[0]
        return codec

    if codec == "copy":
        if src is None:
            log.error("No input to copy its codec from.")
        if not src.videos:
            log.error("Input file does not have a video stream to copy codec from.")
        codec = src.videos[0].codec

    if ctr.vstrict:
        assert ctr.vcodecs is not None
        if codec not in ctr.vcodecs:
            log.error(codec_error.format(codec, out_ext))

    if codec in ctr.disallow_v:
        log.error(codec_error.format(codec, out_ext))

    return codec


def set_audio_codec(
    codec: str, src: FileInfo | None, out_ext: str, ctr: Container, log: Log
) -> str:
    if codec == "auto":
        codec = "aac" if (src is None or not src.audios) else src.audios[0].codec
        if ctr.acodecs is not None and codec not in ctr.acodecs:
            return ctr.acodecs[0]
        return codec

    if codec == "copy":
        if src is None:
            log.error("No input to copy its codec from.")
        if not src.audios:
            log.error("Input file does not have an audio stream to copy codec from.")
        codec = src.audios[0].codec

    if codec != "unset":
        if ctr.acodecs is None or codec not in ctr.acodecs:
            log.error(codec_error.format(codec, out_ext))

    return codec


def parse_export(export: str, log: Log) -> dict[str, Any]:
    exploded = export.split(":", maxsplit=1)
    if len(exploded) == 1:
        name, text = exploded[0], ""
    else:
        name, text = exploded

    name_attr = pAttr("name", "Auto-Editor Media Group", is_str)

    parsing: dict[str, pAttrs] = {
        "default": pAttrs("default"),
        "premiere": pAttrs("premiere", name_attr),
        "resolve": pAttrs("resolve", name_attr),
        "final-cut-pro": pAttrs("final-cut-pro", name_attr),
        "shotcut": pAttrs("shotcut"),
        "json": pAttrs("json", pAttr("api", 3, is_int)),
        "timeline": pAttrs("json", pAttr("api", 3, is_int)),
        "audio": pAttrs("audio"),
        "clip-sequence": pAttrs("clip-sequence"),
    }

    if name in parsing:
        try:
            _tmp = parse_with_palet(text, parsing[name], {})
            _tmp["export"] = name
            return _tmp
        except ParserError as e:
            log.error(e)

    log.error(f"'{name}': Export must be [{', '.join([s for s in parsing.keys()])}]")


def edit_media(
    paths: list[str], ffmpeg: FFmpeg, args: Args, temp: str, log: Log
) -> None:
    bar = Bar(args.progress)
    tl = None

    if paths:
        path_ext = os.path.splitext(paths[0])[1].lower()
        if path_ext == ".xml":
            from auto_editor.formats.fcp7 import fcp7_read_xml

            tl = fcp7_read_xml(paths[0], log)
            assert tl.src is not None
            sources: list[FileInfo] = [tl.src]
            src: FileInfo | None = tl.src

        elif path_ext == ".mlt":
            from auto_editor.formats.shotcut import shotcut_read_mlt

            tl = shotcut_read_mlt(paths[0], log)
            assert tl.src is not None
            sources = [tl.src]
            src = tl.src

        elif path_ext == ".json":
            from auto_editor.formats.json import read_json

            tl = read_json(paths[0], log)
            sources = [] if tl.src is None else [tl.src]
            src = tl.src
        else:
            sources = [initFileInfo(path, log) for path in paths]
            src = None if not sources else sources[0]

    del paths

    output, export = set_output(args.output_file, args.export, src, log)
    assert "export" in export

    if export["export"] == "timeline":
        log.quiet = True

    if not args.preview:
        log.conwrite("Starting")

        if os.path.isdir(output):
            log.error("Output path already has an existing directory!")

        if os.path.isfile(output) and src is not None and src.path != output:  # type: ignore
            log.debug(f"Removing already existing file: {output}")
            os.remove(output)

    if args.sample_rate is None:
        if tl is None:
            samplerate = 48000 if src is None else src.get_sr()
        else:
            samplerate = tl.sr
    else:
        samplerate = args.sample_rate

    ensure = Ensure(ffmpeg, bar, samplerate, temp, log)

    if tl is None:
        tl = make_timeline(sources, ensure, args, samplerate, bar, temp, log)

    if export["export"] == "timeline":
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(export["api"], 0, tl, log)
        return

    if args.preview:
        from auto_editor.preview import preview

        preview(ensure, tl, temp, log)
        return

    if export["export"] == "json":
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(export["api"], output, tl, log)
        return

    if export["export"] == "premiere":
        from auto_editor.formats.fcp7 import fcp7_write_xml

        fcp7_write_xml(export["name"], output, tl, log)
        return

    if export["export"] in ("final-cut-pro", "resolve"):
        from auto_editor.formats.fcp11 import fcp11_write_xml

        fcp11_write_xml(export["name"], ffmpeg, output, export["export"], tl, log)
        return

    if export["export"] == "shotcut":
        from auto_editor.formats.shotcut import shotcut_write_mlt

        shotcut_write_mlt(output, tl)
        return

    out_ext = os.path.splitext(output)[1].replace(".", "")

    # Check if export options make sense.
    ctr = container_constructor(out_ext.lower())

    if ctr.samplerate is not None and args.sample_rate not in ctr.samplerate:
        log.error(f"'{out_ext}' container only supports samplerates: {ctr.samplerate}")

    args.video_codec = set_video_codec(args.video_codec, src, out_ext, ctr, log)
    args.audio_codec = set_audio_codec(args.audio_codec, src, out_ext, ctr, log)

    if args.keep_tracks_separate and ctr.max_audios == 1:
        log.warning(f"'{out_ext}' container doesn't support multiple audio tracks.")

    def make_media(tl: v3, output: str) -> None:
        assert src is not None

        visual_output = []
        audio_output = []
        sub_output = []
        apply_later = False

        if ctr.allow_subtitle and not args.sn:
            sub_output = make_new_subtitles(tl, ensure, temp)

        if ctr.allow_audio:
            audio_output = make_new_audio(tl, ensure, args, ffmpeg, bar, temp, log)

        if ctr.allow_video:
            if tl.v:
                out_path, apply_later = render_av(ffmpeg, tl, args, bar, ctr, temp, log)
                visual_output.append((True, out_path))

            for v, vid in enumerate(src.videos, start=1):
                if ctr.allow_image and vid.codec in ("png", "mjpeg", "webp"):
                    out_path = os.path.join(temp, f"{v}.{vid.codec}")
                    # fmt: off
                    ffmpeg.run(["-i", f"{src.path}", "-map", "0:v", "-map", "-0:V",
                        "-c", "copy", out_path])
                    # fmt: on
                    visual_output.append((False, out_path))

        log.conwrite("Writing output file")
        mux_quality_media(
            ffmpeg,
            visual_output,
            audio_output,
            sub_output,
            apply_later,
            ctr,
            output,
            tl.tb,
            args,
            src,
            temp,
            log,
        )

    if export["export"] == "clip-sequence":
        if tl.v1 is None:
            log.error("Timeline too complex to use clip-sequence export")

        from auto_editor.make_layers import clipify, make_av
        from auto_editor.utils.func import append_filename

        def pad_chunk(chunk: Chunk, total: int) -> Chunks:
            start = [] if chunk[0] == 0 else [(0, chunk[0], 99999.0)]
            end = [] if chunk[1] == total else [(chunk[1], total, 99999.0)]
            return start + [chunk] + end

        total_frames = tl.v1.chunks[-1][1] - 1
        clip_num = 0
        for chunk in tl.v1.chunks:
            if chunk[2] == 99999:
                continue

            padded_chunks = pad_chunk(chunk, total_frames)

            vspace, aspace = make_av(
                tl.v1.source, [clipify(padded_chunks, tl.v1.source)]
            )
            my_timeline = v3(
                tl.v1.source,
                tl.tb,
                tl.sr,
                tl.res,
                "#000",
                vspace,
                aspace,
                v1(tl.v1.source, padded_chunks),
            )

            make_media(my_timeline, append_filename(output, f"-{clip_num}"))
            clip_num += 1
    else:
        make_media(tl, output)

    log.stop_timer()

    if not args.no_open and export["export"] in ("default", "audio", "clip-sequence"):
        if args.player is None:
            from auto_editor.utils.func import open_with_system_default

            open_with_system_default(output, log)
        else:
            import subprocess
            from shlex import split

            subprocess.run(split(args.player) + [output])
