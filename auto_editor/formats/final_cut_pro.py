"""
Export a FCPXML 9 file readable with Final Cut Pro 10.4.9 or later.

See docs here:
https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference

"""

from platform import system
from pathlib import Path, PureWindowsPath

from typing import List, Tuple, Union

from .utils import indent
from auto_editor.ffwrapper import FileInfo


def fcp_xml(inp: FileInfo, output: str, chunks: List[Tuple[int, int, float]]) -> None:
    total_dur = chunks[-1][1]

    if system() == "Windows":
        pathurl = "file://localhost/" + PureWindowsPath(inp.abspath).as_posix()
    else:
        pathurl = Path(inp.abspath).as_uri()

    def fraction(_a: Union[int, float], _fps: float) -> str:
        from fractions import Fraction

        if _a == 0:
            return "0s"

        if isinstance(_a, float):
            a = Fraction(_a)
        else:
            a = _a

        fps = Fraction(_fps)

        frac = Fraction(a, fps).limit_denominator()
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

    width, height = inp.gwidth, inp.gheight
    frame_duration = fraction(1, inp.gfps)

    audio_file = len(inp.videos) == 0 and len(inp.audios) > 0
    group_name = "Auto-Editor {} Group".format("Audio" if audio_file else "Video")
    name = inp.basename

    with open(output, "w", encoding="utf-8") as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        outfile.write("<!DOCTYPE fcpxml>\n\n")
        outfile.write('<fcpxml version="1.9">\n')
        outfile.write("\t<resources>\n")
        outfile.write(
            f'\t\t<format id="r1" name="FFVideoFormat{height}p{inp.gfps}" '
            f'frameDuration="{frame_duration}" '
            f'width="{width}" height="{height}" '
            'colorSpace="1-1-1 (Rec. 709)"/>\n'
        )
        outfile.write(
            f'\t\t<asset id="r2" name="{name}" start="0s" hasVideo="1" format="r1" hasAudio="1" audioSources="1" audioChannels="2" duration="{fraction(total_dur, inp.gfps)}">\n'
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
            dur = fraction(clip_dur, inp.gfps)

            close = "/" if clip[2] == 1 else ""

            if last_dur == 0:
                outfile.write(
                    indent(
                        6,
                        f'<asset-clip name="{name}" offset="0s" ref="r2" duration="{dur}" tcFormat="NDF"{close}>',
                    )
                )
            else:
                start = fraction(clip[0] / clip[2], inp.gfps)
                off = fraction(last_dur, inp.gfps)
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

                frac_total = fraction(total_dur, inp.gfps)
                speed_dur = fraction(total_dur / clip[2], inp.gfps)

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
