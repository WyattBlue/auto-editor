'''edit.py'''

# Internal Libraries
import os
from typing import List, Tuple

import numpy as np

from auto_editor.utils.effects import Effect
from auto_editor.utils.log import Log
from auto_editor.utils.func import fnone, set_output_name, append_filename

def get_chunks(inp, segment, fps, args, log, audio_samples=None, sample_rate=None):
    from auto_editor.cutting import (combine_audio_motion, combine_segment, to_speed_list,
        set_range, chunkify, apply_mark_as, apply_margin, seconds_to_frames, cook)

    start_margin, end_margin = args.frame_margin

    start_margin = seconds_to_frames(start_margin, fps)
    end_margin = seconds_to_frames(end_margin, fps)
    min_clip = seconds_to_frames(args.min_clip_length, fps)
    min_cut = seconds_to_frames(args.min_cut_length, fps)

    def get_has_loud(inp, args, fps, audio_samples, sample_rate, log):
        # type: (...) -> np.ndarray
        from auto_editor.analyze.generic import get_np_list

        if(args.edit_based_on == 'none'):
            return get_np_list(inp, audio_samples, sample_rate, fps, np.ones)
        if(args.edit_based_on == 'all'):
            return get_np_list(inp, audio_samples, sample_rate, fps, np.zeros)

        audio_list, motion_list = None, None

        if('audio' in args.edit_based_on):
            from auto_editor.analyze.audio import audio_detection

            if(audio_samples is None):
                audio_list = get_np_list(inp, audio_samples, sample_rate, fps, np.ones)
            else:
                audio_list = audio_detection(audio_samples, sample_rate,
                    args.silent_threshold, fps, log)

        if('motion' in args.edit_based_on):
            from auto_editor.analyze.motion import motion_detection

            if(len(inp.video_streams) == 0):
                motion_list = get_np_list(inp, audio_samples, sample_rate, fps, np.ones)
            else:
                motion_list = motion_detection(inp, args.motion_threshold, log,
                    width=args.md_width, dilates=args.md_dilates, blur=args.md_blur)

        if(audio_list is not None and motion_list is not None):
            if(len(audio_list) > len(motion_list)):
                audio_list = audio_list[:len(motion_list)]
            elif(len(motion_list) > len(audio_list)):
                motion_list = motion_list[:len(audio_list)]

        return combine_audio_motion(audio_list, motion_list, args.edit_based_on, log)

    has_loud = get_has_loud(inp, args, fps, audio_samples, sample_rate, log)
    has_loud_length = len(has_loud)
    has_loud = apply_mark_as(has_loud, has_loud_length, fps, args, log)
    has_loud = cook(has_loud, min_clip, min_cut)
    has_loud = apply_margin(has_loud, has_loud_length, start_margin, end_margin)

    if(segment is not None):
        has_loud = combine_segment(has_loud, segment, fps)

    # Remove small clips/cuts created by applying other rules.
    has_loud = cook(has_loud, min_clip, min_cut)

    speed_list = to_speed_list(has_loud, args.video_speed, args.silent_speed)

    if(args.cut_out != []):
        speed_list = set_range(speed_list, args.cut_out, fps, 99999, log)

    if(args.add_in != []):
        speed_list = set_range(speed_list, args.add_in, fps, args.video_speed, log)

    if(args.set_speed_for_range != []):
        for item in args.set_speed_for_range:
            speed_list = set_range(speed_list, [item[1:]], fps, item[0], log)

    return chunkify(speed_list, has_loud_length)


def edit_media(i, inp, ffmpeg, args, progress, segment, exporting_to_editor, data_file,
    temp, log):
    from auto_editor.utils.container import get_rules

    chunks = None
    if(inp.ext == '.json'):
        from auto_editor.formats.make_json import read_json_cutlist

        input_path, chunks = read_json_cutlist(inp.path, log)
        inp = ffmpeg.file_info(input_path)

        output_path = set_output_name(inp.path, inp.ext, data_file, args)
    else:
        output_path = args.output_file[i]
        if(not os.path.isdir(inp.path) and os.path.splitext(output_path)[1] == ''):
            output_path = set_output_name(output_path, inp.ext, data_file, args)

    log.debug('{} -> {}'.format(inp.path, output_path))

    output_container = os.path.splitext(output_path)[1].replace('.', '')

    # Check if export options make sense.
    rules = get_rules(output_container)
    codec_error = "'{}' codec is not supported in '{}' container."

    if(not fnone(args.sample_rate)):
        if(rules['samplerate'] is not None and args.sample_rate not in rules['samplerate']):
            log.error("'{}' container only supports samplerates: {}".format(output_container,
                rules['samplerate']))

    vcodec = args.video_codec
    if(vcodec == 'uncompressed'):
        vcodec = 'mpeg4'
    if(vcodec == 'copy'):
        vcodec = inp.video_streams[0]['codec']

    if(vcodec != 'auto'):
        if(rules['vstrict'] and vcodec not in rules['vcodecs']):
            log.error(codec_error.format(vcodec, output_container))

        if(vcodec in rules['disallow_v']):
            log.error(codec_error.format(vcodec, output_container))

    acodec = args.audio_codec
    if(acodec == 'copy'):
        acodec = inp.audio_streams[0]['codec']
        log.debug(f'Settings acodec to {acodec}')

    if(acodec not in ['unset', 'auto']):
        if(rules['astrict'] and acodec not in rules['acodecs']):
            log.error(codec_error.format(acodec, output_container))

        if(acodec in rules['disallow_a']):
            log.error(codec_error.format(acodec, output_container))

    if(args.keep_tracks_seperate and rules['max_audio_streams'] == 1):
        log.warning(
            "'{}' container doesn't support multiple audio tracks.".format(container)
        )

    if(os.path.isfile(output_path) and inp.path != output_path and not args.preview
        and not args.timeline):
        log.debug('Removing already existing file: {}'.format(output_path))
        os.remove(output_path)

    audio_samples = None
    tracks = len(inp.audio_streams)
    audio_file = len(inp.video_streams) == 0 and tracks == 1

    if(inp.fps is None):
        fps = 30
    elif(exporting_to_editor):
        fps = int(float(inp.fps))
    else:
        fps = float(inp.fps)

    if(fps < 1):
        log.error('{}: Frame rate cannot be below 1. fps: {}'.format(inp.basename, fps))

    # Extract subtitles in their native format.
    if(len(inp.subtitle_streams) > 0):
        cmd = ['-i', inp.path, '-hide_banner']
        for s, sub in enumerate(inp.subtitle_streams):
            cmd.extend(['-map', '0:s:{}'.format(s)])
        for s, sub in enumerate(inp.subtitle_streams):
            cmd.extend([os.path.join(temp, '{}s.{}'.format(s, sub['ext']))])
        ffmpeg.run(cmd)

    sample_rate = None

    if(args.cut_by_this_track >= tracks and 'cut_by_this_track' in args._set):
        message = "You choose a track that doesn't exist.\nThere "
        if(tracks == 1):
            message += 'is only {} track.\n'.format(tracks)
        else:
            message += 'are only {} tracks.\n'.format(tracks)
        for t in range(tracks):
            message += ' Track {}\n'.format(t)
        log.error(message)

    # Split audio tracks into: 0.wav, 1.wav, etc.
    log.conwrite('Extracting audio')

    cmd = ['-i', inp.path, '-hide_banner']
    for t in range(tracks):
        cmd.extend(['-map', '0:a:{}'.format(t), '-ac', '2',
            os.path.join(temp, '{}.wav'.format(t))])
    ffmpeg.run(cmd)
    del cmd

    if(tracks != 0):
        if(args.cut_by_all_tracks):
            temp_file = os.path.join(temp, 'combined.wav')
            cmd = ['-i', inp.path, '-filter_complex',
                '[0:a]amix=inputs={}:duration=longest'.format(tracks), '-ac', '2',
                '-f', 'wav', temp_file]
            ffmpeg.run(cmd)
            del cmd
        else:
            temp_file = os.path.join(temp, '{}.wav'.format(args.cut_by_this_track))

        from auto_editor.scipy.wavfile import read
        sample_rate, audio_samples = read(temp_file)

    if(chunks is None):
        chunks = get_chunks(inp, segment, fps, args, log, audio_samples, sample_rate)

    def is_clip(chunk: Tuple[int, int, float]) -> bool:
        return chunk[2] != 99999

    def number_of_cuts(chunks):
        # type: (List[Tuple[int, int, float]]) -> int
        return len(list(filter(is_clip, chunks)))

    def get_clips(chunks):
        # type: (List[Tuple[int, int, float]]) -> List[Tuple[int, int, float]]
        clips = []
        for chunk in chunks:
            if(is_clip(chunk)):
                clips.append((chunk[0], chunk[1], chunk[2] * 100))
        return clips

    num_cuts = number_of_cuts(chunks)
    clips = get_clips(chunks)

    effects = Effect(args, log, _vars={})

    if(args.export_as_json):
        from auto_editor.formats.make_json import make_json_cutlist
        make_json_cutlist(inp.path, output_path, chunks, log)
        return num_cuts, output_path

    if(args.timeline):
        from auto_editor.formats.make_json import make_json_cutlist
        make_json_cutlist(inp.path, 0, chunks, log)
        return num_cuts, None

    if(args.preview):
        from auto_editor.preview import preview
        preview(inp, chunks, log)
        return num_cuts, None

    if(args.export_to_premiere):
        from auto_editor.formats.premiere import premiere_xml
        premiere_xml(inp, temp, output_path, clips, chunks, sample_rate, audio_file,
            fps, log)
        return num_cuts, output_path

    if(args.export_to_final_cut_pro):
        from auto_editor.formats.final_cut_pro import fcp_xml

        total_frames = chunks[len(chunks) - 1][1]
        fcp_xml(inp, temp, output_path, clips, tracks, total_frames, audio_file, fps, log)
        return num_cuts, output_path

    if(args.export_to_shotcut):
        from auto_editor.formats.shotcut import shotcut_xml

        shotcut_xml(inp, temp, output_path, clips, chunks, fps, log)
        return num_cuts, output_path

    def pad_chunk(item, total_frames):
        start = None
        end = None
        if(item[0] != 0):
            start = [0, item[0], 2]
        if(item[1] != total_frames -1):
            end = [item[1], total_frames -1, 2]

        if(start is None):
            return [item] + [end]
        if(end is None):
            return [start] + [item]
        return [start] + [item] + [end]


    def make_media(inp, chunks, output_path):
        from auto_editor.utils.video import mux_quality_media

        if(rules['allow_subtitle']):
            from auto_editor.render.subtitle import cut_subtitles
            cut_subtitles(ffmpeg, inp, chunks, fps, temp, log)

        if(rules['allow_audio']):
            from auto_editor.render.audio import make_new_audio

            for t in range(tracks):
                temp_file = os.path.join(temp, '{}.wav'.format(t))
                new_file = os.path.join(temp, 'new{}.wav'.format(t))
                make_new_audio(temp_file, new_file, chunks, log, fps, progress)

                if(not os.path.isfile(new_file)):
                    log.bug('Audio file not created.')

        video_stuff = []

        if(rules['allow_video']):
            from auto_editor.render.video import render_av
            for v, vid in enumerate(inp.video_streams):
                if(vid['codec'] in ['png', 'jpeg']):
                    video_stuff.append(('image', None, None))
                else:
                    video_stuff.append(render_av(ffmpeg, v, inp, args, chunks, fps,
                        progress, effects, rules, temp, log))

        log.conwrite('Writing the output file.')

        mux_quality_media(ffmpeg, video_stuff, rules, output_path, output_container,
            args, inp, temp, log)
        if(output_path is not None and not os.path.isfile(output_path)):
            log.bug(f'The file {output_path} was not created.')

    if(args.export_as_clip_sequence):
        total_frames = chunks[-1][1]
        clip_num = 0
        for chunk in chunks:
            if(chunk[2] == 99999):
                continue
            make_media(inp, pad_chunk(chunk, total_frames),
                append_filename(output_path, f'-{clip_num}'))
            clip_num += 1
    else:
        make_media(inp, chunks, output_path)
    return num_cuts, output_path
