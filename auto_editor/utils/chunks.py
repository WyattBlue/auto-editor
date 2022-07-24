from __future__ import annotations

from fractions import Fraction
from typing import List, Tuple

import numpy as np

Chunk = Tuple[int, int, float]
Chunks = List[Chunk]


# Turn long silent/loud array to formatted chunk list.
# Example: [1, 1, 1, 2, 2] => [(0, 3, 1), (3, 5, 2)]
def chunkify(arr: np.ndarray | list[int]) -> Chunks:
    arr_length = len(arr)

    chunks = []
    start = 0
    for j in range(1, arr_length):
        if arr[j] != arr[j - 1]:
            chunks.append((start, j, arr[j - 1]))
            start = j
    chunks.append((start, arr_length, arr[j]))
    return chunks


def chunks_len(chunks: Chunks) -> Fraction:
    _len = Fraction(0)
    for chunk in chunks:
        if chunk[2] != 99999:
            speed = Fraction(chunk[2])
            _len += Fraction(chunk[1] - chunk[0], speed)
    return _len


def merge_chunks(all_chunks: list[Chunks]) -> Chunks:
    chunks = []
    start = 0
    for _chunks in all_chunks:
        for chunk in _chunks:
            chunks.append((chunk[0] + start, chunk[1] + start, chunk[2]))
        if _chunks:
            start += _chunks[-1][1]

    return chunks
