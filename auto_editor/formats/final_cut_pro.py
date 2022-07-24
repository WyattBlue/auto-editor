from __future__ import annotations

from fractions import Fraction
from pathlib import Path, PureWindowsPath
from platform import system

from auto_editor.ffwrapper import FileInfo
from auto_editor.timeline import Timeline

from .utils import indent

"""
Export a FCPXML 9 file readable with Final Cut Pro 10.4.9 or later.

See docs here:
https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference

"""


def get_colorspace(inp: FileInfo) -> str:
    # See: https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/asset#3686496

    if len(inp.videos) == 0:
        return "1-1-1 (Rec. 709)"

    s = inp.videos[0]
    if s.pix_fmt == "rgb24":
        return "sRGB IEC61966-2.1"
    if s.color_space == "smpte170m":
        return "6-1-6 (Rec. 601 NTSC)"
    if s.color_space == "bt470bg":
        return "5-1-6 (Rec. 601 PAL)"
    if s.color_primaries == "bt2020":
        # See: https://video.stackexchange.com/questions/22059/how-to-identify-hdr-video
        if s.color_transfer in ("arib-std-b67", "smpte2084"):
            return "9-18-9 (Rec. 2020 HLG)"
        return "9-1-9 (Rec. 2020)"

    return "1-1-1 (Rec. 709)"


def fraction(_a: int | float, tb: Fraction) -> str:
    if _a == 0:
        return "0s"

    if isinstance(_a, float):
        a = Fraction(_a)
    else:
        a = _a

    frac = Fraction(a, tb).limit_denominator()
    num = frac.numerator
    dem = frac.denominator

    if dem < 3000:
        factor = int(3000 / dem)

        if factor == 3000 / dem:
            num *= factor
            dem *= factor
        else:
            # Good enough but has some error that are impacted at speeds such as 150%.
            total = Fraction(0)
            while total < frac:
                total += Fraction(1, 30)
            num = total.numerator
            dem = total.denominator

    return f"{num}/{dem}s"


def fcp_xml(output: str, timeline: Timeline) -> None:
    inp = timeline.inp
    tb = timeline.timebase
    chunks = timeline.chunks

    if chunks is None:
        raise ValueError("Timeline too complex")

    total_dur = chunks[-1][1]

    if system() == "Windows":
        pathurl = "file://localhost/" + PureWindowsPath(inp.abspath).as_posix()
    else:
        pathurl = Path(inp.abspath).as_uri()

    width, height = timeline.res
    frame_duration = fraction(1, tb)

    audio_file = len(inp.videos) == 0 and len(inp.audios) > 0
    group_name = "Auto-Editor {} Group".format("Audio" if audio_file else "Video")
    name = inp.basename

    colorspace = get_colorspace(inp)

    with open(output, "w", encoding="utf-8") as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        outfile.write("<!DOCTYPE fcpxml>\n\n")
        outfile.write('<fcpxml version="1.9">\n')
        outfile.write("\t<resources>\n")
        outfile.write(
            f'\t\t<format id="r1" name="FFVideoFormat{height}p{float(tb)}" '
            f'frameDuration="{frame_duration}" '
            f'width="{width}" height="{height}" '
            f'colorSpace="{colorspace}"/>\n'
        )
        outfile.write(
            f'\t\t<asset id="r2" name="{name}" start="0s" hasVideo="1" format="r1" '
            'hasAudio="1" audioSources="1" audioChannels="2" '
            f'duration="{fraction(total_dur, tb)}">\n'
        )
        outfile.write(
            f'\t\t\t<media-rep kind="original-media" src="{pathurl}"></media-rep>\n'
        )
        outfile.write("\t\t</asset>\n")
        outfile.write("\t</resources>\n")
        outfile.write("\t<library>\n")
        outfile.write(f'\t\t<event name="{group_name}">\n')
        outfile.write(f'\t\t\t<project name="{name}">\n')
        outfile.write(
            indent(
                4,
                '<sequence format="r1" tcStart="0s" tcFormat="NDF" audioLayout="stereo" audioRate="48k">',
                "\t<spine>",
            )
        )

        last_dur = 0.0
        for clip in chunks:
            if clip[2] == 99999:
                continue

            clip_dur = (clip[1] - clip[0] + 1) / clip[2]
            dur = fraction(clip_dur, tb)

            close = "/" if clip[2] == 1 else ""

            if last_dur == 0:
                outfile.write(
                    indent(
                        6,
                        f'<asset-clip name="{name}" offset="0s" ref="r2" duration="{dur}" tcFormat="NDF"{close}>',
                    )
                )
            else:
                start = fraction(clip[0] / clip[2], tb)
                off = fraction(last_dur, tb)
                outfile.write(
                    indent(
                        6,
                        f'<asset-clip name="{name}" offset="{off}" ref="r2" '
                        + f'duration="{dur}" start="{start}" '
                        + f'tcFormat="NDF"{close}>',
                    )
                )

            if clip[2] != 1:
                # See the "Time Maps" section.
                # https://developer.apple.com/library/archive/documentation/FinalCutProX/Reference/FinalCutProXXMLFormat/StoryElements/StoryElements.html

                frac_total = fraction(total_dur, tb)
                speed_dur = fraction(total_dur / clip[2], tb)

                outfile.write(
                    indent(
                        6,
                        "\t<timeMap>",
                        '\t\t<timept time="0s" value="0s" interp="smooth2"/>',
                        f'\t\t<timept time="{speed_dur}" value="{frac_total}" interp="smooth2"/>',
                        "\t</timeMap>",
                        "</asset-clip>",
                    )
                )

            last_dur += clip_dur

        outfile.write("\t\t\t\t\t</spine>\n")
        outfile.write("\t\t\t\t</sequence>\n")
        outfile.write("\t\t\t</project>\n")
        outfile.write("\t\t</event>\n")
        outfile.write("\t</library>\n")
        outfile.write("</fcpxml>\n")
