from __future__ import annotations

from auto_editor.utils.types import (
    bool_coerce,
    db_threshold,
    natural,
    natural_or_none,
    stream,
    threshold,
    time,
)

from .util import Attr, Attrs, Required

audio_builder = Attrs(
    "audio",
    Attr("threshold", db_threshold, 0.04),
    Attr("stream", stream, 0),
    Attr("mincut", time, 6),
    Attr("minclip", time, 3),
)
motion_builder = Attrs(
    "motion",
    Attr("threshold", threshold, 0.02),
    Attr("stream", natural, 0),
    Attr("blur", natural, 9),
    Attr("width", natural, 400),
)
pixeldiff_builder = Attrs(
    "pixeldiff",
    Attr("threshold", natural, 1),
    Attr("stream", natural, 0),
)
subtitle_builder = Attrs(
    "subtitle",
    Attr("pattern", str, Required),
    Attr("stream", natural, 0),
    Attr("ignore-case", bool_coerce, False),
    Attr("max-count", natural_or_none, None),
)
