import numpy as np


class ArrReader:
    __slots__ = ("samples", "pointer")

    def __init__(self, arr):
        self.samples = arr
        self.pointer = 0

    @property
    def empty(self):
        return self.samples.shape[0] <= self.pointer

    def read(self, buffer: np.ndarray) -> int:
        end = self.pointer + buffer.shape[1]
        frames = self.samples[self.pointer : end].T.astype(np.float32)
        n = frames.shape[1]
        np.copyto(buffer[:, :n], frames)
        del frames
        self.pointer = end
        return n

    def skip(self, n):
        pastPointer = self.pointer
        self.pointer += n
        return self.pointer - pastPointer


class ArrWriter:
    __slots__ = ("output", "pointer")

    def __init__(self, arr):
        self.output = arr
        self.pointer = 0

    def write(self, buffer: np.ndarray) -> int:
        end = self.pointer + buffer.shape[1]
        changedBuffer = buffer.T.astype(np.int16)
        self.output = np.concatenate((self.output, changedBuffer))
        self.pointer = end

        return buffer.shape[1]
