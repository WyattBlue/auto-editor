import numpy as np

from .array import ArrReader, ArrWriter


class CBuffer:
    def __init__(self, channels: int, max_length: int) -> None:
        self._data = np.zeros((channels, max_length), dtype=np.float32)
        self._channels = channels
        self._max_length = max_length

        self._offset = 0
        self._ready = 0
        self.length = 0

    def add(self, buffer: np.ndarray) -> None:
        """Adds a buffer element-wise to the CBuffer."""
        if buffer.shape[0] != self._data.shape[0]:
            raise ValueError("the two buffers should have the same number of channels")

        n = buffer.shape[1]
        if n > self.length:
            raise ValueError("not enough space remaining in CBuffer")

        # Compute the slice of data where the values will be added
        start = self._offset
        end = self._offset + n

        if end <= self._max_length:
            self._data[:, start:end] += buffer[:, :n]
        else:
            end -= self._max_length
            self._data[:, start:] += buffer[:, : self._max_length - start]
            self._data[:, :end] += buffer[:, self._max_length - start : n]

    def divide(self, array: np.ndarray) -> None:
        n = len(array)
        if n > self.length:
            raise ValueError("not enough space remaining in the CBuffer")

        start = self._offset
        end = self._offset + n

        if end <= self._max_length:
            self._data[:, start:end] /= array[:n]
        else:
            end -= self._max_length
            self._data[:, start:] /= array[: self._max_length - start]
            self._data[:, :end] /= array[self._max_length - start : n]

    def peek(self, buffer: np.ndarray) -> int:
        if buffer.shape[0] != self._data.shape[0]:
            raise ValueError("the two buffers should have the same number of channels")

        n = min(buffer.shape[1], self._ready)

        start = self._offset
        end = self._offset + n

        if end <= self._max_length:
            np.copyto(buffer[:, :n], self._data[:, start:end])
        else:
            end -= self._max_length
            np.copyto(buffer[:, : self._max_length - start], self._data[:, start:])
            np.copyto(buffer[:, self._max_length - start : n], self._data[:, :end])

        return n

    def read(self, buffer: np.ndarray) -> int:
        n = self.peek(buffer)
        self.remove(n)
        return n

    def read_from(self, reader: ArrReader) -> int:
        # Compute the slice of data that will be written to
        start = (self._offset + self.length) % self._max_length
        end = start + self._max_length - self.length

        if end <= self._max_length:
            n = reader.read(self._data[:, start:end])
        else:
            # There is not enough space to copy the whole buffer, it has to be
            # split into two parts, one of which will be copied at the end of
            # _data, and the other at the beginning.
            end -= self._max_length

            n = reader.read(self._data[:, start:])
            n += reader.read(self._data[:, :end])

        self.length += n
        self._ready = self.length
        return n

    @property
    def ready(self):
        return self._ready

    @property
    def remaining_length(self):
        return self._max_length - self._ready

    def remove(self, n: int) -> int:
        """
        Removes the first n samples of the CBuffer, preventing
        them to be read again, and leaving more space for new samples to be
        written.
        """
        if n >= self.length:
            n = self.length

        # Compute the slice of data that will be reset to 0
        start = self._offset
        end = self._offset + n

        if end <= self._max_length:
            self._data[:, start:end] = 0
        else:
            end -= self._max_length
            self._data[:, start:] = 0
            self._data[:, :end] = 0

        self._offset += n
        self._offset %= self._max_length
        self.length -= n

        self._ready -= n
        if self._ready < 0:
            self._ready = 0

        return n

    def right_pad(self, n: int) -> None:
        if n > self._max_length - self.length:
            raise ValueError("not enough space remaining in CBuffer")

        self.length += n

    def set_ready(self, n: int) -> None:
        """Mark the next n samples as ready to be read."""
        if self._ready + n > self.length:
            raise ValueError("not enough samples to be marked as ready")

        self._ready += n

    def to_array(self):
        out = np.empty((self._channels, self._ready))
        self.peek(out)
        return out

    def write(self, buffer: np.ndarray) -> int:
        if buffer.shape[0] != self._data.shape[0]:
            raise ValueError("the two buffers should have the same number of channels")

        n = min(buffer.shape[1], self._max_length - self.length)

        # Compute the slice of data that will be written to
        start = (self._offset + self.length) % self._max_length
        end = start + n

        if end <= self._max_length:
            np.copyto(self._data[:, start:end], buffer[:, :n])
        else:
            # There is not enough space to copy the whole buffer, it has to be
            # split into two parts, one of which will be copied at the end of
            # _data, and the other at the beginning.
            end -= self._max_length

            np.copyto(self._data[:, start:], buffer[:, : self._max_length - start])
            np.copyto(self._data[:, :end], buffer[:, self._max_length - start : n])

        self.length += n
        self._ready = self.length
        return n

    def write_to(self, writer: ArrWriter) -> int:
        start = self._offset
        end = self._offset + self._ready

        if end <= self._max_length:
            n = writer.write(self._data[:, start:end])
        else:
            end -= self._max_length
            n = writer.write(self._data[:, start:])
            n += writer.write(self._data[:, :end])

        self.remove(n)
        return n
