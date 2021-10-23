'''analyze.py'''

import math

import numpy as np

from auto_editor.utils.progressbar import ProgressBar

def get_np_list(inp, audio_samples, sample_rate, fps, func):
    if(audio_samples is not None):
        sample_count = audio_samples.shape[0]
        sample_rate_per_frame = sample_rate / fps
        audio_frame_count = int(math.ceil(sample_count / sample_rate_per_frame))
        return func((audio_frame_count), dtype=np.bool_)

    import cv2
    cap = cv2.VideoCapture(inp.path)
    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) + 1
    return func((total_frames), dtype=np.bool_)


def audio_detection(audio_samples, sample_rate, silent_threshold, fps, log):
    # type: (np.ndarray, int, float, float, Any) -> np.ndarray
    log.conwrite('Analyzing audio volume.')

    def get_max_volume(s):
        # type: (np.ndarray) -> float
        maxv = float(np.max(s))
        minv = float(np.min(s))
        return max(maxv, -minv)

    max_volume = get_max_volume(audio_samples)
    sample_count = audio_samples.shape[0]

    sample_rate_per_frame = sample_rate / fps
    audio_frame_count = int(math.ceil(sample_count / sample_rate_per_frame))
    hasLoudAudio = np.zeros((audio_frame_count), dtype=np.bool_)

    if(max_volume == 0):
        log.error('The entire audio is completely silent.')

    # Calculate when the audio is loud or silent.
    for i in range(audio_frame_count):
        start = int(i * sample_rate_per_frame)
        end = min(int((i+1) * sample_rate_per_frame), sample_count)
        audiochunks = audio_samples[start:end]
        if(get_max_volume(audiochunks) / max_volume >= silent_threshold):
            hasLoudAudio[i] = True

    return hasLoudAudio


def motion_detection(inp, threshold, log, width, dilates, blur):
    # type: (Any, float, Any, int, int, int) -> np.ndarray

    # Based on this post:
    # https://pyimagesearch.com/2015/05/25/basic-motion-detection-and-tracking-with-python-and-opencv/

    import cv2

    log.conwrite('Analyzing video motion.')

    cap = cv2.VideoCapture(inp.path)

    total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) + 1

    log.debug('   - Cutting total_frames: {}'.format(total_frames))
    prevFrame = None
    gray = None
    has_motion = np.zeros((total_frames), dtype=np.bool_)
    total = None

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

    progress = ProgressBar(total_frames, 'Detecting motion')

    while cap.isOpened():
        if(gray is None):
            prevFrame = None
        else:
            prevFrame = gray

        ret, frame = cap.read()

        if(not ret):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame

        frame = resize(frame, width=width)
        gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY) # Convert frame to grayscale.
        if(blur > 0):
            gray = cv2.GaussianBlur(gray, (blur, blur), 0)

        if(prevFrame is not None):
            frameDelta = cv2.absdiff(prevFrame, gray)
            thresh = cv2.threshold(frameDelta, 25, 255, cv2.THRESH_BINARY)[1]

            # Dilate the thresholded image to fill in holes.
            if(dilates > 0):
                thresh = cv2.dilate(thresh, None, iterations=dilates)

            if(total is None):
                total = thresh.shape[0] * thresh.shape[1]

            if(np.count_nonzero(thresh) / total >= threshold):
                has_motion[cframe] = True

        progress.tick(cframe)

    cap.release()
    cv2.destroyAllWindows()

    log.conwrite('')

    return has_motion
