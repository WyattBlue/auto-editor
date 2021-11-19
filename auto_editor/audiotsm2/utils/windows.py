'''utils/windows.py'''

import numpy as np


def apply(buffer, window):
    """
    Applies a window to a buffer.
    """
    if window is None:
        return

    for channel in buffer:
        channel *= window


def hanning(length):
    """
    Returns a periodic Hanning window.
    """
    if length <= 0:
        return np.zeros(0)

    time = np.arange(length)
    return 0.5 * (1 - np.cos(2 * np.pi * time / length))


def product(window1, window2):
    if window1 is None:
        return window2

    if window2 is None:
        return window1

    return window1 * window2
