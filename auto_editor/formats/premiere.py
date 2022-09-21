from __future__ import annotations

import os.path
import xml.etree.ElementTree as ET
from fractions import Fraction
from os.path import abspath
from pathlib import Path
from shutil import move
from xml.etree.ElementTree import Element

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.make_layers import ASpace, VSpace
from auto_editor.objects import AudioObj, VideoObj
from auto_editor.output import Ensure
from auto_editor.timeline import Timeline
from auto_editor.utils.log import Log

from .utils import indent, safe_mkdir

"""
Premiere Pro uses the Final Cut Pro 7 XML Interchange Format

See docs here:
https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/Elements/Elements.html

Also, Premiere itself will happily output subtlety incorrect XML files that don't
come back the way they started.
"""

PIXEL_ASPECT_RATIO = "square"
COLORDEPTH = "24"
ANAMORPHIC = "FALSE"
DEPTH = "16"


def path_to_uri(path: str) -> str:
    return Path(abspath(path)).as_uri()


def uri_to_path(uri: str) -> str:
    from urllib.parse import urlparse
    from urllib.request import url2pathname

    parsed = urlparse(uri)
    host = "{0}{0}{mnt}{0}".format(os.path.sep, mnt=parsed.netloc)
    return os.path.normpath(os.path.join(host, url2pathname(parsed.path)))

    # /Users/wyattblue/projects/auto-editor/example.mp4
    # file:///Users/wyattblue/projects/auto-editor/example.mp4
    # file://localhost/Users/wyattblue/projects/auto-editor/example.mp4


def speedup(speed: float) -> str:
    return indent(
        6,
        "<filter>",
        "\t<effect>",
        "\t\t<name>Time Remap</name>",
        "\t\t<effectid>timeremap</effectid>",
        "\t\t<effectcategory>motion</effectcategory>",
        "\t\t<effecttype>motion</effecttype>",
        "\t\t<mediatype>video</mediatype>",
        '\t\t<parameter authoringApp="PremierePro">',
        "\t\t\t<parameterid>variablespeed</parameterid>",
        "\t\t\t<name>variablespeed</name>",
        "\t\t\t<valuemin>0</valuemin>",
        "\t\t\t<valuemax>1</valuemax>",
        "\t\t\t<value>0</value>",
        "\t\t</parameter>",
        '\t\t<parameter authoringApp="PremierePro">',
        "\t\t\t<parameterid>speed</parameterid>",
        "\t\t\t<name>speed</name>",
        "\t\t\t<valuemin>-100000</valuemin>",
        "\t\t\t<valuemax>100000</valuemax>",
        f"\t\t\t<value>{speed}</value>",
        "\t\t</parameter>",
        '\t\t<parameter authoringApp="PremierePro">',
        "\t\t\t<parameterid>reverse</parameterid>",
        "\t\t\t<name>reverse</name>",
        "\t\t\t<value>FALSE</value>",
        "\t\t</parameter>",
        '\t\t<parameter authoringApp="PremierePro">',
        "\t\t\t<parameterid>frameblending</parameterid>",
        "\t\t\t<name>frameblending</name>",
        "\t\t\t<value>FALSE</value>",
        "\t\t</parameter>",
        "\t</effect>",
        "</filter>",
    )


def premiere_read_xml(path: str, ffmpeg: FFmpeg, log: Log) -> Timeline:
    def show(ele, limit, depth=0):
        print(
            f"{' ' * (depth * 4)}<{ele.tag} {ele.attrib}> {ele.text.strip() if ele.text is not None else ''}"
        )
        for child in ele:
            if isinstance(child, Element) and depth < limit:
                show(child, limit, depth + 1)

    def xml_bool(val: str) -> bool:
        if val == "TRUE":
            return True
        if val == "FALSE":
            return False
        raise TypeError("Value must be 'TRUE' or 'FALSE'")

    def check(ele: Element, tag: str) -> None:
        if tag != ele.tag:
            log.error(f"Expected '{tag}' tag, got '{ele.tag}'")

    def validate(ele: Element, schema: dict) -> dict:
        new: dict = {}

        for key, val in schema.items():
            if isinstance(val, dict) and "__arr" in val:
                new[key] = []

        is_arr = False
        for child in ele:
            if child.tag not in schema:
                # log.warning(f"Didn't expect '{child.tag}' tag")
                continue

            if schema[child.tag] is None:
                new[child.tag] = child
                continue

            if isinstance(schema[child.tag], dict):
                val = validate(child, schema[child.tag])
                is_arr = "__arr" in schema[child.tag]
            else:
                val = schema[child.tag](child.text)

            if child.tag in new:
                if not is_arr:
                    log.error(f"<{child.tag}> can only occur once")
                new[child.tag].append(val)
            else:
                new[child.tag] = [val] if is_arr else val

        return new

    try:
        tree = ET.parse(path)
    except FileNotFoundError:
        log.error(f"Coud not find file '{path}'")

    root = tree.getroot()

    check(root, "xmeml")
    check(root[0], "sequence")
    result = validate(
        root[0],
        {
            "name": str,
            "duration": int,
            "rate": {
                "timebase": Fraction,
                "ntsc": xml_bool,
            },
            "media": None,
        },
    )

    tb = result["rate"]["timebase"]

    av = validate(
        result["media"],
        {
            "video": None,
            "audio": None,
        },
    )

    sources: dict[int | str, FileInfo] = {}
    vobjs: VSpace = []
    aobjs: ASpace = []

    vclip_schema = {
        "format": {
            "samplecharacteristics": {
                "width": int,
                "height": int,
            },
        },
        "track": {
            "__arr": "",
            "clipitem": {
                "__arr": "",
                "start": int,
                "end": int,
                "in": int,
                "out": int,
                "file": None,
            },
        },
    }

    aclip_schema = {
        "format": {"samplecharacteristics": {"samplerate": int}},
        "track": {
            "__arr": "",
            "clipitem": {
                "__arr": "",
                "start": int,
                "end": int,
                "in": int,
                "out": int,
                "file": None,
            },
        },
    }

    sr = 48000
    res = (1920, 1080)

    if "video" in av:
        tracks = validate(av["video"], vclip_schema)

        width = tracks["format"]["samplecharacteristics"]["width"]
        height = tracks["format"]["samplecharacteristics"]["height"]
        res = width, height

        for t, track in enumerate(tracks["track"]):
            if len(track["clipitem"]) > 0:
                vobjs.append([])
            for i, clipitem in enumerate(track["clipitem"]):
                file_id = clipitem["file"].attrib["id"]
                if file_id not in sources:
                    fileobj = validate(clipitem["file"], {"pathurl": str})
                    sources[file_id] = FileInfo(
                        uri_to_path(fileobj["pathurl"]), len(sources), ffmpeg, log
                    )

                start = clipitem["start"]
                dur = clipitem["end"] - start
                offset = clipitem["in"]

                vobjs[t].append(
                    VideoObj(start, dur, file_id, offset, speed=1, stream=0)
                )

    if "audio" in av:
        tracks = validate(av["audio"], aclip_schema)
        sr = tracks["format"]["samplecharacteristics"]["samplerate"]

        for t, track in enumerate(tracks["track"]):
            if len(track["clipitem"]) > 0:
                aobjs.append([])
            for i, clipitem in enumerate(track["clipitem"]):
                file_id = clipitem["file"].attrib["id"]
                if file_id not in sources:
                    fileobj = validate(clipitem["file"], {"pathurl": str})
                    sources[file_id] = FileInfo(
                        uri_to_path(fileobj["pathurl"]), len(sources), ffmpeg, log
                    )

                start = clipitem["start"]
                dur = clipitem["end"] - start
                offset = clipitem["in"]

                aobjs[t].append(
                    AudioObj(start, dur, file_id, offset, speed=1, volume=1, stream=0)
                )

    timeline = Timeline(sources, tb, sr, res, "#000", vobjs, aobjs, None)
    return timeline


def premiere_write_xml(
    ensure: Ensure,
    output: str,
    timeline: Timeline,
) -> None:

    src = timeline.sources[0]
    chunks = timeline.chunks

    if chunks is None:
        raise ValueError("Timeline too complex")

    fps = timeline.timebase
    samplerate = timeline.samplerate

    audio_file = len(src.videos) == 0 and len(src.audios) == 1

    # See chart: https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/FrameRate/FrameRate.html#//apple_ref/doc/uid/TP30001158-TPXREF103

    if fps == 23.98 or fps == 23.976 or fps == Fraction(24000, 1001):
        timebase = 24
        ntsc = "TRUE"
    elif fps == 29.97 or fps == Fraction(30000, 1001):
        timebase = 30
        ntsc = "TRUE"
    elif fps == 59.94 or fps == 59.94005994:
        timebase = 60
        ntsc = "TRUE"
    else:
        timebase = int(fps)
        ntsc = "FALSE"

    duration = chunks[-1][1]

    clips = []
    for chunk in chunks:
        if chunk[2] != 99999:
            clips.append(chunk)

    pathurls = [path_to_uri(src.path)]

    tracks = len(src.audios)

    if tracks > 1:
        name_without_extension = src.basename[: src.basename.rfind(".")]

        fold = safe_mkdir(os.path.join(src.dirname, f"{name_without_extension}_tracks"))

        for i in range(1, tracks):
            newtrack = os.path.join(fold, f"{i}.wav")
            move(ensure.audio(src.path, 0, i), newtrack)
            pathurls.append(path_to_uri(newtrack))

    width, height = timeline.res

    group_name = f"Auto-Editor {'Audio' if audio_file else 'Video'} Group"

    with open(output, "w", encoding="utf-8") as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
        outfile.write('<xmeml version="4">\n')
        outfile.write("\t<sequence>\n")
        outfile.write(f"\t\t<name>{group_name}</name>\n")
        outfile.write(f"\t\t<duration>{duration}</duration>\n")
        outfile.write("\t\t<rate>\n")
        outfile.write(f"\t\t\t<timebase>{timebase}</timebase>\n")
        outfile.write(f"\t\t\t<ntsc>{ntsc}</ntsc>\n")
        outfile.write("\t\t</rate>\n")
        outfile.write("\t\t<media>\n")
        outfile.write(
            indent(
                3,
                "<video>",
                "\t<format>",
                "\t\t<samplecharacteristics>",
            )
        )

        if len(src.videos) > 0:
            outfile.write(
                indent(
                    3,
                    "\t\t\t<rate>",
                    f"\t\t\t\t<timebase>{timebase}</timebase>",
                    f"\t\t\t\t<ntsc>{ntsc}</ntsc>",
                    "\t\t\t</rate>",
                )
            )

        outfile.write(
            indent(
                3,
                f"\t\t\t<width>{width}</width>",
                f"\t\t\t<height>{height}</height>",
                f"\t\t\t<pixelaspectratio>{PIXEL_ASPECT_RATIO}</pixelaspectratio>",
            )
        )

        if len(src.videos) > 0:
            outfile.write(
                indent(
                    3,
                    "\t\t\t<fielddominance>none</fielddominance>",
                    f"\t\t\t<colordepth>{COLORDEPTH}</colordepth>",
                )
            )

        outfile.write(
            indent(
                3,
                "\t\t</samplecharacteristics>",
                "\t</format>",
                "</video>" if len(src.videos) == 0 else "\t<track>",
            )
        )

        if len(src.videos) > 0:
            # Handle video clips

            total = 0.0
            for j, clip in enumerate(clips):

                clip_duration = (clip[1] - clip[0]) / clip[2]

                _start = int(total)
                _end = int(total) + int(clip_duration)
                _in = int(clip[0] / clip[2])
                _out = int(clip[1] / clip[2])

                total += clip_duration

                outfile.write(
                    indent(
                        5,
                        f'<clipitem id="clipitem-{j+1}">',
                        "\t<masterclipid>masterclip-2</masterclipid>",
                        f"\t<name>{src.basename}</name>",
                        f"\t<start>{_start}</start>",
                        f"\t<end>{_end}</end>",
                        f"\t<in>{_in}</in>",
                        f"\t<out>{_out}</out>",
                    )
                )

                if j == 0:
                    outfile.write(
                        indent(
                            6,
                            '<file id="file-1">',
                            f"\t<name>{src.basename}</name>",
                            f"\t<pathurl>{pathurls[0]}</pathurl>",
                            "\t<rate>",
                            f"\t\t<timebase>{timebase}</timebase>",
                            f"\t\t<ntsc>{ntsc}</ntsc>",
                            "\t</rate>",
                            f"\t<duration>{duration}</duration>",
                            "\t<media>",
                            "\t\t<video>",
                            "\t\t\t<samplecharacteristics>",
                            "\t\t\t\t<rate>",
                            f"\t\t\t\t\t<timebase>{timebase}</timebase>",
                            f"\t\t\t\t\t<ntsc>{ntsc}</ntsc>",
                            "\t\t\t\t</rate>",
                            f"\t\t\t\t<width>{width}</width>",
                            f"\t\t\t\t<height>{height}</height>",
                            f"\t\t\t\t<anamorphic>{ANAMORPHIC}</anamorphic>",
                            f"\t\t\t\t<pixelaspectratio>{PIXEL_ASPECT_RATIO}</pixelaspectratio>",
                            "\t\t\t\t<fielddominance>none</fielddominance>",
                            "\t\t\t</samplecharacteristics>",
                            "\t\t</video>",
                            "\t\t<audio>",
                            "\t\t\t<samplecharacteristics>",
                            f"\t\t\t\t<depth>{DEPTH}</depth>",
                            f"\t\t\t\t<samplerate>{samplerate}</samplerate>",
                            "\t\t\t</samplecharacteristics>",
                            "\t\t\t<channelcount>2</channelcount>",
                            "\t\t</audio>",
                            "\t</media>",
                            "</file>",
                        )
                    )
                else:
                    outfile.write('\t\t\t\t\t\t<file id="file-1"/>\n')

                if clip[2] != 1:
                    outfile.write(speedup(clip[2] * 100))

                # Linking for video blocks
                for i in range(max(6, tracks + 1)):
                    outfile.write("\t\t\t\t\t\t<link>\n")
                    outfile.write(
                        f"\t\t\t\t\t\t\t<linkclipref>clipitem-{(i*(len(clips)))+j+1}</linkclipref>\n"
                    )
                    if i == 0:
                        outfile.write("\t\t\t\t\t\t\t<mediatype>video</mediatype>\n")
                    else:
                        outfile.write("\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n")
                    if 1 <= i <= 6:
                        outfile.write(f"\t\t\t\t\t\t\t<trackindex>{i}</trackindex>\n")
                    else:
                        outfile.write("\t\t\t\t\t\t\t<trackindex>1</trackindex>\n")
                    outfile.write(f"\t\t\t\t\t\t\t<clipindex>{j+1}</clipindex>\n")
                    if i > 0:
                        outfile.write("\t\t\t\t\t\t\t<groupindex>1</groupindex>\n")
                    outfile.write("\t\t\t\t\t\t</link>\n")

                outfile.write("\t\t\t\t\t</clipitem>\n")
            outfile.write(indent(3, "\t</track>", "</video>"))

        # Audio Clips
        outfile.write(
            indent(
                3,
                "<audio>",
                "\t<numOutputChannels>2</numOutputChannels>",
                "\t<format>",
                "\t\t<samplecharacteristics>",
                f"\t\t\t<depth>{DEPTH}</depth>",
                f"\t\t\t<samplerate>{samplerate}</samplerate>",
                "\t\t</samplecharacteristics>",
                "\t</format>",
            )
        )

        for t in range(tracks):
            outfile.write(
                '\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n'
            )
            total = 0
            for j, clip in enumerate(clips):

                clip_duration = (clip[1] - clip[0]) / clip[2]

                _start = int(total)
                _end = int(total) + int(clip_duration)
                _in = int(clip[0] / clip[2])
                _out = int(clip[1] / clip[2])

                total += clip_duration

                if audio_file:
                    clip_item_num = j + 1
                    master_id = "1"
                else:
                    clip_item_num = len(clips) + 1 + j + (t * len(clips))
                    master_id = "2"

                outfile.write(
                    indent(
                        5,
                        f'<clipitem id="clipitem-{clip_item_num}" premiereChannelType="stereo">',
                        f"\t<masterclipid>masterclip-{master_id}</masterclipid>",
                        f"\t<name>{src.basename}</name>",
                        f"\t<start>{_start}</start>",
                        f"\t<end>{_end}</end>",
                        f"\t<in>{_in}</in>",
                        f"\t<out>{_out}</out>",
                    )
                )

                if j == 0 and (audio_file or t > 0):
                    outfile.write(
                        indent(
                            6,
                            f'<file id="file-{t+1}">',
                            f"\t<name>{src.basename}</name>",
                            f"\t<pathurl>{pathurls[t]}</pathurl>",
                            "\t<rate>",
                            f"\t\t<timebase>{timebase}</timebase>",
                            f"\t\t<ntsc>{ntsc}</ntsc>",
                            "\t</rate>",
                            "\t<media>",
                            "\t\t<audio>",
                            "\t\t\t<samplecharacteristics>",
                            f"\t\t\t\t<depth>{DEPTH}</depth>",
                            f"\t\t\t\t<samplerate>{samplerate}</samplerate>",
                            "\t\t\t</samplecharacteristics>",
                            "\t\t\t<channelcount>2</channelcount>",
                            "\t\t</audio>",
                            "\t</media>",
                            "</file>",
                        )
                    )
                else:
                    outfile.write(f'\t\t\t\t\t\t<file id="file-{t+1}"/>\n')

                outfile.write(
                    indent(
                        6,
                        "<sourcetrack>",
                        "\t<mediatype>audio</mediatype>",
                        "\t<trackindex>1</trackindex>",
                        "</sourcetrack>",
                        "<labels>",
                        "\t<label2>Iris</label2>",
                        "</labels>",
                    )
                )

                if clip[2] != 1:
                    outfile.write(speedup(clip[2] * 100))

                outfile.write("\t\t\t\t\t</clipitem>\n")
            if not audio_file:
                outfile.write("\t\t\t\t\t<outputchannelindex>1</outputchannelindex>\n")
            outfile.write("\t\t\t\t</track>\n")

        outfile.write("\t\t\t</audio>\n")
        outfile.write("\t\t</media>\n")
        outfile.write("\t</sequence>\n")
        outfile.write("</xmeml>\n")
