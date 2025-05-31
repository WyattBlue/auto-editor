from __future__ import annotations

import sys
from typing import TYPE_CHECKING

from auto_editor.json import dump
from auto_editor.timeline import v3

if TYPE_CHECKING:
    from auto_editor.utils.log import Log


def make_json_timeline(ver: str, out: str, tl: v3, log: Log) -> None:
    if ver not in {"v1", "v3"}:
        log.error(f"Unknown timeline version: {ver}")

    if out == "-":
        outfile = sys.stdout
    else:
        outfile = open(out, "w")

    if ver == "v3":
        dump(tl.as_dict(), outfile, indent=2)
    else:
        if tl.v1 is None:
            log.error("Timeline can't be converted to v1 format")
        dump(tl.v1.as_dict(), outfile, indent=2)

    if out == "-":
        print("")  # Flush stdout
    else:
        outfile.close()
