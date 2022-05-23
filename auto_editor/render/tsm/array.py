import numpy as np
from numpy.typing import NDArray


class ArrReader:
    __slots__ = ("samples", "pointer")

    def __init__(self, arr: np.ndarray) -> None:
        self.samples = arr
        self.pointer = 0

    @property
    def empty(self) -> bool:
        return self.samples.shape[0] <= self.pointer

    def read(self, buffer: np.ndarray) -> int:
        end = self.pointer + buffer.shape[1]
        frames = self.samples[self.pointer : end].T.astype(np.float32)
        n = frames.shape[1]
        np.copyto(buffer[:, :n], frames)
        del frames
        self.pointer = end
        return n

    def skip(self, n: int) -> int:
        self.pointer += n
        return n


class ArrWriter:
    __slots__ = ("output", "pointer")

    def __init__(self, arr: NDArray[np.int16]) -> None:
        self.output = arr
        self.pointer = 0

    def write(self, buffer: np.ndarray) -> int:
        end = self.pointer + buffer.shape[1]
        changed_buffer: NDArray[np.int16] = buffer.T.astype(np.int16)
        self.output = np.concatenate((self.output, changed_buffer))
        self.pointer = end

        return buffer.shape[1]
