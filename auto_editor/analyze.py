'''analyze.py'''

from __future__ import division

import math

import numpy as np

def get_np_list(inp, audioData, sampleRate, fps, func):
    if(audioData is not None):
        audioSampleCount = audioData.shape[0]
        samplesPerFrame = sampleRate / fps
        audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
        return func((audioFrameCount), dtype=np.bool_)

    import cv2
    cap = cv2.VideoCapture(inp.path)
    totalFrames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) + 1
    return func((totalFrames), dtype=np.bool_)


def audio_detection(audioData, sampleRate, silent_threshold, fps, log):
    # type: (np.ndarray, int, float, float, Any) -> np.ndarray
    log.debug('Analyzing audio volume.')

    def getMaxVolume(s):
        # type: (np.ndarray) -> float
        maxv = float(np.max(s))
        minv = float(np.min(s))
        return max(maxv, -minv)

    maxAudioVolume = getMaxVolume(audioData)
    audioSampleCount = audioData.shape[0]

    samplesPerFrame = sampleRate / fps
    audioFrameCount = int(math.ceil(audioSampleCount / samplesPerFrame))
    hasLoudAudio = np.zeros((audioFrameCount), dtype=np.bool_)

    if(maxAudioVolume == 0):
        log.error('The entire audio is completely silent.')

    # Calculate when the audio is loud or silent.
    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        if(getMaxVolume(audiochunks) / maxAudioVolume >= silent_threshold):
            hasLoudAudio[i] = True

    return hasLoudAudio


def motion_detection(inp, motionThreshold, log, width, dilates, blur):
    # type: (Any, float, Any, int, int, int) -> np.ndarray

    # Based on this post:
    # https://pyimagesearch.com/2015/05/25/basic-motion-detection-and-tracking-with-python-and-opencv/

    import cv2
    from auto_editor.utils.progressbar import ProgressBar

    log.debug('Analyzing video motion.')

    cap = cv2.VideoCapture(inp.path)

    totalFrames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT)) + 1

    log.debug('   - Cutting totalFrames: {}'.format(totalFrames))
    prevFrame = None
    gray = None
    hasMotion = np.zeros((totalFrames), dtype=np.bool_)
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

    progress = ProgressBar(totalFrames, 'Detecting motion')

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

            if(np.count_nonzero(thresh) / total >= motionThreshold):
                hasMotion[cframe] = True

        progress.tick(cframe)

    cap.release()
    cv2.destroyAllWindows()

    log.conwrite('')

    return hasMotion
