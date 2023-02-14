from __future__ import annotations

import os.path
import xml.etree.ElementTree as ET
from fractions import Fraction
from math import ceil
from shutil import move
from typing import TYPE_CHECKING
from xml.etree.ElementTree import Element

from auto_editor.ffwrapper import FFmpeg, FileInfo
from auto_editor.timeline import ASpace, TlAudio, TlVideo, VSpace, v3

from .utils import Validator, safe_mkdir, show

if TYPE_CHECKING:
    from auto_editor.output import Ensure
    from auto_editor.utils.log import Log

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


def uri_to_path(uri: str) -> str:
    from urllib.parse import urlparse
    from urllib.request import url2pathname

    parsed = urlparse(uri)
    s = os.path.sep
    host = f"{s}{s}{parsed.netloc}{s}"
    return os.path.normpath(os.path.join(host, url2pathname(parsed.path)))

    # /Users/wyattblue/projects/auto-editor/example.mp4
    # file:///Users/wyattblue/projects/auto-editor/example.mp4
    # file://localhost/Users/wyattblue/projects/auto-editor/example.mp4


def set_tb_ntsc(tb: Fraction) -> tuple[int, str]:
    # See chart: https://developer.apple.com/library/archive/documentation/AppleApplications/Reference/FinalCutPro_XML/FrameRate/FrameRate.html#//apple_ref/doc/uid/TP30001158-TPXREF103
    if tb == Fraction(24000, 1001):
        return 24, "TRUE"
    if tb == Fraction(30000, 1001):
        return 30, "TRUE"
    if tb == Fraction(60000, 1001):
        return 60, "TRUE"

    ctb = ceil(tb)
    if ctb not in (24, 30, 60) and ctb * Fraction(999, 1000) == tb:
        return ctb, "TRUE"

    return int(tb), "FALSE"


def read_tb_ntsc(tb: int, ntsc: bool) -> Fraction:
    if ntsc:
        if tb == 24:
            return Fraction(24000, 1001)
        if tb == 30:
            return Fraction(30000, 1001)
        if tb == 60:
            return Fraction(60000, 1001)
        return tb * Fraction(999, 1000)

    return Fraction(tb)


def speedup(speed: float) -> Element:
    fil = Element("filter")
    effect = ET.SubElement(fil, "effect")
    ET.SubElement(effect, "name").text = "Time Remap"
    ET.SubElement(effect, "effectid").text = "timeremap"

    para = ET.SubElement(effect, "parameter", authoringApp="PremierePro")
    ET.SubElement(para, "parameterid").text = "variablespeed"
    ET.SubElement(para, "name").text = "variablespeed"
    ET.SubElement(para, "valuemin").text = "0"
    ET.SubElement(para, "valuemax").text = "1"
    ET.SubElement(para, "value").text = "0"

    para2 = ET.SubElement(effect, "parameter", authoringApp="PremierePro")
    ET.SubElement(para2, "parameterid").text = "speed"
    ET.SubElement(para2, "name").text = "speed"
    ET.SubElement(para2, "valuemin").text = "-100000"
    ET.SubElement(para2, "valuemax").text = "100000"
    ET.SubElement(para2, "value").text = str(speed)

    para3 = ET.SubElement(effect, "parameter", authoringApp="PremierePro")
    ET.SubElement(para3, "parameterid").text = "frameblending"
    ET.SubElement(para3, "name").text = "frameblending"
    ET.SubElement(para3, "value").text = "FALSE"

    return fil


def premiere_read_xml(path: str, ffmpeg: FFmpeg, log: Log) -> v3:
    def xml_bool(val: str) -> bool:
        if val == "TRUE":
            return True
        if val == "FALSE":
            return False
        raise TypeError("Value must be 'TRUE' or 'FALSE'")

    try:
        tree = ET.parse(path)
    except FileNotFoundError:
        log.nofile(path)

    root = tree.getroot()

    valid = Validator(log)

    valid.check(root, "xmeml")
    valid.check(root[0], "sequence")
    result = valid.parse(
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

    tb = read_tb_ntsc(result["rate"]["timebase"], result["rate"]["ntsc"])

    av = valid.parse(
        result["media"],
        {
            "video": None,
            "audio": None,
        },
    )

    sources: dict[str, FileInfo] = {}
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
        tracks = valid.parse(av["video"], vclip_schema)

        width = tracks["format"]["samplecharacteristics"]["width"]
        height = tracks["format"]["samplecharacteristics"]["height"]
        res = width, height

        for t, track in enumerate(tracks["track"]):
            if len(track["clipitem"]) > 0:
                vobjs.append([])
            for i, clipitem in enumerate(track["clipitem"]):
                file_id = clipitem["file"].attrib["id"]
                if file_id not in sources:
                    fileobj = valid.parse(clipitem["file"], {"pathurl": str})

                    if "pathurl" in fileobj:
                        sources[file_id] = FileInfo(
                            uri_to_path(fileobj["pathurl"]),
                            ffmpeg,
                            log,
                            str(len(sources)),
                        )
                    else:
                        show(clipitem["file"], 3)
                        log.error(
                            f"'pathurl' child element not found in {clipitem['file'].tag}"
                        )

                start = clipitem["start"]
                dur = clipitem["end"] - start
                offset = clipitem["in"]

                vobjs[t].append(TlVideo(start, dur, file_id, offset, speed=1, stream=0))

    if "audio" in av:
        tracks = valid.parse(av["audio"], aclip_schema)
        sr = tracks["format"]["samplecharacteristics"]["samplerate"]

        for t, track in enumerate(tracks["track"]):
            if len(track["clipitem"]) > 0:
                aobjs.append([])
            for i, clipitem in enumerate(track["clipitem"]):
                file_id = clipitem["file"].attrib["id"]
                if file_id not in sources:
                    fileobj = valid.parse(clipitem["file"], {"pathurl": str})
                    sources[file_id] = FileInfo(
                        uri_to_path(fileobj["pathurl"]), ffmpeg, log, str(len(sources))
                    )

                start = clipitem["start"]
                dur = clipitem["end"] - start
                offset = clipitem["in"]

                aobjs[t].append(
                    TlAudio(start, dur, file_id, offset, speed=1, volume=1, stream=0)
                )

    return v3(sources, tb, sr, res, "#000", vobjs, aobjs, None)


def premiere_write_xml(_name: str | None, ensure: Ensure, output: str, tl: v3) -> None:
    assert tl.v1 is not None

    clips = list(filter(lambda c: c[2] != 99999, tl.v1.chunks))
    duration = tl.v1.chunks[-1][1]

    src = tl.v1.source
    width, height = tl.res

    audio_file = len(src.videos) == 0 and len(src.audios) == 1
    timebase, ntsc = set_tb_ntsc(tl.tb)

    pathurls = [src.path.resolve().as_uri()]

    tracks = len(src.audios)

    if tracks > 1:
        fold = src.path.parent / f"{src.path.stem}_tracks"
        safe_mkdir(fold)

        for i in range(1, tracks):
            newtrack = fold / f"{i}.wav"
            move(ensure.audio(f"{src.path.resolve()}", "0", i), newtrack)
            pathurls.append(newtrack.resolve().as_uri())

    if _name is None:
        name = f"Auto-Editor {'Audio' if audio_file else 'Video'} Group"
    else:
        name = _name

    xmeml = ET.Element("xmeml", version="4")
    sequence = ET.SubElement(xmeml, "sequence")
    ET.SubElement(sequence, "name").text = name
    ET.SubElement(sequence, "duration").text = str(duration)
    rate = ET.SubElement(sequence, "rate")
    ET.SubElement(rate, "timebase").text = str(timebase)
    ET.SubElement(rate, "ntsc").text = ntsc
    media = ET.SubElement(sequence, "media")
    video = ET.SubElement(media, "video")
    vformat = ET.SubElement(video, "format")
    vschar = ET.SubElement(vformat, "samplecharacteristics")

    rate = ET.SubElement(vschar, "rate")
    ET.SubElement(rate, "timebase").text = str(timebase)
    ET.SubElement(rate, "ntsc").text = ntsc
    ET.SubElement(vschar, "fielddominance").text = "none"
    ET.SubElement(vschar, "colordepth").text = COLORDEPTH
    ET.SubElement(vschar, "width").text = str(width)
    ET.SubElement(vschar, "height").text = str(height)
    ET.SubElement(vschar, "pixelaspectratio").text = PIXEL_ASPECT_RATIO

    if len(src.videos) > 0:
        track = ET.SubElement(video, "track")

        total = 0.0
        for j, clip in enumerate(clips):
            clip_duration = (clip[1] - clip[0]) / clip[2]

            _start = int(total)
            _end = int(total) + int(clip_duration)
            _in = int(clip[0] / clip[2])
            _out = int(clip[1] / clip[2])

            total += clip_duration

            clipitem = ET.SubElement(track, "clipitem", id=f"clipitem-{j+1}")
            ET.SubElement(clipitem, "masterclipid").text = "masterclip-2"
            ET.SubElement(clipitem, "name").text = src.path.stem
            ET.SubElement(clipitem, "start").text = str(_start)
            ET.SubElement(clipitem, "end").text = str(_end)
            ET.SubElement(clipitem, "in").text = str(_in)
            ET.SubElement(clipitem, "out").text = str(_out)

            filedef = ET.SubElement(clipitem, "file", id="file-1")

            if j == 0:
                ET.SubElement(filedef, "name").text = src.path.stem
                ET.SubElement(filedef, "pathurl").text = pathurls[0]

                rate = ET.SubElement(filedef, "rate")
                ET.SubElement(rate, "timebase").text = str(timebase)
                ET.SubElement(rate, "ntsc").text = ntsc
                ET.SubElement(filedef, "duration").text = str(duration)

                mediadef = ET.SubElement(filedef, "media")
                videodef = ET.SubElement(mediadef, "video")

                vschar = ET.SubElement(videodef, "samplecharacteristics")
                rate = ET.SubElement(vschar, "rate")
                ET.SubElement(rate, "timebase").text = str(timebase)
                ET.SubElement(rate, "ntsc").text = ntsc
                ET.SubElement(filedef, "duration").text = str(duration)
                ET.SubElement(vschar, "width").text = str(width)
                ET.SubElement(vschar, "height").text = str(height)
                ET.SubElement(vschar, "anamorphic").text = ANAMORPHIC
                ET.SubElement(vschar, "pixelaspectratio").text = PIXEL_ASPECT_RATIO

                audiodef = ET.SubElement(mediadef, "audio")
                aschar = ET.SubElement(audiodef, "samplecharacteristics")
                ET.SubElement(aschar, "depth").text = DEPTH
                ET.SubElement(aschar, "samplerate").text = str(tl.sr)
                ET.SubElement(audiodef, "channelcount").text = "2"

            if clip[2] != 1:
                clipitem.append(speedup(clip[2] * 100))

            for i in range(tracks + 1):
                link = ET.SubElement(clipitem, "link")
                ET.SubElement(
                    link, "linkclipref"
                ).text = f"clipitem-{(i*(len(clips)))+j+1}"
                ET.SubElement(link, "mediatype").text = "video" if i == 0 else "audio"
                ET.SubElement(link, "trackindex").text = str(max(i, 1))
                ET.SubElement(link, "clipindex").text = str(j + 1)
                if i > 0:
                    ET.SubElement(link, "groupindex").text = "1"

    # Audio definitions and clips
    audio = ET.SubElement(media, "audio")
    ET.SubElement(audio, "numOutputChannels").text = "2"
    aformat = ET.SubElement(audio, "format")
    aschar = ET.SubElement(aformat, "samplecharacteristics")
    ET.SubElement(aschar, "depth").text = DEPTH
    ET.SubElement(aschar, "samplerate").text = str(tl.sr)

    for t in range(tracks):
        track = ET.Element(
            "track", currentExplodedTrackIndex="0", premiereTrackType="Stereo"
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

            clipitem = ET.SubElement(
                track,
                "clipitem",
                id=f"clipitem-{clip_item_num}",
                premiereChannelType="stereo",
            )
            ET.SubElement(clipitem, "masterclipid").text = f"masterclip-{master_id}"
            ET.SubElement(clipitem, "name").text = src.path.stem
            ET.SubElement(clipitem, "start").text = str(_start)
            ET.SubElement(clipitem, "end").text = str(_end)
            ET.SubElement(clipitem, "in").text = str(_in)
            ET.SubElement(clipitem, "out").text = str(_out)

            filedef = ET.SubElement(clipitem, "file", id=f"file-{t+1}")
            if j == 0 and (audio_file or t > 0):
                ET.SubElement(filedef, "name").text = src.path.stem
                ET.SubElement(filedef, "pathurl").text = pathurls[t]

                rate = ET.SubElement(filedef, "rate")
                ET.SubElement(rate, "timebase").text = str(timebase)
                ET.SubElement(rate, "ntsc").text = ntsc

                media = ET.SubElement(filedef, "media")
                media_audio = ET.SubElement(media, "audio")
                maschar = ET.SubElement(media_audio, "samplecharacteristics")
                ET.SubElement(maschar, "depth").text = DEPTH
                ET.SubElement(maschar, "samplerate").text = str(tl.sr)
                ET.SubElement(media_audio, "channelcount").text = "2"

            sourcetrack = ET.SubElement(clipitem, "sourcetrack")
            ET.SubElement(sourcetrack, "mediatype").text = "audio"
            ET.SubElement(sourcetrack, "trackindex").text = "1"
            labels = ET.SubElement(clipitem, "labels")
            ET.SubElement(labels, "label2").text = "Iris"

            if clip[2] != 1:
                clipitem.append(speedup(clip[2] * 100))

            if not audio_file:
                ET.SubElement(clipitem, "outputchannelindex").text = "1"

        audio.append(track)

    tree = ET.ElementTree(xmeml)
    ET.indent(tree, space="\t", level=0)
    tree.write(output, xml_declaration=True, encoding="utf-8")
