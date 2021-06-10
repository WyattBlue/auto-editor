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
def motionDetection(inp, motionThreshold: float, log, width: int, dilates: int,
    blur: int) -> np.ndarray:

    import cv2
    from auto_editor.utils.progressbar import ProgressBar

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


def isNumber(val):
    return val.replace('.', '', 1).isdigit()

def setRange(hasLoud: np.ndarray, syntaxRange, fps: float, with_, log) -> np.ndarray:

    def replaceVarsWithVals(item) -> int:
        nonlocal hasLoud
        nonlocal log

        if(isNumber(item)):
            return int(item)
        if(item == 'start'):
            return 0
        if(item == 'end'):
            return len(hasLoud)
        if(item.startswith('sec')):
            log.error('Seconds unit not implemented in this function.')
        log.error('Variable {} not avaiable in this context.'.format(item))

    def ConvertToFrames(num) -> int:
        num = replaceVarsWithVals(num)
        if(num < 0):
            num = len(hasLoud) - num
        return num

    for item in syntaxRange:
        pair = list(map(ConvertToFrames, item))
        hasLoud[pair[0]:pair[1]] = with_
    return hasLoud


def secToFrames(value, fps):
    if(isinstance(value, str)):
        return int(float(value) * fps)
    return value

def cook(hasLoud: np.ndarray, minClip: int, minCut: int) -> np.ndarray:
    # Remove small loudness spikes
    hasLoud = removeSmall(hasLoud, minClip, replace=1, with_=0)
    # Remove small silences
    hasLoud = removeSmall(hasLoud, minCut, replace=0, with_=1)
    return hasLoud


# Turn long silent/loud array to formatted chunk list.
# Example: [True, True, True, False, False] => [[0, 3, 1], [3, 5, 0]]
def chunkify(hasLoud, hasLoudLengthCache=None) -> list:
    if(hasLoudLengthCache is None):
        hasLoudLengthCache = len(hasLoud)

    chunks = []
    startP = 0
    for j in range(1, hasLoudLengthCache):
        if(hasLoud[j] != hasLoud[j - 1]):
            chunks.append([startP, j, int(hasLoud[j-1])])
            startP = j
    chunks.append([startP, hasLoudLengthCache, int(hasLoud[j])])
    return chunks


def applySpacingRules(hasLoud: np.ndarray, speeds, fps: float, args, log) -> list:
    frameMargin = secToFrames(args.frame_margin, fps)
    minClip = secToFrames(args.min_clip_length, fps)
    minCut = secToFrames(args.min_cut_length, fps)

    hasLoud = cook(hasLoud, minClip, minCut)
    hasLoudLengthCache = len(hasLoud)

    def applyFrameMargin(hasLoud, hasLoudLengthCache, frameMargin) -> np.ndarray:
        new = np.zeros((hasLoudLengthCache), dtype=np.uint8)
        for i in range(hasLoudLengthCache):
            start = int(max(0, i - frameMargin))
            end = int(min(hasLoudLengthCache, i+1+frameMargin))
            new[i] = min(1, np.max(hasLoud[start:end]))
        return new

    hasLoud = applyFrameMargin(hasLoud, hasLoudLengthCache, frameMargin)

    if(args.mark_as_loud != []):
        hasLoud = setRange(hasLoud, args.mark_as_loud, fps, 1, log)

    if(args.mark_as_silent != []):
        hasLoud = setRange(hasLoud, args.mark_as_silent, fps, 0, log)

    # Remove small clips/cuts created by applying other rules.
    hasLoud = cook(hasLoud, minClip, minCut)

    if(args.cut_out != []):
        cut_speed_index = speeds.index(99999)
        hasLoud = setRange(hasLoud, args.cut_out, fps, cut_speed_index, log)

    if(args.set_speed_for_range != []):
        for item in args.set_speed_for_range:
            my_speed_index = speeds.index(float(item[0]))
            hasLoud = setRange(hasLoud, [item[1:]], fps, my_speed_index, log)

    return chunkify(hasLoud, hasLoudLengthCache)


def applyBasicSpacing(hasLoud: np.ndarray, fps: float, minClip: int, minCut: int, log):
    minClip = secToFrames(minClip, fps)
    minCut = secToFrames(minCut, fps)

    hasLoud = cook(hasLoud, minClip, minCut)
    return chunkify(hasLoud)


def merge(start_list: np.ndarray, end_list: np.ndarray) -> np.ndarray:
    merge = np.zeros((len(start_list)), dtype=np.bool_)

    startP = 0
    for item in start_list:
        if(item == True):
            where_list = np.where(end_list[startP:])[0]
            if(len(where_list) > 0):
                merge[startP:where_list[0]] = True
        startP += 1
    return merge


def handleBoolExp(val: str, data, sampleRate, fps, log) -> list:
    invert = False

    if('>' in val and '<' in val):
        log.error('Cannot have both ">" and "<" in same expression.')
    if('>' in val):
        exp = val.split('>')
    elif('<' in val):
        exp = val.split('<')
        invert = True
    else:
        log.error('audio array needs ">" or "<".')

    if(len(exp) != 2):
        log.error(f'Only one expression supported, not {len(exp)-1}.')

    if(data is None or sampleRate is None):
        log.error('No audio data found.')

    new_list = audioToHasLoud(data, sampleRate, float(exp[1]), fps, log)

    if(invert):
        new_list = np.invert(new_list)

    return new_list


def applyRects(cmdRects, audioData, sampleRate, fps, log):
    from auto_editor.utils.func import hex_to_bgr

    rects = []
    for ms in cmdRects:
        if(len(ms) < 6):
            log.error('Too few comma arguments for rectangle option.')

        if(len(ms) > 8):
            log.error('Too many comma arguments for rectangle option.')

        start, end, x1, y1, x2, y2 = ms[:6]

        color = '#000'
        thickness = -1
        if(len(ms) > 6):
            color = ms[6]
        if(len(ms) > 7):
            thickness = int(ms[7])
        color = hex_to_bgr(color, log)

        # Handle Boolean Expressions. Mostly the same as zoom.
        start_list, end_list = None, None
        if(start.startswith('audio')):
            start_list = handleBoolExp(start, audioData, sampleRate, fps, log)

        if(end.startswith('audio')):
            if(start_list is None):
                log.error('The start parameter must also have a boolean expression.')
            end_list = handleBoolExp(end, audioData, sampleRate, fps, log)

        if(start_list is None):
            rects.append(['rectangle', start, end, x1, y1, x2, y2, color, thickness])

        elif(end_list is None):
            # Handle if end is not a boolean expression.
            indexs = np.where(start_list)[0]
            if(indexs != []):
                rects.append(['rectangle', str(indexs[0]), end, x1, y1, x2, y2, color,
                    thickness])
        else:
            chunks = applyBasicSpacing(merge(start_list, end_list), fps, 0, 0, log)
            for item in chunks:
                if(item[2] == 1):
                    rects.append(['rectangle', str(item[0]), str(item[1]), x1, y1, x2, y2,
                        color, thickness])

            if(rects == []):
                log.warning('No rectangles applied.')
            else:
                log.print(f' {len(rects)} rectangles applied.')

    return rects


def applyZooms(cmdZooms, audioData, sampleRate, fps, log):
    zooms = []
    for ms in cmdZooms:

        start, end = ms[:2]

        start_zoom = float(ms[2])

        if(len(ms) == 3):
            end_zoom = start_zoom
        else:
            end_zoom = float(ms[3])

        x = 'centerX'
        y = 'centerY'
        inter = 'linear'
        hold = None

        if(len(ms) > 4):
            x, y = ms[4:6]

        if(len(ms) > 6):
            inter = ms[6]

        if(len(ms) > 7):
            hold = ms[7]

        start_list, end_list = None, None
        if(start.startswith('audio')):
            start_list = handleBoolExp(start, audioData, sampleRate, fps, log)

        if(end.startswith('audio')):
            if(start_list is None):
                log.error('The start parameter must also have a boolean expression.')
            end_list = handleBoolExp(end, audioData, sampleRate, fps, log)

        if(start_list is None):
            zooms.append(['zoom', start, end, start_zoom, end_zoom, x, y, inter, hold])

        elif(end_list is None):
            # Handle if end is not a boolean expression.
            indexs = np.where(start_list)[0]
            if(indexs != []):
                zooms.append(['zoom', str(indexs[0]), end, start_zoom, end_zoom, x, y,
                    inter, hold])
        else:
            chunks = applyBasicSpacing(merge(start_list, end_list), fps, 0, 0, log)
            for item in chunks:
                if(item[2] == 1):
                    zooms.append(['zoom', str(item[0]), str(item[1]), start_zoom,
                        end_zoom, x, y, inter, hold])

            if(zooms == []):
                log.warning('No zooms applied.')
            else:
                log.print(f' {len(zooms)} zooms applied.')

    log.debug(zooms)
    return zooms
