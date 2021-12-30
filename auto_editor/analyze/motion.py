'''analyze/motion.py'''

# Motion detection method is based on this post:
# pyimagesearch.com/2015/05/25/basic-motion-detection-and-tracking-with-python-and-opencv/

import cv2
import numpy as np

from auto_editor.ffwrapper import File
from auto_editor.utils.log import Log

def resize(image, width=None, height=None, inter=cv2.INTER_AREA):
    if(width is None and height is None):
        return image

    h, w = image.shape[:2]
    if(width is None):
        r = height / h
        dim = (int(w * r), height)
    else:
        r = width / w
        dim = (width, int(h * r))

    return cv2.resize(image, dim, interpolation=inter)


def display_motion_levels(inp: File, width: int, dilates: int, blur: int):
    import sys

    cap = cv2.VideoCapture(inp.path)

    prev_frame = None
    gray = None
    total_pixels = None

    while cap.isOpened():
        if(gray is None):
            prev_frame = None
        else:
            prev_frame = gray

        ret, frame = cap.read()
        if(not ret):
            break

        frame = resize(frame, width=width)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
        if(blur > 0):
            gray = cv2.GaussianBlur(gray, (blur, blur), 0)

        if(prev_frame is not None):
            frame_delta = cv2.absdiff(prev_frame, gray)
            thresh = cv2.threshold(frame_delta, 25, 255, cv2.THRESH_BINARY)[1]

            if(dilates > 0):
                thresh = cv2.dilate(thresh, None, iterations=dilates)

            if(total_pixels is None):
                total_pixels = thresh.shape[0] * thresh.shape[1]

            sys.stdout.write('{:.20f}\n'.format(np.count_nonzero(thresh) / total_pixels))

    cap.release()
    cv2.destroyAllWindows()


def motion_detection(inp: File, threshold: float, log: Log, width: int,
    dilates: int, blur: int) -> np.ndarray:

    from auto_editor.utils.progressbar import ProgressBar

    log.conwrite('Analyzing video motion.')

    cap = cv2.VideoCapture(inp.path)

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) + 1

    log.debug('   - Cutting total_frames: {}'.format(total_frames))
    prev_frame = None
    gray = None
    has_motion = np.zeros((total_frames), dtype=np.bool_)
    total_pixels = None

    progress = ProgressBar(total_frames, 'Detecting motion')

    while cap.isOpened():
        if(gray is None):
            prev_frame = None
        else:
            prev_frame = gray

        ret, frame = cap.read()

        if(not ret):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame

        frame = resize(frame, width=width)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) # Convert frame to grayscale.
        if(blur > 0):
            gray = cv2.GaussianBlur(gray, (blur, blur), 0)

        if(prev_frame is not None):
            frame_delta = cv2.absdiff(prev_frame, gray)
            thresh = cv2.threshold(frame_delta, 25, 255, cv2.THRESH_BINARY)[1]

            # Dilate the thresholded image to fill in holes.
            if(dilates > 0):
                thresh = cv2.dilate(thresh, None, iterations=dilates)

            if(total_pixels is None):
                total_pixels = thresh.shape[0] * thresh.shape[1]

            if(np.count_nonzero(thresh) / total_pixels >= threshold):
                has_motion[cframe] = True

        progress.tick(cframe)

    cap.release()
    cv2.destroyAllWindows()

    log.conwrite('')

    return has_motion
