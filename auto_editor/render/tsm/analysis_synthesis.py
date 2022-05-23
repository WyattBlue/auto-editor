from typing import Tuple

import numpy as np
from numpy.typing import NDArray

from .array import ArrReader, ArrWriter
from .cbuffer import CBuffer
from .normalizebuffer import NormalizeBuffer

EPSILON = 0.0001


def find_peaks(amplitude: NDArray[np.float_]) -> NDArray[np.bool_]:
    # To avoid overflows
    padded = np.concatenate((-np.ones(2), amplitude, -np.ones(2)))

    # Shift the array by one/two values to the left/right
    shifted_l2 = padded[:-4]
    shifted_l1 = padded[1:-3]
    shifted_r1 = padded[3:-1]
    shifted_r2 = padded[4:]

    # Compare the original array with the shifted versions.
    peaks = (
        (amplitude >= shifted_l2)
        & (amplitude >= shifted_l1)
        & (amplitude >= shifted_r1)
        & (amplitude >= shifted_r2)
    )

    return peaks


def get_closest_peaks(peaks: NDArray[np.bool_]) -> NDArray[np.int_]:
    """
    Returns an array containing the index of the closest peak of each index.
    """
    closest_peak = np.empty_like(peaks, dtype=int)
    previous = -1
    for i, is_peak in enumerate(peaks):
        if is_peak:
            if previous >= 0:
                closest_peak[previous : (previous + i) // 2 + 1] = previous
                closest_peak[(previous + i) // 2 + 1 : i] = i
            else:
                closest_peak[:i] = i
            previous = i
    closest_peak[previous:] = previous

    return closest_peak


class PhaseVocoderConverter:
    def __init__(
        self, channels: int, frame_length: int, analysis_hop: int, synthesis_hop: int
    ) -> None:
        self.channels = channels
        self._frame_length = frame_length
        self._synthesis_hop = synthesis_hop
        self._analysis_hop = analysis_hop

        self._center_frequency = np.fft.rfftfreq(frame_length) * 2 * np.pi  # type: ignore
        fft_length = len(self._center_frequency)

        self._first = True

        self._previous_phase = np.empty((channels, fft_length))
        self._output_phase = np.empty((channels, fft_length))

        # Buffer used to compute the phase increment and the instantaneous frequency
        self._buffer = np.empty(fft_length)

    def clear(self) -> None:
        self._first = True

    def convert_frame(self, frame: np.ndarray) -> np.ndarray:
        for k in range(self.channels):
            # Compute the FFT of the analysis frame
            stft = np.fft.rfft(frame[k])
            amplitude = np.abs(stft)

            phase: NDArray[np.float_]
            phase = np.angle(stft)  # type: ignore
            del stft

            peaks = find_peaks(amplitude)
            closest_peak = get_closest_peaks(peaks)

            if self._first:
                # Leave the first frame unchanged
                self._output_phase[k, :] = phase
            else:
                # Compute the phase increment
                self._buffer[peaks] = (
                    phase[peaks]
                    - self._previous_phase[k, peaks]
                    - self._analysis_hop * self._center_frequency[peaks]
                )

                # Unwrap the phase increment
                self._buffer[peaks] += np.pi
                self._buffer[peaks] %= 2 * np.pi
                self._buffer[peaks] -= np.pi

                # Compute the instantaneous frequency (in the same buffer,
                # since the phase increment wont be required after that)
                self._buffer[peaks] /= self._analysis_hop
                self._buffer[peaks] += self._center_frequency[peaks]

                self._buffer[peaks] *= self._synthesis_hop
                self._output_phase[k][peaks] += self._buffer[peaks]

                # Phase locking
                self._output_phase[k] = (
                    self._output_phase[k][closest_peak] + phase - phase[closest_peak]
                )

                # Compute the new stft
                output_stft = amplitude * np.exp(1j * self._output_phase[k])

                frame[k, :] = np.fft.irfft(output_stft).real

            # Save the phase for the next analysis frame
            self._previous_phase[k, :] = phase
            del phase
            del amplitude

        self._first = False

        return frame


class AnalysisSynthesisTSM:
    def run(self, reader: ArrReader, writer: ArrWriter, flush: bool = True) -> None:
        finished = False
        while not (finished and reader.empty):
            self.read_from(reader)
            _, finished = self.write_to(writer)

        if flush:
            finished = False
            while not finished:
                _, finished = self.flush_to(writer)

            self.clear()

    def __init__(
        self,
        channels: int,
        frame_length: int,
        analysis_hop: int,
        synthesis_hop: int,
        analysis_window: np.ndarray,
        synthesis_window: np.ndarray,
    ) -> None:

        self._converter = PhaseVocoderConverter(
            channels, frame_length, analysis_hop, synthesis_hop
        )

        self._channels = channels
        self._frame_length = frame_length
        self._analysis_hop = analysis_hop
        self._synthesis_hop = synthesis_hop

        self._analysis_window = analysis_window
        self._synthesis_window = synthesis_window

        # When the analysis hop is larger than the frame length, some samples
        # from the input need to be skipped.
        self._skip_input_samples = 0

        # Used to start the output signal in the middle of a frame, which should
        # be the peek of the window function
        self._skip_output_samples = 0

        self._normalize_window = self._analysis_window * self._synthesis_window

        # Initialize the buffers
        self._in_buffer = CBuffer(self._channels, self._frame_length)
        self._analysis_frame = np.empty((self._channels, self._frame_length))
        self._out_buffer = CBuffer(self._channels, self._frame_length)
        self._normalize_buffer = NormalizeBuffer(self._frame_length)

        self.clear()

    def clear(self) -> None:
        self._in_buffer.remove(self._in_buffer.length)
        self._out_buffer.remove(self._out_buffer.length)
        self._out_buffer.right_pad(self._frame_length)
        self._normalize_buffer.remove(self._normalize_buffer.length)

        # Left pad the input with half a frame of zeros, and ignore that half
        # frame in the output. This makes the output signal start in the middle
        # of a frame, which should be the peak of the window function.
        self._in_buffer.write(np.zeros((self._channels, self._frame_length // 2)))
        self._skip_output_samples = self._frame_length // 2

        self._converter.clear()

    def flush_to(self, writer: ArrWriter) -> Tuple[int, bool]:
        if self._in_buffer.remaining_length == 0:
            raise RuntimeError(
                "There is still data to process in the input buffer, flush_to method "
                "should only be called when write_to returns True."
            )

        n = self._out_buffer.write_to(writer)
        if self._out_buffer.ready == 0:
            # The output buffer is empty
            self.clear()
            return n, True

        return n, False

    def get_max_output_length(self, input_length: int) -> int:
        input_length -= self._skip_input_samples
        if input_length <= 0:
            return 0

        n_frames = input_length // self._analysis_hop + 1
        return n_frames * self._synthesis_hop

    def _process_frame(self) -> None:
        """Read an analysis frame from the input buffer, process it, and write
        the result to the output buffer."""
        # Generate the analysis frame and discard the input samples that will
        # not be needed anymore
        self._in_buffer.peek(self._analysis_frame)
        self._in_buffer.remove(self._analysis_hop)

        for channel in self._analysis_frame:
            channel *= self._analysis_window

        synthesis_frame = self._converter.convert_frame(self._analysis_frame)

        for channel in synthesis_frame:
            channel *= self._synthesis_window

        # Overlap and add the synthesis frame in the output buffer
        self._out_buffer.add(synthesis_frame)

        # The overlap and add step changes the volume of the signal. The
        # normalize_buffer is used to keep track of "how much of the input
        # signal was added" to each part of the output buffer, allowing to
        # normalize it.
        self._normalize_buffer.add(self._normalize_window)

        # Normalize the samples that are ready to be written to the output
        normalize = self._normalize_buffer.to_array(end=self._synthesis_hop)
        normalize[normalize < EPSILON] = 1
        self._out_buffer.divide(normalize)
        self._out_buffer.set_ready(self._synthesis_hop)
        self._normalize_buffer.remove(self._synthesis_hop)

    def read_from(self, reader: ArrReader) -> int:
        n = reader.skip(self._skip_input_samples)
        self._skip_input_samples -= n
        if self._skip_input_samples > 0:
            return n

        n += self._in_buffer.read_from(reader)

        if (
            self._in_buffer.remaining_length == 0
            and self._out_buffer.remaining_length >= self._synthesis_hop
        ):
            # The input buffer has enough data to process, and there is enough
            # space in the output buffer to store the output
            self._process_frame()

            # Skip output samples if necessary
            skipped = self._out_buffer.remove(self._skip_output_samples)
            self._out_buffer.right_pad(skipped)
            self._skip_output_samples -= skipped

            # Set the number of input samples to be skipped
            self._skip_input_samples = self._analysis_hop - self._frame_length
            if self._skip_input_samples < 0:
                self._skip_input_samples = 0

        return n

    def write_to(self, writer: ArrWriter) -> Tuple[int, bool]:
        n = self._out_buffer.write_to(writer)
        self._out_buffer.right_pad(n)

        if self._in_buffer.remaining_length > 0 and self._out_buffer.ready == 0:
            # There is not enough data to process in the input buffer, and the
            # output buffer is empty
            return n, True

        return n, False
