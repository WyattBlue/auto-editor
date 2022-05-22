import numpy as np
from numpy.typing import NDArray

from .analysis_synthesis import AnalysisSynthesisTSM


def hanning(length: int) -> np.ndarray:
    time = np.arange(length)
    return 0.5 * (1 - np.cos(2 * np.pi * time / length))


def find_peaks(amplitude: NDArray[np.float_]) -> NDArray[np.bool_]:
    """
    A value is considered to be a peak if it is higher than its four closest
    neighbours.
    """

    # Pad the array with -1 at the beginning and the end to avoid overflows.
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


def phasevocoder(
    channels: int, speed: float = 1.0, frame_length: int = 2048
) -> AnalysisSynthesisTSM:

    # Frame length should be a power of two for maximum performance.

    synthesis_hop = frame_length // 4
    analysis_hop = int(synthesis_hop * speed)

    analysis_window = hanning(frame_length)
    synthesis_window = hanning(frame_length)

    converter = PhaseVocoderConverter(
        channels, frame_length, analysis_hop, synthesis_hop
    )

    return AnalysisSynthesisTSM(
        converter,
        channels,
        frame_length,
        analysis_hop,
        synthesis_hop,
        analysis_window,
        synthesis_window,
    )
