'''audiotsm2/io/stream.py'''

import numpy as np
from sounddevice import OutputStream

class StreamWriter():
    def __init__(self, channels, samplerate, **attrs):
        self._channels = channels

        self._stream = OutputStream(samplerate=samplerate, channels=channels, **attrs)
        self._stream.start()

    @property
    def channels(self):
        return self._channels

    def write(self, buffer):
        if(buffer.shape[0] != self.channels):
            raise ValueError("the buffer should have the same number of "
                "channels as WavWriter")

        self._stream.write(np.ascontiguousarray(buffer.T))

        return buffer.shape[1]

    def stop(self):
        self._stream.stop()

    def __enter__(self):
        return self

    def __exit__(self, _1, _2, _3):
        self.stop()
