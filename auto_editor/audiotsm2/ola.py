'''ola.py'''

"""
The audiotsm.ola module implements the OLA (Overlap-Add) time-scale
modification procedure.
"""

from auto_editor.audiotsm2.base import AnalysisSynthesisTSM, Converter
from auto_editor.audiotsm2.utils.windows import hanning

class OLAConverter(Converter):
    def convert_frame(self, analysis_frame):
        return analysis_frame


def ola(channels, speed=1., frame_length=256, analysis_hop=None, synthesis_hop=None):
    """
    Returns a audiotsm.base.tsm.TSM object implementing the OLA
    (Overlap-Add) time-scale modification procedure.

    In most cases, you should not need to set the frame_length, the
    analysis_hop or the synthesis_hop. If you want to fine tune these
    parameters, you can check the documentation of the
    audiotsm.base.analysis_synthesis.AnalysisSynthesisTSM class to
    see what they represent.
    """
    if(synthesis_hop is None):
        synthesis_hop = frame_length // 2

    if(analysis_hop is None):
        analysis_hop = int(synthesis_hop * speed)

    analysis_window = None
    synthesis_window = hanning(frame_length)

    converter = OLAConverter()

    return AnalysisSynthesisTSM(
        converter, channels, frame_length, analysis_hop, synthesis_hop,
        analysis_window, synthesis_window)
