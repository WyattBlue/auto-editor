from __future__ import annotations

import os
import sys
from fractions import Fraction
from heapq import heappop, heappush
from os.path import splitext
from pathlib import Path
from subprocess import run
from typing import TYPE_CHECKING, Any

import bv

from auto_editor.ffwrapper import FileInfo
from auto_editor.lib.contracts import is_int, is_str
from auto_editor.make_layers import clipify, make_av, make_timeline
from auto_editor.render.audio import make_new_audio
from auto_editor.render.subtitle import make_new_subtitles
from auto_editor.render.video import render_av
from auto_editor.timeline import v1, v3
from auto_editor.utils.bar import initBar
from auto_editor.utils.chunks import Chunk, Chunks
from auto_editor.utils.cmdkw import ParserError, parse_with_palet, pAttr, pAttrs
from auto_editor.utils.container import Container, container_constructor
from auto_editor.utils.log import Log

if TYPE_CHECKING:
    from auto_editor.__main__ import Args


def set_output(
    out: str | None, _export: str | None, path: Path | None, log: Log
) -> tuple[str, dict[str, Any]]:
    if out is None:
        if path is None:
            log.error("`--output` must be set.")  # When a timeline file is the input.
        root, ext = splitext(path)
    else:
        root, ext = splitext(out)

    if ext == "":
        # Use `mp4` as the default, because it is most compatible.
        ext = ".mp4" if path is None else path.suffix

    if _export is None:
        match ext:
            case ".xml":
                export: dict[str, Any] = {"export": "premiere"}
            case ".fcpxml":
                export = {"export": "final-cut-pro"}
            case ".mlt":
                export = {"export": "shotcut"}
            case ".json":
                export = {"export": "json", "api": 1}
            case _:
                export = {"export": "default"}
    else:
        export = parse_export(_export, log)

    ext_map = {
        "premiere": ".xml",
        "resolve-fcp7": ".xml",
        "final-cut-pro": ".fcpxml",
        "resolve": ".fcpxml",
        "shotcut": ".mlt",
        "json": ".json",
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
        if codec not in ctr.vcodecs and ctr.default_vid != "none":
            return ctr.default_vid
        return codec

    if ctr.vcodecs is not None and codec not in ctr.vcodecs:
        try:
            cobj = bv.Codec(codec, "w")
        except bv.codec.codec.UnknownCodecError:
            log.error(f"Unknown encoder: {codec}")
        # Normalize encoder names
        if cobj.id not in (bv.Codec(x, "w").id for x in ctr.vcodecs):
            log.error(codec_error.format(codec, out_ext))

    return codec


def set_audio_codec(
    codec: str, src: FileInfo | None, out_ext: str, ctr: Container, log: Log
) -> str:
    if codec == "auto":
        if src is None or not src.audios:
            codec = "aac"
        else:
            codec = src.audios[0].codec
            if bv.Codec(codec, "w").audio_formats is None:
                codec = "aac"
        if codec not in ctr.acodecs and ctr.default_aud != "none":
            codec = ctr.default_aud
        if codec is None:
            codec = "aac"
        return codec

    if ctr.acodecs is None or codec not in ctr.acodecs:
        try:
            cobj = bv.Codec(codec, "w")
        except bv.codec.codec.UnknownCodecError:
            log.error(f"Unknown encoder: {codec}")
        # Normalize encoder names
        if cobj.id not in (bv.Codec(x, "w").id for x in ctr.acodecs):
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
        "final-cut-pro": pAttrs(
            "final-cut-pro", name_attr, pAttr("version", 11, is_int)
        ),
        "resolve": pAttrs("resolve", name_attr),
        "resolve-fcp7": pAttrs("resolve-fcp7", name_attr),
        "shotcut": pAttrs("shotcut"),
        "json": pAttrs("json", pAttr("api", 3, is_int)),
        "timeline": pAttrs("json", pAttr("api", 3, is_int)),
        "clip-sequence": pAttrs("clip-sequence"),
    }

    if name in parsing:
        try:
            _tmp = parse_with_palet(text, parsing[name], {})
            _tmp["export"] = name
            return _tmp
        except ParserError as e:
            log.error(e)

    valid_choices = " ".join(f'"{s}"' for s in parsing.keys())
    log.error(f'Invalid export format: "{name}"\nValid choices: {valid_choices}')


def edit_media(paths: list[str], args: Args, log: Log) -> None:
    bar = initBar(args.progress)
    tl = src = use_path = None

    if args.keep_tracks_separate:
        log.deprecated("--keep-tracks-separate is deprecated.")
        args.keep_tracks_separate = False

    if paths:
        path_ext = splitext(paths[0])[1].lower()
        if path_ext == ".xml":
            from auto_editor.formats.fcp7 import fcp7_read_xml

            tl = fcp7_read_xml(paths[0], log)
        elif path_ext == ".mlt":
            from auto_editor.formats.shotcut import shotcut_read_mlt

            tl = shotcut_read_mlt(paths[0], log)
        elif path_ext == ".json":
            from auto_editor.formats.json import read_json

            tl = read_json(paths[0], log)
        else:
            sources = [FileInfo.init(path, log) for path in paths]
            src = sources[0]
            use_path = src.path

    output, export_ops = set_output(args.output, args.export, use_path, log)
    assert "export" in export_ops
    export = export_ops["export"]

    if export == "timeline":
        log.quiet = True

    if not args.preview:
        log.conwrite("Starting")

        if os.path.isdir(output):
            log.error("Output path already has an existing directory!")

    if args.sample_rate is None:
        if tl is None:
            samplerate = 48000 if src is None else src.get_sr()
        else:
            samplerate = tl.sr
    else:
        samplerate = args.sample_rate

    if tl is None:
        tl = make_timeline(sources, args, samplerate, bar, log)
    else:
        if args.resolution is not None:
            tl.T.res = args.resolution
        if args.background is not None:
            tl.background = args.background
        if args.frame_rate is not None:
            log.warning(
                "Setting timebase/framerate is not supported when importing timelines"
            )

    if export == "timeline":
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(export_ops["api"], 0, tl, log)
        return

    if args.preview:
        from auto_editor.preview import preview

        preview(tl, log)
        return

    if export == "json":
        from auto_editor.formats.json import make_json_timeline

        make_json_timeline(export_ops["api"], output, tl, log)
        return

    if export in {"premiere", "resolve-fcp7"}:
        from auto_editor.formats.fcp7 import fcp7_write_xml

        is_resolve = export.startswith("resolve")
        fcp7_write_xml(export_ops["name"], output, is_resolve, tl)
        return

    if export == "final-cut-pro":
        from auto_editor.formats.fcp11 import fcp11_write_xml

        ver = export_ops["version"]
        fcp11_write_xml(export_ops["name"], ver, output, False, tl, log)
        return

    if export == "resolve":
        from auto_editor.formats.fcp11 import fcp11_write_xml
        from auto_editor.timeline import set_stream_to_0

        assert src is not None
        set_stream_to_0(src, tl, log)
        fcp11_write_xml(export_ops["name"], 10, output, True, tl, log)
        return

    if export == "shotcut":
        from auto_editor.formats.shotcut import shotcut_write_mlt

        shotcut_write_mlt(output, tl)
        return

    out_ext = splitext(output)[1].replace(".", "")

    # Check if export options make sense.
    ctr = container_constructor(out_ext.lower(), log)

    if ctr.samplerate is not None and args.sample_rate not in ctr.samplerate:
        log.error(f"'{out_ext}' container only supports samplerates: {ctr.samplerate}")

    args.video_codec = set_video_codec(args.video_codec, src, out_ext, ctr, log)
    args.audio_codec = set_audio_codec(args.audio_codec, src, out_ext, ctr, log)

    def make_media(tl: v3, output_path: str) -> None:
        options = {}
        mov_flags = []
        if args.fragmented and not args.no_fragmented:
            mov_flags.extend(["default_base_moof", "frag_keyframe", "separate_moof"])
            options["frag_duration"] = "0.2"
            if args.faststart:
                log.warning("Fragmented is enabled, will not apply faststart.")
        elif not args.no_faststart:
            mov_flags.append("faststart")
        if mov_flags:
            options["movflags"] = "+".join(mov_flags)

        output = bv.open(output_path, "w", container_options=options)

        # Setup video
        if ctr.default_vid != "none" and tl.v:
            vframes = render_av(output, tl, args, log)
            output_stream: bv.VideoStream | None
            output_stream = next(vframes)  # type: ignore
        else:
            output_stream, vframes = None, iter([])

        # Setup audio
        try:
            audio_encoder = bv.Codec(args.audio_codec, "w")
        except bv.FFmpegError as e:
            log.error(e)
        if audio_encoder.audio_formats is None:
            log.error(f"{args.audio_codec}: No known audio formats avail.")
        fmt = audio_encoder.audio_formats[0]

        audio_streams: list[bv.AudioStream] = []

        if ctr.default_aud == "none":
            while len(tl.a) > 0:
                tl.a.pop()
        elif len(tl.a) > 1 and ctr.max_audios == 1:
            log.warning("Dropping extra audio streams (container only allows one)")

            while len(tl.a) > 1:
                tl.a.pop()

        if len(tl.a) > 0:
            audio_streams, audio_gen_frames = make_new_audio(output, fmt, tl, args, log)
        else:
            audio_streams, audio_gen_frames = [], [iter([])]

        # Setup subtitles
        if ctr.default_sub != "none" and not args.sn:
            sub_paths = make_new_subtitles(tl, log)
        else:
            sub_paths = []

        subtitle_streams = []
        subtitle_inputs = []
        sub_gen_frames = []

        for i, sub_path in enumerate(sub_paths):
            subtitle_input = bv.open(sub_path)
            subtitle_inputs.append(subtitle_input)
            subtitle_stream = output.add_stream_from_template(
                subtitle_input.streams.subtitles[0]
            )
            if i < len(tl.T.subtitles) and (lang := tl.T.subtitles[i].lang) is not None:
                subtitle_stream.metadata["language"] = lang

            subtitle_streams.append(subtitle_stream)
            sub_gen_frames.append(subtitle_input.demux(subtitles=0))

        no_color = log.no_color or log.machine
        encoder_titles = []
        if output_stream is not None:
            name = output_stream.codec.canonical_name
            encoder_titles.append(name if no_color else f"\033[95m{name}")
        if audio_streams:
            name = audio_streams[0].codec.canonical_name
            encoder_titles.append(name if no_color else f"\033[96m{name}")
        if subtitle_streams:
            name = subtitle_streams[0].codec.canonical_name
            encoder_titles.append(name if no_color else f"\033[32m{name}")

        title = f"({os.path.splitext(output_path)[1][1:]}) "
        if no_color:
            title += "+".join(encoder_titles)
        else:
            title += "\033[0m+".join(encoder_titles) + "\033[0m"
        bar.start(tl.end, title)

        MAX_AUDIO_AHEAD = 30  # In timebase, how far audio can be ahead of video.
        MAX_SUB_AHEAD = 30

        class Priority:
            __slots__ = ("index", "frame_type", "frame", "stream")

            def __init__(self, value: int | Fraction, frame, stream):
                self.frame_type: str = stream.type
                assert self.frame_type in ("audio", "subtitle", "video")
                if self.frame_type in {"audio", "subtitle"}:
                    self.index: int | float = round(value * frame.time_base * tl.tb)
                else:
                    self.index = float("inf") if value is None else int(value)
                self.frame = frame
                self.stream = stream

            def __lt__(self, other):
                return self.index < other.index

            def __eq__(self, other):
                return self.index == other.index

        # Priority queue for ordered frames by time_base.
        frame_queue: list[Priority] = []
        latest_audio_index = float("-inf")
        latest_sub_index = float("-inf")
        earliest_video_index = None

        while True:
            if earliest_video_index is None:
                should_get_audio = True
                should_get_sub = True
            else:
                for item in frame_queue:
                    if item.frame_type == "audio":
                        latest_audio_index = max(latest_audio_index, item.index)
                    elif item.frame_type == "subtitle":
                        latest_sub_index = max(latest_sub_index, item.index)

                should_get_audio = (
                    latest_audio_index <= earliest_video_index + MAX_AUDIO_AHEAD
                )
                should_get_sub = (
                    latest_sub_index <= earliest_video_index + MAX_SUB_AHEAD
                )

            index, video_frame = next(vframes, (0, None))

            if video_frame:
                earliest_video_index = index
                heappush(frame_queue, Priority(index, video_frame, output_stream))

            if should_get_audio:
                audio_frames = [next(frames, None) for frames in audio_gen_frames]
                if output_stream is None and audio_frames and audio_frames[-1]:
                    assert audio_frames[-1].time is not None
                    index = round(audio_frames[-1].time * tl.tb)
            else:
                audio_frames = [None]
            if should_get_sub:
                subtitle_frames = [next(packet, None) for packet in sub_gen_frames]
            else:
                subtitle_frames = [None]

            # Break if no more frames
            if (
                all(frame is None for frame in audio_frames)
                and video_frame is None
                and all(packet is None for packet in subtitle_frames)
            ):
                break

            if should_get_audio:
                for audio_stream, aframe in zip(audio_streams, audio_frames):
                    if aframe is None:
                        continue
                    assert aframe.pts is not None
                    heappush(frame_queue, Priority(aframe.pts, aframe, audio_stream))
            if should_get_sub:
                for subtitle_stream, packet in zip(subtitle_streams, subtitle_frames):
                    if packet and packet.pts is not None:
                        packet.stream = subtitle_stream
                        heappush(
                            frame_queue, Priority(packet.pts, packet, subtitle_stream)
                        )

            while frame_queue and frame_queue[0].index <= index:
                item = heappop(frame_queue)
                frame_type = item.frame_type
                bar_index = None
                try:
                    if frame_type in {"video", "audio"}:
                        if item.frame.time is not None:
                            bar_index = round(item.frame.time * tl.tb)
                        output.mux(item.stream.encode(item.frame))
                    elif frame_type == "subtitle":
                        output.mux(item.frame)
                except bv.error.ExternalError:
                    log.error(
                        f"Generic error for encoder: {item.stream.name}\n"
                        f"at {item.index} time_base\nPerhaps video quality settings are too low?"
                    )
                except bv.FileNotFoundError:
                    log.error(f"File not found: {output_path}")
                except bv.FFmpegError as e:
                    log.error(e)

                if bar_index:
                    bar.tick(bar_index)

        # Flush streams
        if output_stream is not None:
            output.mux(output_stream.encode(None))
        for audio_stream in audio_streams:
            output.mux(audio_stream.encode(None))

        bar.end()

        # Close resources
        for subtitle_input in subtitle_inputs:
            subtitle_input.close()
        output.close()

    if export == "clip-sequence":
        if tl.v1 is None:
            log.error("Timeline too complex to use clip-sequence export")

        def pad_chunk(chunk: Chunk, total: int) -> Chunks:
            start = [] if chunk[0] == 0 else [(0, chunk[0], 99999.0)]
            end = [] if chunk[1] == total else [(chunk[1], total, 99999.0)]
            return start + [chunk] + end

        def append_filename(path: str, val: str) -> str:
            root, ext = splitext(path)
            return root + val + ext

        total_frames = tl.v1.chunks[-1][1] - 1
        clip_num = 0
        for chunk in tl.v1.chunks:
            if chunk[2] == 0 or chunk[2] >= 99999:
                continue

            padded_chunks = pad_chunk(chunk, total_frames)

            vspace, aspace = make_av(
                tl.v1.source, [clipify(padded_chunks, tl.v1.source)]
            )
            my_timeline = v3(
                tl.tb,
                "#000",
                tl.template,
                vspace,
                aspace,
                v1(tl.v1.source, padded_chunks),
            )

            make_media(my_timeline, append_filename(output, f"-{clip_num}"))
            clip_num += 1
    else:
        make_media(tl, output)

    log.stop_timer()

    if not args.no_open and export == "default":
        if args.player is None:
            if sys.platform == "win32":
                try:
                    os.startfile(output)
                except OSError:
                    log.warning(f"Could not find application to open file: {output}")
            else:
                try:  # MacOS case
                    run(["open", output])
                except Exception:
                    try:  # WSL2 case
                        run(["cmd.exe", "/C", "start", output])
                    except Exception:
                        try:  # Linux case
                            run(["xdg-open", output])
                        except Exception:
                            log.warning(f"Could not open output file: {output}")
        else:
            run(__import__("shlex").split(args.player) + [output])
