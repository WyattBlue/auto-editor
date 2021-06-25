'''formats/shotcut.py'''

from .utils import get_width_height
from auto_editor.utils.func import aspect_ratio

def frames_to_timecode(frames, fps):
    seconds = frames / fps

    m, s = divmod(seconds, 60)
    h, m = divmod(m, 60)

    if(len(str(int(s))) == 1):
        s = '0' + str('{:.3f}'.format(round(s, 3)))
    else:
        s = str('{:.3f}'.format(round(s, 3)))

    return '{:02d}:{:02d}:{}'.format(int(h), int(m), s)

def timecode_to_frames(timecode, fps):
    h, m, s, = timecode.split(':')
    h = int(h)
    m = int(m)
    s = float(s)
    return round((h * 3600 + m * 60 + s) * fps)

def shotcut_xml(inp, temp, output, clips, chunks, fps, log):
    width, height = get_width_height(inp)
    if(width is None or height is None):
        width, height = '1280', '720'
    num, den = aspect_ratio(int(width), int(height))

    global_out = inp.duration

    version = '21.05.18'

    with open(output, 'w', encoding='utf-8') as out:
        out.write('<?xml version="1.0" standalone="no"?>\n')
        out.write('<mlt LC_NUMERIC="C" version="7.1.0" ' +
            'title="Shotcut version {}" '.format(version) +
            'producer="main_bin">\n')
        out.write('\t<profile description="automatic" ' +
            'width="{}" height="{}" '.format(width, height) +
            'progressive="1" sample_aspect_num="1" sample_aspect_den="1" ' +
            'display_aspect_num="{}" display_aspect_den="{}" '.format(num, den) +
            'frame_rate_num="{}" frame_rate_den="1" colorspace="709"/>\n'.format(fps))
        out.write('\t<playlist id="main_bin">\n')
        out.write('\t\t<property name="xml_retain">1</property>\n')
        out.write('\t</playlist>\n')

        # out was the new video length in the original xml
        out.write('\t<producer id="black" in="00:00:00.000" out="{}">\n'.format(global_out))
        out.write('\t\t<property name="length">{}</property>\n'.format(global_out))
        out.write('\t\t<property name="eof">pause</property>\n')
        out.write('\t\t<property name="resource">0</property>\n')
        out.write('\t\t<property name="aspect_ratio">1</property>\n')
        out.write('\t\t<property name="mlt_service">color</property>\n')
        out.write('\t\t<property name="mlt_image_format">rgba</property>\n')
        out.write('\t\t<property name="set.test_audio">0</property>\n')
        out.write('\t</producer>\n')

        out.write('\t<playlist id="background">\n') # same for this out too.
        out.write('\t\t<entry producer="black" in="00:00:00.000" out="{}"/>\n'.format(
            global_out))
        out.write('\t</playlist>\n')

        chains = 0
        producers = 0

        # Speeds like [1.5, 3] don't work because of duration issues, too bad!

        for clip in clips:
            speed = clip[2] / 100
            if(int(speed) == speed):
                speed = int(speed)

            _out = frames_to_timecode(clip[1] / speed, fps)
            length = frames_to_timecode((clip[1] / speed) + 1, fps)

            if(speed == 1):
                resource = inp.path
                caption = inp.basename
                out.write('\t<chain id="chain{}" out="{}">\n'.format(
                    chains, _out))
                chains += 1
            else:
                resource = '{}:{}'.format(speed, inp.path)
                caption = '{} ({}x)'.format(inp.basename, speed)
                out.write('\t<producer id="producer{}" in="00:00:00.000" out="{}">\n'.format(
                    producers, _out))
                producers += 1
                chains += 1 # yes, Shotcut does this.

            out.write('\t\t<property name="length">{}</property>\n'.format(length))
            out.write('\t\t<property name="eof">pause</property>\n')
            out.write('\t\t<property name="resource">{}</property>\n'.format(resource))

            if(speed == 1):
                out.write('\t\t<property name="mlt_service">avformat-novalidate</property>\n')
                out.write('\t\t<property name="seekable">1</property>\n')
                out.write('\t\t<property name="audio_index">1</property>\n')
                out.write('\t\t<property name="video_index">0</property>\n')
                out.write('\t\t<property name="mute_on_pause">0</property>\n')
                out.write('\t\t<property name="shotcut:caption">{}</property>\n'.format(
                    caption))
                out.write('\t\t<property name="xml">was here</property>\n')
            else:
                out.write('\t\t<property name="aspect_ratio">1</property>\n')
                out.write('\t\t<property name="seekable">1</property>\n')
                out.write('\t\t<property name="audio_index">1</property>\n')
                out.write('\t\t<property name="video_index">0</property>\n')
                out.write('\t\t<property name="mute_on_pause">1</property>\n')
                out.write('\t\t<property name="warp_speed">{}</property>\n'.format(speed))
                out.write('\t\t<property name="warp_resource">{}</property>\n'.format(
                    inp.path))
                out.write('\t\t<property name="mlt_service">timewarp</property>\n')
                out.write('\t\t<property name="shotcut:producer">avformat</property>\n')
                out.write('\t\t<property name="video_delay">0</property>\n')
                out.write('\t\t<property name="shotcut:caption">{}</property>\n'.format(caption))
                out.write('\t\t<property name="xml">was here</property>\n')
                out.write('\t\t<property name="warp_pitch">1</property>\n')

            out.write('\t</chain>\n' if speed == 1 else '\t</producer>\n')

        out.write('\t<playlist id="playlist0">\n')
        out.write('\t\t<property name="shotcut:video">1</property>\n')
        out.write('\t\t<property name="shotcut:name">V1</property>\n')

        producers = 0
        for i, clip in enumerate(clips):

            if(speed == 1):
                in_len = clip[0] - 1
            else:
                in_len = max(clip[0] / speed, 0)

            out_len = max((clip[1] - 2) / speed, 0)

            _in = frames_to_timecode(in_len, fps)
            _out = frames_to_timecode(out_len, fps)

            tag_name = 'chain{}'.format(i)
            if(speed != 1):
                tag_name = 'producer{}'.format(producers)
                producers += 1

            out.write('\t\t<entry producer="{}" in="{}" out="{}"/>\n'.format(
                tag_name, _in, _out))

        out.write('\t</playlist>\n')

        out.write('\t<tractor id="tractor0" title="Shotcut version {}" '.format(version) +
            'in="00:00:00.000" out="{}">\n'.format(global_out))
        out.write('\t\t<property name="shotcut">1</property>\n')
        out.write('\t\t<property name="shotcut:projectAudioChannels">2</property>\n')
        out.write('\t\t<property name="shotcut:projectFolder">0</property>\n')
        out.write('\t\t<track producer="background"/>\n')
        out.write('\t\t<track producer="playlist0"/>\n')
        out.write('\t\t<transition id="transition0">\n')
        out.write('\t\t\t<property name="a_track">0</property>\n')
        out.write('\t\t\t<property name="b_track">1</property>\n')
        out.write('\t\t\t<property name="mlt_service">mix</property>\n')
        out.write('\t\t\t<property name="always_active">1</property>\n')
        out.write('\t\t\t<property name="sum">1</property>\n')
        out.write('\t\t</transition>\n')
        out.write('\t\t<transition id="transition1">\n')
        out.write('\t\t\t<property name="a_track">0</property>\n')
        out.write('\t\t\t<property name="b_track">1</property>\n')
        out.write('\t\t\t<property name="version">0.9</property>\n')
        out.write('\t\t\t<property name="mlt_service">frei0r.cairoblend</property>\n')
        out.write('\t\t\t<property name="threads">0</property>\n')
        out.write('\t\t\t<property name="disable">1</property>\n')
        out.write('\t\t</transition>\n')

        out.write('\t</tractor>\n')
        out.write('</mlt>\n')
