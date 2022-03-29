import numpy as np

# A NormalizeBuffer is a mono-channel circular buffer, used to normalize audio buffers.


class NormalizeBuffer:
    def __init__(self, length):
        self._data = np.zeros(length)
        self._offset = 0
        self.length = length

    def add(self, window):
        # Adds a window element-wise to the NormalizeBuffer.
        n = len(window)
        if n > self.length:
            raise ValueError("the window should be smaller than the NormalizeBuffer")

        # Compute the slice of data where the values will be added
        start = self._offset
        end = self._offset + n

        if end <= self.length:
            self._data[start:end] += window
        else:
            end -= self.length
            self._data[start:] += window[: self.length - start]
            self._data[:end] += window[self.length - start :]

    def remove(self, n):
        if n >= self.length:
            n = self.length
        if n == 0:
            return

        # Compute the slice of data to reset
        start = self._offset
        end = self._offset + n

        if end <= self.length:
            self._data[start:end] = 0
        else:
            end -= self.length
            self._data[start:] = 0
            self._data[:end] = 0

        self._offset += n
        self._offset %= self.length

    def to_array(self, start=0, end=None):
        if end is None:
            end = self.length

        start += self._offset
        end += self._offset

        if end <= self.length:
            return np.copy(self._data[start:end])

        end -= self.length
        if start < self.length:
            return np.concatenate((self._data[start:], self._data[:end]))

        start -= self.length
        return np.copy(self._data[start:end])
