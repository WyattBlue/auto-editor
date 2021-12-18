'''io/wav.py'''

import wave
import numpy as np

class WavReader():
    def __init__(self, filename):
        self._reader = wave.open(filename, 'rb')

    @property
    def channels(self):
        return self._reader.getnchannels()

    @property
    def empty(self):
        return self._reader.tell() == self._reader.getnframes()

    def close(self):
        self._reader.close()

    def read(self, buffer):
        if(buffer.shape[0] != self.channels):
            raise ValueError("the buffer should have the same number of "
                "channels as the WavReader")

        frames = self._reader.readframes(buffer.shape[1])
        frames = np.frombuffer(frames, '<i2').astype(np.float32) / 32676

        # Separate channels
        frames = frames.reshape((-1, self.channels)).T

        n = frames.shape[1]
        np.copyto(buffer[:, :n], frames)
        del frames

        return n

    @property
    def samplerate(self):
        return self._reader.getframerate()

    @property
    def samplewidth(self):
        return self._reader.getsamplewidth()

    def skip(self, n):
        current_pos = self._reader.tell()
        new_pos = min(current_pos + n, self._reader.getnframes())

        self._reader.setpos(new_pos)

        return new_pos - current_pos

    def __enter__(self):
        return self

    def __exit__(self, _1, _2, _3):
        self.close()


class WavWriter():
    def __init__(self, filename, channels, samplerate):
        self._writer = wave.open(filename, 'wb')
        self._channels = channels
        self._writer.setnchannels(channels)
        self._writer.setframerate(samplerate)
        self._writer.setsampwidth(2)

    @property
    def channels(self):
        return self._channels

    def close(self):
        self._writer.close()

    def write(self, buffer):
        if(buffer.shape[0] != self.channels):
            raise ValueError(f"buffer has {buffer.shape[0]} channels while self has {self.channels} channels")

        np.clip(buffer, -1, 1, out=buffer)

        n = buffer.shape[1]
        frames = (buffer.T.reshape((-1,)) * 32676).astype(np.int16).tobytes()
        self._writer.writeframes(frames)
        del frames

        return n

    def __enter__(self):
        return self

    def __exit__(self, _1, _2, _3):
        self.close()
