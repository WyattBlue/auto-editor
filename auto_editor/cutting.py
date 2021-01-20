'''cutting.py'''

import numpy as np

def combineArrs(audioList: np.ndarray, motionList: np.ndarray, based: str,
    log) -> np.ndarray:

    if(based == 'audio' or based == 'not_audio'):
        if(max(audioList) == 0):
            log.error('There was no place where audio exceeded the threshold.')
    if(based == 'motion' or based == 'not_motion'):
        if(max(motionList) == 0):
            log.error('There was no place where motion exceeded the threshold.')

    # Only raise a warning for other cases.
    if(audioList is not None and max(audioList) == 0):
        log.warning('There was no place where audio exceeded the threshold.')
    if(motionList is not None and max(motionList) == 0):
        log.warning('There was no place where motion exceeded the threshold.')

    hasLoud = None
    if(based == 'audio'):
        hasLoud = audioList

    if(based == 'motion'):
        hasLoud = motionList

    if(based == 'not_audio'):
        hasLoud = np.invert(audioList)

    if(based == 'not_motion'):
        hasLoud = np.invert(motionList)

    if(based == 'audio_and_motion'):
        hasLoud = audioList & motionList

    if(based == 'audio_or_motion'):
        hasLoud = audioList | motionList

    if(based == 'audio_xor_motion'):
        hasLoud = np.bitwise_xor(audioList, motionList)

    if(based == 'audio_and_not_motion'):
        hasLoud = audioList & np.invert(motionList)

    if(based == 'not_audio_and_motion'):
        hasLoud = np.invert(audioList) & motionList

    if(based == 'not_audio_and_not_motion'):
        hasLoud = np.invert(audioList) & np.invert(motionList)

    log.checkType(hasLoud, 'hasLoud', np.ndarray)
    return hasLoud


def audioToHasLoud(audioData: np.ndarray, sampleRate: int, silentT: float,
    fps: float, log) -> np.ndarray:

    import math

    audioSampleCount = audioData.shape[0]

    def getMaxVolume(s: np.ndarray) -> float:
        maxv = float(np.max(s))
        minv = float(np.min(s))
        return max(maxv, -minv)

    maxAudioVolume = getMaxVolume(audioData)

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
        if(getMaxVolume(audiochunks) / maxAudioVolume >= silentT):
            hasLoudAudio[i] = True

    return hasLoudAudio


# Motion detection algorithm based on this blog post:
# https://pyimagesearch.com/2015/05/25/basic-motion-detection-and-tracking-with-python-and-opencv/
def motionDetection(path: str, ffprobe, motionThreshold: float, log,
    width: int, dilates: int, blur: int) -> np.ndarray:

    import cv2
    import subprocess
    from usefulFunctions import ProgressBar

    cap = cv2.VideoCapture(path)

    # Find total frames
    if(path.endswith('.mp4') or path.endswith('.mov')):
        # Query Container
        cmd = [ffprobe.getPath(), '-v', 'error', '-select_streams', 'v:0', '-show_entries',
            'stream=nb_frames', '-of', 'default=nokey=1:noprint_wrappers=1', path]
    else:
        # Count the number of frames (slow)
        cmd = [ffprobe.getPath(), '-v', 'error', '-count_frames', '-select_streams', 'v:0',
            '-show_entries', 'stream=nb_read_frames', '-of',
            'default=nokey=1:noprint_wrappers=1', path]

    # Read what ffprobe piped in.
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()

    totalFrames = int(output) + 1
    log.debug(f'   - Cutting totalFrames: {totalFrames}')
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


def removeSmall(hasLoud: np.ndarray, lim: int, replace: bool, with_: bool) -> np.ndarray:
    startP = 0
    active = False
    for j, item in enumerate(hasLoud):
        if(item == replace):
            if(not active):
                startP = j
                active = True
            # Special case for end.
            if(j == len(hasLoud) - 1):
                if(j - startP < lim):
                    hasLoud[startP:j+1] = with_
        else:
            if(active):
                if(j - startP < lim):
                    hasLoud[startP:j] = with_
                active = False
    return hasLoud


def setRange(includeFrame: np.ndarray, syntaxRange, fps: float, with_: bool, log) -> np.ndarray:
    end = len(includeFrame) - 1
    for item in syntaxRange:
        pair = []

        if(item.count('-') > 1):
            log.error('Too many deliminators!')
        if(item.count('-') < 1):
            log.error('Invalid range. Use range syntax. ex: 5-10')

        for num in item.split('-'):
            if(num == 'start'):
                pair.append(0)
            elif(num == 'end'):
                pair.append(end)
            elif(float(num) < 0):
                # Negative numbers = frames from end.
                value = end - round(float(num) * fps)
                if(value < 0):
                    value = 0
                pair.append(value)
                del value
            else:
                pair.append(round(float(num) * fps))
        includeFrame[pair[0]:pair[1]+1] = with_
    return includeFrame


def applySpacingRules(hasLoud: np.ndarray, fps: float, frameMargin: int,
    minClip: int, minCut: int, ignore, cutOut, log):

    def secToFrames(value, fps):
        if(isinstance(value, str)):
            return int(float(value) * fps)
        return value

    frameMargin = secToFrames(frameMargin, fps)
    minClip = secToFrames(minClip, fps)
    minCut = secToFrames(minCut, fps)

    log.checkType(frameMargin, 'frameMargin', int)

    def cook(hasLoud: np.ndarray, minClip: int, minCut: int) -> np.ndarray:
        # Remove small loudness spikes
        hasLoud = removeSmall(hasLoud, minClip, replace=True, with_=False)
        # Remove small silences
        hasLoud = removeSmall(hasLoud, minCut, replace=False, with_=True)
        return hasLoud

    hasLoud = cook(hasLoud, minClip, minCut)

    arrayLen = len(hasLoud)

    # Apply frame margin rules.
    includeFrame = np.zeros((arrayLen), dtype=np.bool_)
    for i in range(arrayLen):
        start = int(max(0, i - frameMargin))
        end = int(min(arrayLen, i+1+frameMargin))
        includeFrame[i] = min(1, np.max(hasLoud[start:end]))

    del hasLoud

    # Apply ignore rules if applicable.
    if(ignore != []):
        includeFrame = setRange(includeFrame, ignore, fps, True, log)

    # Cut out ranges.
    if(cutOut != []):
        includeFrame = setRange(includeFrame, cutOut, fps, False, log)

    # Remove small clips/cuts created by applying other rules.
    includeFrame = cook(includeFrame, minClip, minCut)

    # Turn long silent/loud array to formatted chunk list.
    # Example: [True, True, True, False, False] => [[0, 3, 1], [3, 5, 0]]
    chunks = []
    startP = 0
    for j in range(1, arrayLen):
        if(includeFrame[j] != includeFrame[j - 1]):
            chunks.append([startP, j, int(includeFrame[j-1])])
            startP = j
    chunks.append([startP, arrayLen, int(includeFrame[j])])
    return chunks
