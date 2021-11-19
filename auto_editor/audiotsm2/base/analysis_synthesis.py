'''audiotsm2/base/analysis_synthesis.py'''

import numpy as np

from auto_editor.audiotsm2.utils import (windows, CBuffer, NormalizeBuffer)
from .tsm import TSM

EPSILON = 0.0001


class AnalysisSynthesisTSM(TSM):
    def __init__(self, converter, channels, frame_length, analysis_hop, synthesis_hop,
        analysis_window, synthesis_window, delta_before=0, delta_after=0):
        self._converter = converter

        self._channels = channels
        self._frame_length = frame_length
        self._analysis_hop = analysis_hop
        self._synthesis_hop = synthesis_hop

        self._analysis_window = analysis_window
        self._synthesis_window = synthesis_window

        self._delta_before = delta_before
        self._delta_after = delta_after

        # When the analysis hop is larger than the frame length, some samples
        # from the input need to be skipped. self._skip_input_samples tracks
        # how many samples should be skipped before reading the analysis frame.
        self._skip_input_samples = 0

        # This attribute is used to start the output signal in the middle of a
        # frame, which should be the peek of the window function
        self._skip_output_samples = 0

        # Compute the normalize window
        self._normalize_window = windows.product(self._analysis_window,
                                                 self._synthesis_window)

        if(self._normalize_window is None):
            self._normalize_window = np.ones(self._frame_length)

        # Initialize the buffers
        delta = self._delta_before + self._delta_after
        self._in_buffer = CBuffer(self._channels, self._frame_length + delta)
        self._analysis_frame = np.empty(
            (self._channels, self._frame_length + delta))
        self._out_buffer = CBuffer(self._channels, self._frame_length)
        self._normalize_buffer = NormalizeBuffer(self._frame_length)

        self.clear()

    def clear(self):
        # Clear the buffers
        self._in_buffer.remove(self._in_buffer.length)
        self._out_buffer.remove(self._out_buffer.length)
        self._out_buffer.right_pad(self._frame_length)
        self._normalize_buffer.remove(self._normalize_buffer.length)

        # Left pad the input with half a frame of zeros, and ignore that half
        # frame in the output. This makes the output signal start in the middle
        # of a frame, which should be the peak of the window function.
        self._in_buffer.write(np.zeros(
            (self._channels, self._delta_before + self._frame_length // 2)))
        self._skip_output_samples = self._frame_length // 2

        self._converter.clear()

    def flush_to(self, writer):
        if(self._in_buffer.remaining_length == 0):
            raise RuntimeError(
                "There is still data to process in the input buffer, flush_to method "
                "should only be called when write_to returns True."
            )

        n = self._out_buffer.write_to(writer)
        if(self._out_buffer.ready == 0):
            # The output buffer is empty
            self.clear()
            return n, True

        return n, False

    def get_max_output_length(self, input_length):
        input_length -= self._skip_input_samples
        if(input_length <= 0):
            return 0

        n_frames = input_length // self._analysis_hop + 1
        return n_frames * self._synthesis_hop

    def _process_frame(self):
        """Read an analysis frame from the input buffer, process it, and write
        the result to the output buffer."""
        # Generate the analysis frame and discard the input samples that will
        # not be needed anymore
        self._in_buffer.peek(self._analysis_frame)
        self._in_buffer.remove(self._analysis_hop)

        # Apply the analysis window
        windows.apply(self._analysis_frame, self._analysis_window)

        # Convert the analysis frame into a synthesis frame
        synthesis_frame = self._converter.convert_frame(self._analysis_frame)

        # Apply the synthesis window
        windows.apply(synthesis_frame, self._synthesis_window)

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

    def read_from(self, reader):
        n = reader.skip(self._skip_input_samples)
        self._skip_input_samples -= n
        if(self._skip_input_samples > 0):
            return n

        n += self._in_buffer.read_from(reader)

        if(self._in_buffer.remaining_length == 0 and
            self._out_buffer.remaining_length >= self._synthesis_hop):
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

    def set_speed(self, speed):
        self._analysis_hop = int(self._synthesis_hop * speed)
        self._converter.set_analysis_hop(self._analysis_hop)

    def write_to(self, writer):
        n = self._out_buffer.write_to(writer)
        self._out_buffer.right_pad(n)

        if(self._in_buffer.remaining_length > 0 and self._out_buffer.ready == 0):
            # There is not enough data to process in the input buffer, and the
            # output buffer is empty
            return n, True

        return n, False
