from typing import List, Tuple, Union

from auto_editor.ffwrapper import FileInfo
from auto_editor.utils.func import aspect_ratio


def frames_to_timecode(frames: Union[int, float], fps: float) -> str:
    seconds = frames / fps

    m, _s = divmod(seconds, 60)
    h, m = divmod(m, 60)

    if len(str(int(_s))) == 1:
        s = f"0{round(_s, 3):.3f}"
    else:
        s = f"{round(_s, 3):.3f}"

    return f"{int(h):02d}:{int(m):02d}:{s}"


def timecode_to_frames(timecode: str, fps: float) -> int:
    _h, _m, _s = timecode.split(":")
    h = int(_h)
    m = int(_m)
    s = float(_s)
    return round((h * 3600 + m * 60 + s) * fps)


def shotcut_xml(
    inp: FileInfo,
    output: str,
    chunks: List[Tuple[int, int, float]],
) -> None:
    width, height = inp.gwidth, inp.gheight
    num, den = aspect_ratio(width, height)

    global_out = inp.duration

    version = "21.05.18"

    with open(output, "w", encoding="utf-8") as out:
        out.write('<?xml version="1.0" standalone="no"?>\n')
        out.write(
            '<mlt LC_NUMERIC="C" version="7.1.0" '
            + f'title="Shotcut version {version}" '
            + 'producer="main_bin">\n'
        )
        out.write(
            '\t<profile description="automatic" '
            + f'width="{width}" height="{height}" '
            + 'progressive="1" sample_aspect_num="1" sample_aspect_den="1" '
            + f'display_aspect_num="{num}" display_aspect_den="{den}" '
            + f'frame_rate_num="{inp.gfps}" frame_rate_den="1" colorspace="709"/>\n'
        )
        out.write('\t<playlist id="main_bin">\n')
        out.write('\t\t<property name="xml_retain">1</property>\n')
        out.write("\t</playlist>\n")

        # out was the new video length in the original xml
        out.write(f'\t<producer id="black" in="00:00:00.000" out="{global_out}">\n')
        out.write(f'\t\t<property name="length">{global_out}</property>\n')
        out.write('\t\t<property name="eof">pause</property>\n')
        out.write('\t\t<property name="resource">0</property>\n')
        out.write('\t\t<property name="aspect_ratio">1</property>\n')
        out.write('\t\t<property name="mlt_service">color</property>\n')
        out.write('\t\t<property name="mlt_image_format">rgba</property>\n')
        out.write('\t\t<property name="set.test_audio">0</property>\n')
        out.write("\t</producer>\n")

        out.write('\t<playlist id="background">\n')  # same for this out too.
        out.write(
            f'\t\t<entry producer="black" in="00:00:00.000" out="{global_out}"/>\n'
        )
        out.write("\t</playlist>\n")

        chains = 0
        producers = 0

        # Speeds like [1.5, 3] don't work because of duration issues, too bad!

        for clip in chunks:
            if clip[2] == 99999:
                continue

            speed = clip[2]

            _out = frames_to_timecode(clip[1] / speed, inp.gfps)
            length = frames_to_timecode((clip[1] / speed) + 1, inp.gfps)

            if speed == 1:
                resource = inp.path
                caption = inp.basename
                out.write(f'\t<chain id="chain{chains}" out="{_out}">\n')
                chains += 1
            else:
                resource = f"{speed}:{inp.path}"
                caption = f"{inp.basename} ({speed}x)"
                out.write(
                    '\t<producer id="producer{}" in="00:00:00.000" out="{}">\n'.format(
                        producers, _out
                    )
                )
                producers += 1
                chains += 1  # yes, Shotcut does this.

            out.write(f'\t\t<property name="length">{length}</property>\n')
            out.write('\t\t<property name="eof">pause</property>\n')
            out.write(f'\t\t<property name="resource">{resource}</property>\n')

            if speed == 1:
                out.write(
                    '\t\t<property name="mlt_service">avformat-novalidate</property>\n'
                )
                out.write('\t\t<property name="seekable">1</property>\n')
                out.write('\t\t<property name="audio_index">1</property>\n')
                out.write('\t\t<property name="video_index">0</property>\n')
                out.write('\t\t<property name="mute_on_pause">0</property>\n')
                out.write(
                    f'\t\t<property name="shotcut:caption">{caption}</property>\n'
                )
                out.write('\t\t<property name="xml">was here</property>\n')
            else:
                out.write('\t\t<property name="aspect_ratio">1</property>\n')
                out.write('\t\t<property name="seekable">1</property>\n')
                out.write('\t\t<property name="audio_index">1</property>\n')
                out.write('\t\t<property name="video_index">0</property>\n')
                out.write('\t\t<property name="mute_on_pause">1</property>\n')
                out.write(f'\t\t<property name="warp_speed">{speed}</property>\n')
                out.write(f'\t\t<property name="warp_resource">{inp.path}</property>\n')
                out.write('\t\t<property name="mlt_service">timewarp</property>\n')
                out.write('\t\t<property name="shotcut:producer">avformat</property>\n')
                out.write('\t\t<property name="video_delay">0</property>\n')
                out.write(
                    f'\t\t<property name="shotcut:caption">{caption}</property>\n'
                )
                out.write('\t\t<property name="xml">was here</property>\n')
                out.write('\t\t<property name="warp_pitch">1</property>\n')

            out.write("\t</chain>\n" if speed == 1 else "\t</producer>\n")

        out.write('\t<playlist id="playlist0">\n')
        out.write('\t\t<property name="shotcut:video">1</property>\n')
        out.write('\t\t<property name="shotcut:name">V1</property>\n')

        producers = 0
        i = 0
        for clip in chunks:
            if clip[2] == 99999:
                continue

            speed = clip[2]

            if speed == 1:
                in_len: float = clip[0] - 1
            else:
                in_len = max(clip[0] / speed, 0)

            out_len = max((clip[1] - 2) / speed, 0)

            _in = frames_to_timecode(in_len, inp.gfps)
            _out = frames_to_timecode(out_len, inp.gfps)

            tag_name = f"chain{i}"
            if speed != 1:
                tag_name = f"producer{producers}"
                producers += 1

            out.write(f'\t\t<entry producer="{tag_name}" in="{_in}" out="{_out}"/>\n')
            i += 1

        out.write("\t</playlist>\n")

        out.write(
            f'\t<tractor id="tractor0" title="Shotcut version {version}" '
            + f'in="00:00:00.000" out="{global_out}">\n'
        )
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
        out.write("\t\t</transition>\n")
        out.write('\t\t<transition id="transition1">\n')
        out.write('\t\t\t<property name="a_track">0</property>\n')
        out.write('\t\t\t<property name="b_track">1</property>\n')
        out.write('\t\t\t<property name="version">0.9</property>\n')
        out.write('\t\t\t<property name="mlt_service">frei0r.cairoblend</property>\n')
        out.write('\t\t\t<property name="threads">0</property>\n')
        out.write('\t\t\t<property name="disable">1</property>\n')
        out.write("\t\t</transition>\n")

        out.write("\t</tractor>\n")
        out.write("</mlt>\n")
