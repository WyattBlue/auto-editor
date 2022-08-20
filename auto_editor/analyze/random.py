from __future__ import annotations

import random
from typing import TYPE_CHECKING

import numpy as np

from auto_editor.analyze.helper import get_media_length

if TYPE_CHECKING:
    from fractions import Fraction

    from numpy.typing import NDArray

    from auto_editor.utils.log import Log


def random_levels(
    path: str, i: int, robj, timebase: Fraction, temp: str, log: Log
) -> NDArray[np.float_]:
    if robj.seed == -1:
        robj.seed = random.randint(0, 2147483647)

    l = get_media_length(path, i, timebase, temp, log) - 1
    random.seed(robj.seed)

    log.debug(f"Seed: {robj.seed}")

    arr = [random.random() for _ in range(l)]

    return np.array(arr, dtype=np.float_)
