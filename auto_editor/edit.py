# Internal Libraries
import os

# Typing
from typing import List, Tuple, Optional

# Included Libraries
from auto_editor.sheet import Sheet
from auto_editor.utils.log import Log
from auto_editor.utils.func import fnone, append_filename
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.method import get_chunks
from auto_editor.ffwrapper import FFmpeg, FileInfo

def set_output_name(path: str, inp_ext: str, export: str) -> str:
    root, ext = os.path.splitext(path)

    if export == 'json':
        return root + '.json'
    if export == 'final-cut-pro':
        return root + '.fcpxml'
    if export == 'shotcut':
        return root + '.mlt'
    if export == 'premiere':
        return root + '.xml'
    if export == 'audio':
        return root + '_ALTERED.wav'
    if ext == '':
        return root + inp_ext

    return root + '_ALTERED' + ext


def edit_media(
    i: int, inp: FileInfo, ffmpeg: FFmpeg, args, progress: ProgressBar, temp: str, log: Log
) -> Tuple[int, Optional[str]]:
    from auto_editor.utils.container import get_rules

    chunks = None
    if inp.ext == '.json':
        from auto_editor.formats.timeline import read_json_timeline

        args.background, input_path, chunks = read_json_timeline(inp.path, log)
        inp = FileInfo(input_path, ffmpeg)

    if i < len(args.output_file):
        output_path = args.output_file[i]

        # Add input extension if output doesn't have one.
        if os.path.splitext(output_path)[1] == '':
            output_path = set_output_name(output_path, inp.ext, args.export)
    else:
        output_path = set_output_name(inp.path, inp.ext, args.export)

    log.debug(f'{inp.path} -> {output_path}')

    output_container = os.path.splitext(output_path)[1].replace('.', '')

    # Check if export options make sense.
    rules = get_rules(output_container)
    codec_error = "'{}' codec is not supported in '{}' container."

    if not fnone(args.sample_rate):
        if rules['samplerate'] is not None and args.sample_rate not in rules['samplerate']:
            log.error(
                f"'{output_container}' container only supports "
                f"samplerates: {rules['samplerate']}"
            )

    vcodec = args.video_codec
    if vcodec == 'uncompressed':
        vcodec = 'mpeg4'
    if vcodec == 'copy':
        vcodec = inp.video_streams[0]['codec']

    if vcodec != 'auto':
        if rules['vstrict'] and vcodec not in rules['vcodecs']:
            log.error(codec_error.format(vcodec, output_container))

        if vcodec in rules['disallow_v']:
            log.error(codec_error.format(vcodec, output_container))

    acodec = args.audio_codec
    if acodec == 'copy':
        acodec = inp.audio_streams[0]['codec']
        log.debug(f'Settings acodec to {acodec}')

    if acodec not in ('unset', 'auto'):
        if rules['astrict'] and acodec not in rules['acodecs']:
            log.error(codec_error.format(acodec, output_container))

        if acodec in rules['disallow_a']:
            log.error(codec_error.format(acodec, output_container))

    if args.keep_tracks_seperate and rules['max_audio_streams'] == 1:
        log.warning(f"'{container}' container doesn't support multiple audio tracks.")

    if not args.preview and not args.timeline:
        if os.path.isdir(output_path):
            log.error('Output path already has an existing directory!')

        if os.path.isfile(output_path) and inp.path != output_path:
            log.debug(f'Removing already existing file: {output_path}')
            os.remove(output_path)

    tracks = len(inp.audio_streams)

    fps = 30.0 if inp.fps is None else float(inp.fps)

    if fps < 1:
        log.error(f'{inp.basename}: Frame rate cannot be below 1. fps: {fps}')

    # Extract subtitles in their native format.
    if len(inp.subtitle_streams) > 0:
        cmd = ['-i', inp.path, '-hide_banner']
        for s, sub in enumerate(inp.subtitle_streams):
            cmd.extend(['-map', f'0:s:{s}'])
        for s, sub in enumerate(inp.subtitle_streams):
            cmd.extend([os.path.join(temp, f"{s}s.{sub['ext']}")])
        ffmpeg.run(cmd)

    # Split audio tracks into: 0.wav, 1.wav, etc.
    log.conwrite('Extracting audio')

    cmd = ['-i', inp.path, '-hide_banner']
    for t in range(tracks):
        cmd.extend(['-map', f'0:a:{t}', '-ac', '2', os.path.join(temp, f'{t}.wav')])
    ffmpeg.run(cmd)
    del cmd


    if chunks is None:
        chunks = get_chunks(inp, fps, args, progress, temp, log)

    if len(chunks) == 1 and chunks[0][2] == 99999:
        log.error('The entire media is cut!')

    def is_clip(chunk: Tuple[int, int, float]) -> bool:
        return chunk[2] != 99999

    def number_of_cuts(chunks: List[Tuple[int, int, float]]) -> int:
        return len(list(filter(is_clip, chunks)))

    num_cuts = number_of_cuts(chunks)


    pool = args.add_text + args.add_rectangle + args.add_ellipse + args.add_image

    obj_sheet = Sheet(pool, inp, chunks, log)

    if args.timeline:
        from auto_editor.formats.timeline import make_json_timeline
        make_json_timeline(
            args.api, inp.path, 0, obj_sheet, chunks, fps, args.background, log
        )
        return num_cuts, None

    if args.preview:
        from auto_editor.preview import preview
        preview(inp, chunks, log)
        return num_cuts, None

    if args.export == 'json':
        from auto_editor.formats.timeline import make_json_timeline
        make_json_timeline(
            args.api, inp.path, output_path, obj_sheet, chunks, fps, args.background, log
        )
        return num_cuts, output_path

    if args.export == 'premiere':
        from auto_editor.formats.premiere import premiere_xml
        premiere_xml(inp, temp, output_path, chunks, fps, log)
        return num_cuts, output_path

    if args.export == 'final-cut-pro':
        from auto_editor.formats.final_cut_pro import fcp_xml

        fcp_xml(inp, output_path, chunks, fps, log)
        return num_cuts, output_path

    if args.export == 'shotcut':
        from auto_editor.formats.shotcut import shotcut_xml

        shotcut_xml(inp, output_path, chunks, fps, log)
        return num_cuts, output_path

    def pad_chunk(
        chunk: Tuple[int, int, float], total_frames: int
    ) -> List[Tuple[int, int, float]]:

        start = []
        end = []
        if chunk[0] != 0:
            start.append((0, chunk[0], 99999.0))

        if chunk[1] != total_frames - 1:
            end.append((chunk[1], total_frames - 1, 99999.0))

        return start + [chunk] + end


    def make_media(inp: FileInfo, chunks: List[Tuple[int, int, float]], output_path: str
    ) -> None:
        from auto_editor.utils.video import mux_quality_media

        if rules['allow_subtitle']:
            from auto_editor.render.subtitle import cut_subtitles
            cut_subtitles(ffmpeg, inp, chunks, fps, temp, log)

        if rules['allow_audio']:
            from auto_editor.render.audio import make_new_audio

            for t in range(tracks):
                temp_file = os.path.join(temp, f'{t}.wav')
                new_file = os.path.join(temp, f'new{t}.wav')
                make_new_audio(temp_file, new_file, chunks, log, fps, progress)

                if not os.path.isfile(new_file):
                    log.error('Audio file not created.')

        video_stuff = []

        if rules['allow_video']:
            from auto_editor.render.video import render_av
            for v, vid in enumerate(inp.video_streams):
                if vid['codec'] in ('png', 'jpeg'):
                    video_stuff.append(('image', None, None))
                else:
                    video_stuff.append(render_av(ffmpeg, v, inp, args, chunks, fps,
                        progress, obj_sheet, rules, temp, log))

        log.conwrite('Writing output file')

        mux_quality_media(
            ffmpeg, video_stuff, rules, output_path, output_container, args, inp, temp, log
        )

    if args.export == 'clip-sequence':
        total_frames = chunks[-1][1]
        clip_num = 0
        for chunk in chunks:
            if chunk[2] == 99999:
                continue
            make_media(inp, pad_chunk(chunk, total_frames),
                append_filename(output_path, f'-{clip_num}'))
            clip_num += 1
    else:
        make_media(inp, chunks, output_path)
    return num_cuts, output_path
