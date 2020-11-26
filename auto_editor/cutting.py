'''cutting.py'''
import numpy as np

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
    hasLoudAudio = np.zeros((audioFrameCount), dtype=np.uint8)

    if(maxAudioVolume == 0):
        log.error('The entire audio is silent.')

    # Calculate when the audio is loud or silent.
    for i in range(audioFrameCount):
        start = int(i * samplesPerFrame)
        end = min(int((i+1) * samplesPerFrame), audioSampleCount)
        audiochunks = audioData[start:end]
        if(getMaxVolume(audiochunks) / maxAudioVolume >= silentT):
            hasLoudAudio[i] = 1

    return hasLoudAudio


# Motion detection algorithm based on this blog post:
# https://www.pyimagesearch.com/2015/05/25/basic-motion-detection-and-tracking-with-python-and-opencv/
def motionDetection(path: str, ffprobe: str, motionThreshold: float, log,
    width, dilates, blur) -> np.ndarray:

    import cv2
    import subprocess
    from usefulFunctions import progressBar, conwrite

    cap = cv2.VideoCapture(path)

    # Find total frames
    if(path.endswith('.mp4') or path.endswith('.mov')):
        # Query Container
        cmd = [ffprobe, '-v', 'error', '-select_streams', 'v:0', '-show_entries',
            'stream=nb_frames', '-of', 'default=nokey=1:noprint_wrappers=1', path]
    else:
        # Count the number of frames (slow)
        cmd = [ffprobe, '-v', 'error', '-count_frames', '-select_streams', 'v:0',
            '-show_entries', 'stream=nb_read_frames', '-of',
            'default=nokey=1:noprint_wrappers=1', path]

    # Read what ffprobe piped in.
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    stdout, __ = process.communicate()
    output = stdout.decode()

    totalFrames = int(output)
    prevFrame = None
    gray = None
    hasMotion = np.zeros((totalFrames), dtype=np.uint8)
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

    import time
    beginTime = time.time()

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
        if(blur):
            gray = cv2.GaussianBlur(gray, (21, 21), 0)

        if(prevFrame is not None):
            frameDelta = cv2.absdiff(prevFrame, gray)
            thresh = cv2.threshold(frameDelta, 25, 255, cv2.THRESH_BINARY)[1]

            # Dilate the thresholded image to fill in holes.
            if(dilates > 0):
                thresh = cv2.dilate(thresh, None, iterations=dilates)

            if(total is None):
                total = thresh.shape[0] * thresh.shape[1]

            if(np.count_nonzero(thresh) / total >= motionThreshold):
                hasMotion[cframe] = 1

        progressBar(cframe, totalFrames, beginTime, title='Detecting motion')

    cap.release()
    cv2.destroyAllWindows()

    conwrite('')

    return hasMotion


def applySpacingRules(hasLoud, fps, frameMargin, minClip, minCut, ignore, cutOut, log):

    def removeSmall(hasLoud, limit, replace, with_):
        startP = 0
        active = False
        for j, item in enumerate(hasLoud):
            if(item == replace):
                if(not active):
                    startP = j
                    active = True
                # Special case for end.
                if(j == len(hasLoud) - 1):
                    if(j - startP < limit):
                        hasLoud[startP:j+1] = with_
            else:
                if(active):
                    if(j - startP < limit):
                        hasLoud[startP:j] = with_
                    active = False
        return hasLoud

    # Remove small loudness spikes
    hasLoud = removeSmall(hasLoud, minClip, replace=1, with_=0)
    # Remove small silences
    hasLoud = removeSmall(hasLoud, minCut, replace=0, with_=1)

    arrayLen = len(hasLoud)

    # Apply frame margin rules.
    includeFrame = np.zeros((arrayLen), dtype=np.uint8)
    for i in range(arrayLen):
        start = int(max(0, i - frameMargin))
        end = int(min(arrayLen, i+1+frameMargin))
        includeFrame[i] = min(1, np.max(hasLoud[start:end]))

    del hasLoud

    def setRange(includeFrame, syntaxRange, fps, with_):
        end = len(includeFrame) - 1
        for item in syntaxRange:
            pair = []

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

    # Apply ignore rules if applicable.
    if(ignore != []):
        includeFrame = setRange(includeFrame, ignore, fps, 1)

    # Cut out ranges.
    if(cutOut != []):
        includeFrame = setRange(includeFrame, cutOut, fps, 0)

    # Remove small clips created by applying other rules.
    includeFrame = removeSmall(includeFrame, minClip, replace=1, with_=0)
    # Remove small cuts created.
    includeFrame = removeSmall(includeFrame, minCut, replace=0, with_=1)

    # Convert long numpy array into properly formatted chunks list.
    chunks = []
    startP = 0
    for j in range(1, arrayLen):
        if(includeFrame[j] != includeFrame[j - 1]):
            chunks.append([startP, j, includeFrame[j-1]])
            startP = j
    chunks.append([startP, arrayLen, includeFrame[j]])

    # Return formatted chunk list and long silent/loud array.
    return chunks, includeFrame
