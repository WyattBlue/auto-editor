import sys

from auto_editor.json import dump
from auto_editor.timeline import Clip, v3
from auto_editor.utils.log import Log


def as_dict(self: v3) -> dict:
    def aclip_to_dict(self: Clip) -> dict:
        return {
            "name": "audio",
            "src": self.src,
            "start": self.start,
            "dur": self.dur,
            "offset": self.offset,
            "speed": self.speed,
            "volume": self.volume,
            "stream": self.stream,
        }

    v = []
    a = []
    for vlayer in self.v:
        vb = [vobj.as_dict() for vobj in vlayer]
        if vb:
            v.append(vb)
    for layer in self.a:
        ab = [aclip_to_dict(clip) for clip in layer]
        if ab:
            a.append(ab)

    return {
        "version": "3",
        "timebase": f"{self.tb.numerator}/{self.tb.denominator}",
        "background": self.background,
        "resolution": self.T.res,
        "samplerate": self.T.sr,
        "layout": self.T.layout,
        "v": v,
        "a": a,
    }


def make_json_timeline(ver: str, out: str, tl: v3, log: Log) -> None:
    if ver not in {"v1", "v3"}:
        log.error(f"Unknown timeline version: {ver}")

    if out == "-":
        outfile = sys.stdout
    else:
        outfile = open(out, "w")

    if ver == "v3":
        dump(as_dict(tl), outfile, indent=2)
    else:
        if tl.v1 is None:
            log.error("Timeline can't be converted to v1 format")
        dump(tl.v1.as_dict(), outfile, indent=2)

    if out == "-":
        print("")  # Flush stdout
    else:
        outfile.close()
