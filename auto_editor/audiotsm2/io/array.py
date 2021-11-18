'''audiotsm2/io/array.py'''

import numpy as np

class ArrReader:
    pointer = 0

    def __init__(self, arr, channels, samplerate, samplewidth):
        self.samples = arr
        self._channels = channels
        self.samplerate = samplerate
        self.samplewidth = samplewidth

    @property
    def channels(self):
        return self._channels

    @property
    def empty(self):
        return self.samples.shape[0] <= self.pointer

    def read(self, buffer):
        if buffer.shape[0] != self.channels:
            raise ValueError(
                "the buffer should have the same number of channels as the ArrReader"
            )

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

    def __enter__(self):
        return self

    def __exit__(self, _1, _2, _3):
        pass


class ArrWriter:
    pointer = 0

    def __init__(self, arr, channels, samplerate, samplewidth):
        self._channels = channels
        self.output = arr

    @property
    def channels(self):
        return self._channels

    def write(self, buffer):
        if buffer.shape[0] != self.channels:
            raise ValueError(
                "the buffer should have the same number of channels as the ArrWriter"
            )

        end = self.pointer + buffer.shape[1]
        changedBuffer = buffer.T.astype(np.int16)
        n = buffer.shape[1]
        self.output = np.concatenate((self.output, changedBuffer))
        self.pointer = end
        return n

    def __enter__(self):
        return self

    def __exit__(self, _1, _2, _3):
        pass
