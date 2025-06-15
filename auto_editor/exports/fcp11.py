import xml.etree.ElementTree as ET
from fractions import Fraction
from xml.etree.ElementTree import Element, ElementTree, SubElement, indent

from auto_editor.ffwrapper import FileInfo
from auto_editor.timeline import Clip, v3
from auto_editor.utils.log import Log

"""
Export a FCPXML 11 file readable with Final Cut Pro 10.6.8 or later.

See docs here:
https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference

"""


def get_colorspace(src: FileInfo) -> str:
    # See: https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/asset#3686496

    if not src.videos:
        return "1-1-1 (Rec. 709)"

    s = src.videos[0]
    if s.pix_fmt == "rgb24":
        return "sRGB IEC61966-2.1"
    if s.color_space == 5:  # "bt470bg"
        return "5-1-6 (Rec. 601 PAL)"
    if s.color_space == 6:  # "smpte170m"
        return "6-1-6 (Rec. 601 NTSC)"
    if s.color_primaries == 9:  # "bt2020"
        # See: https://video.stackexchange.com/questions/22059/how-to-identify-hdr-video
        if s.color_transfer in {16, 18}:  # "smpte2084" "arib-std-b67"
            return "9-18-9 (Rec. 2020 HLG)"
        return "9-1-9 (Rec. 2020)"

    return "1-1-1 (Rec. 709)"


def make_name(src: FileInfo, tb: Fraction) -> str:
    if src.get_res()[1] == 720 and tb == 30:
        return "FFVideoFormat720p30"
    if src.get_res()[1] == 720 and tb == 25:
        return "FFVideoFormat720p25"
    return "FFVideoFormatRateUndefined"


def parseSMPTE(val: str, fps: Fraction, log: Log) -> int:
    if len(val) == 0:
        return 0
    try:
        parts = val.split(":")
        if len(parts) != 4:
            raise ValueError(f"Invalid SMPTE format: {val}")

        hours, minutes, seconds, frames = map(int, parts)

        if (
            hours < 0
            or minutes < 0
            or minutes >= 60
            or seconds < 0
            or seconds >= 60
            or frames < 0
        ):
            raise ValueError(f"Invalid SMPTE values: {val}")

        if frames >= fps:
            raise ValueError(f"Frame count {frames} exceeds fps {fps}")

        total_frames = (hours * 3600 + minutes * 60 + seconds) * fps + frames
        return int(round(total_frames))
    except (ValueError, ZeroDivisionError) as e:
        log.error(f"Cannot parse SMPTE timecode '{val}': {e}")


def fcp11_write_xml(
    group_name: str, version: int, output: str, resolve: bool, tl: v3, log: Log
) -> None:
    def fraction(val: int) -> str:
        if val == 0:
            return "0s"
        return f"{val * tl.tb.denominator}/{tl.tb.numerator}s"

    if version == 11:
        ver_str = "1.11"
    elif version == 10:
        ver_str = "1.10"
    else:
        log.error(f"Unknown final cut pro version: {version}")

    fcpxml = Element("fcpxml", version=ver_str)
    resources = SubElement(fcpxml, "resources")

    src_dur = 0
    tl_dur = 0 if resolve else len(tl)

    for i, one_src in enumerate(tl.unique_sources()):
        if i == 0:
            proj_name = one_src.path.stem
            src_dur = int(one_src.duration * tl.tb)
            if resolve:
                tl_dur = src_dur

        SubElement(
            resources,
            "format",
            id=f"r{i * 2 + 1}",
            name=make_name(one_src, tl.tb),
            frameDuration=fraction(1),
            width=f"{tl.res[0]}",
            height=f"{tl.res[1]}",
            colorSpace=get_colorspace(one_src),
        )

        startPoint = parseSMPTE(one_src.timecode, tl.tb, log)
        r2 = SubElement(
            resources,
            "asset",
            id=f"r{i * 2 + 2}",
            name=one_src.path.stem,
            start=fraction(startPoint),
            hasVideo="1" if one_src.videos else "0",
            format=f"r{i * 2 + 1}",
            hasAudio="1" if one_src.audios else "0",
            audioSources="1",
            audioChannels=f"{2 if not one_src.audios else one_src.audios[0].channels}",
            duration=fraction(tl_dur),
        )
        SubElement(
            r2, "media-rep", kind="original-media", src=one_src.path.resolve().as_uri()
        )

    lib = SubElement(fcpxml, "library")
    evt = SubElement(lib, "event", name=group_name)
    proj = SubElement(evt, "project", name=proj_name)
    sequence = SubElement(
        proj,
        "sequence",
        format="r1",
        tcStart="0s",
        tcFormat="NDF",
        audioLayout=tl.T.layout,
        audioRate="44.1k" if tl.sr == 44100 else "48k",
    )
    spine = SubElement(sequence, "spine")

    def make_clip(ref: str, clip: Clip) -> None:
        startPoint = parseSMPTE(clip.src.timecode, tl.tb, log)

        clip_properties = {
            "name": proj_name,
            "ref": ref,
            "offset": fraction(clip.start + startPoint),
            "duration": fraction(clip.dur),
            "start": fraction(clip.offset + startPoint),
            "tcFormat": "NDF",
        }
        asset = SubElement(spine, "asset-clip", clip_properties)
        if clip.speed != 1:
            # See the "Time Maps" section.
            # https://developer.apple.com/documentation/professional_video_applications/fcpxml_reference/story_elements/timemap/

            timemap = SubElement(asset, "timeMap")
            SubElement(timemap, "timept", time="0s", value="0s", interp="smooth2")
            SubElement(
                timemap,
                "timept",
                time=fraction(int(src_dur // clip.speed)),
                value=fraction(src_dur),
                interp="smooth2",
            )

    if tl.v and tl.v[0]:
        clips = [clip for clip in tl.v[0] if isinstance(clip, Clip)]
    elif tl.a and tl.a[0]:
        clips = tl.a[0]
    else:
        clips = []

    all_refs: list[str] = ["r2"]
    if resolve:
        for i in range(1, len(tl.a)):
            all_refs.append(f"r{(i + 1) * 2}")

    for my_ref in reversed(all_refs):
        for clip in clips:
            make_clip(my_ref, clip)

    tree = ElementTree(fcpxml)
    indent(tree, space="\t", level=0)
    if output == "-":
        print(ET.tostring(fcpxml, encoding="unicode"))
    else:
        tree.write(output, xml_declaration=True, encoding="utf-8")
