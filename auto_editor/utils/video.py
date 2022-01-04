'''utils/video.py'''

# Internal Libraries
import os.path

# Included Libraries
from .func import fnone

def fset(cmd, option, value):
    if(fnone(value)):
        return cmd
    return cmd + [option] + [value]


def get_vcodec(args, inp, rules):
    vcodec = args.video_codec
    if(vcodec == 'auto'):
        vcodec = inp.video_streams[0]['codec']

        if((rules['vstrict'] and vcodec not in rules['vcodecs'])
            or (vcodec in rules['disallow_v'])):
            return rules['vcodecs'][0]

    if(vcodec == 'copy'):
        return inp.video_streams[0]['codec']

    if(vcodec == 'uncompressed'):
        return 'mpeg4'
    return vcodec

def get_acodec(args, inp, rules):
    acodec = args.audio_codec
    if(acodec == 'auto'):
        acodec = inp.audio_streams[0]['codec']

        if((rules['astrict'] and acodec not in rules['acodecs'])
            or (acodec in rules['disallow_a'])):
            return rules['acodecs'][0]

    if(acodec == 'copy'):
        return inp.audio_streams[0]['codec']
    return acodec

def video_quality(cmd, args, inp, rules):
    cmd = fset(cmd, '-crf', args.constant_rate_factor)
    cmd = fset(cmd, '-b:v', args.video_bitrate)
    cmd = fset(cmd, '-tune', args.tune)
    cmd = fset(cmd, '-preset', args.preset)

    qscale = args.video_quality_scale

    if(args.video_codec == 'uncompressed' and fnone(qscale)):
        qscale = '1'

    vcodec = get_vcodec(args, inp, rules)

    cmd.extend(['-c:v', vcodec])

    cmd = fset(cmd, '-qscale:v', qscale)

    cmd.extend(['-movflags', 'faststart'])
    return cmd


def mux_quality_media(ffmpeg, video_stuff, rules, write_file, container, args, inp,
    temp, log):
    s_tracks = 0 if not rules['allow_subtitle'] else len(inp.subtitle_streams)
    a_tracks = 0 if not rules['allow_audio'] else len(inp.audio_streams)
    v_tracks = 0
    cmd = ['-hide_banner', '-y', '-i', inp.path]

    for _, spedup, _ in video_stuff:
        if(spedup is not None):
            cmd.extend(['-i', spedup])
            v_tracks += 1

    if(a_tracks > 0):
        if(args.keep_tracks_seperate and rules['max_audio_streams'] is None):
            for t in range(a_tracks):
                cmd.extend(['-i', os.path.join(temp, f'new{t}.wav')])
        else:
            # Merge all the audio a_tracks into one.
            new_a_file = os.path.join(temp, 'new_audio.wav')
            if(a_tracks > 1):
                new_cmd = []
                for t in range(a_tracks):
                    new_cmd.extend(['-i', os.path.join(temp, f'new{t}.wav')])
                new_cmd.extend(['-filter_complex', f'amerge=inputs={a_tracks}', '-ac',
                    '2', new_a_file])
                ffmpeg.run(new_cmd)
                a_tracks = 1
            else:
                new_a_file = os.path.join(temp, 'new0.wav')
            cmd.extend(['-i', new_a_file])

    if(s_tracks > 0):
        for s, sub in enumerate(inp.subtitle_streams):
            new_path = os.path.join(temp, 'new{}s.{}'.format(s, sub['ext']))
            cmd.extend(['-i', new_path])

    total_streams = v_tracks + s_tracks + a_tracks

    for i in range(total_streams):
        cmd.extend(['-map', f'{i+1}:0'])

    # Copy lang metadata
    streams = (
        (inp.video_streams, 'v', v_tracks),
        (inp.audio_streams, 'a', a_tracks),
        (inp.subtitle_streams, 's', s_tracks),
    )

    for stream, marker, max_streams in streams:
        for i, track in enumerate(stream):
            if(i > max_streams):
                break
            if(track['lang'] is not None):
                cmd.extend([f'-metadata:s:{marker}:{i}', f'language={track["lang"]}'])

    for video_type, _, apply_video in video_stuff:
        if(video_type == 'video'):
            if(apply_video):
                cmd = video_quality(cmd, args, inp, rules)
            else:
                cmd.extend(['-c:v', 'copy'])
            break

    if(s_tracks > 0):
        scodec = inp.subtitle_streams[0]['codec']
        if(inp.ext == '.' + container):
            cmd.extend(['-c:s', scodec])
        elif(rules['scodecs'] is not None):
            if(scodec not in rules['scodecs']):
                scodec = rules['scodecs'][0]
            cmd.extend(['-c:s', scodec])

    if(a_tracks > 0):
        acodec = get_acodec(args, inp, rules)

        cmd = fset(cmd, '-c:a', acodec)
        cmd = fset(cmd, '-b:a', args.audio_bitrate)

        if(fnone(args.sample_rate)):
            if(rules['samplerate'] is not None):
                cmd.extend(['-ar', str(rules['samplerate'][0])])
        else:
            cmd.extend(['-ar', str(args.sample_rate)])

    cmd.extend(['-strict', '-2']) # Allow experimental codecs.
    cmd.extend(['-map', '0:t?', '-map', '0:d?']) # Add input attachments and data to output.
    cmd.append(write_file)
    ffmpeg.run_check_errors(cmd, log)
