'''shotcut.py'''

from auto_editor.formats.utils import get_width_height
from auto_editor.usefulFunctions import aspect_ratio

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
    return round((h * 360 + m * 60 + s) * fps)

def shotcut_xml(inp, temp, output, clips, chunks, fps, log):
    width, height = get_width_height(inp)
    num, den = aspect_ratio(int(width), int(height))

    global_out = inp.duration

    version = '21.05.18'

    print('\n')
    print(clips)

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

        for i, clip in enumerate(clips):
            _out = frames_to_timecode(clip[1], fps)
            out.write('\t<chain id="chain{}" out="{}">\n'.format(i, _out))

            length = frames_to_timecode(clip[1] + 1, fps)
            out.write('\t\t<property name="length">{}</property>\n'.format(length))
            out.write('\t\t<property name="eof">pause</property>\n')
            out.write('\t\t<property name="resource">{}</property>\n'.format(inp.abspath))
            out.write('\t\t<property name="mlt_service">avformat-novalidate</property>\n')
            out.write('\t\t<property name="seekable">1</property>\n')
            out.write('\t\t<property name="audio_index">1</property>\n')
            out.write('\t\t<property name="video_index">0</property>\n')
            out.write('\t\t<property name="mute_on_pause">0</property>\n')
            out.write('\t\t<property name="ignore_points">0</property>\n')
            out.write('\t\t<property name="shotcut:caption">{}</property>\n'.format(inp.basename))
            out.write('\t\t<property name="xml">was here</property>\n')
            out.write('\t</chain>\n')

        out.write('\t<playlist id="playlist0">\n')
        out.write('\t\t<property name="shotcut:video">1</property>\n')
        out.write('\t\t<property name="shotcut:name">V1</property>\n')
        for i, clip in enumerate(clips):
            _in = frames_to_timecode(clip[0], fps)
            _out = frames_to_timecode(clip[1], fps)
            out.write('\t\t<entry producer="chain{}" in="{}" out="{}"/>\n'.format(
                i, _in, _out))

        out.write('\t</playlist>\n')

        out.write('\t<tractor id="tractor0" title="Shotcut version {}" '.format(version) +
            'in="00:00:00.000" out="{}">\n'.format(global_out))
        out.write('\t\t<property name="shotcut">1</property>\n')
        out.write('\t\t<property name="shotcut:projectAudioChannels">2</property>\n')
        out.write('\t\t<property name="shotcut:projectFolder">0</property>\n')
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
