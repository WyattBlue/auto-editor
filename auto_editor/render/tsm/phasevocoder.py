import numpy as np
from numpy.typing import NDArray

from .analysis_synthesis import AnalysisSynthesisTSM
from .array import ArrReader, ArrWriter


def hanning(length: int) -> np.ndarray:
    time = np.arange(length)
    return 0.5 * (1 - np.cos(2 * np.pi * time / length))


def phasevocoder(
    channels: int, speed: float, arr: np.ndarray, frame_length: int = 2048
) -> NDArray[np.int16]:

    # Frame length should be a power of two for maximum performance.

    synthesis_hop = frame_length // 4
    analysis_hop = int(synthesis_hop * speed)

    analysis_window = hanning(frame_length)
    synthesis_window = hanning(frame_length)

    writer = ArrWriter(np.zeros((0, channels), dtype=np.int16))
    reader = ArrReader(arr)

    AnalysisSynthesisTSM(
        channels,
        frame_length,
        analysis_hop,
        synthesis_hop,
        analysis_window,
        synthesis_window,
    ).run(reader, writer)

    return writer.output
