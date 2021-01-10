'''cvVideo.py'''

import numpy as np

# Included functions
from usefulFunctions import ProgressBar

def cvVideo(vidFile: str, chunks: list, includeFrame: np.ndarray, speeds: list,
    fps, machineReadable, hideBar, temp, log):

    import cv2

    cap = cv2.VideoCapture(vidFile)
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')

    out = cv2.VideoWriter(f'{temp}/spedup.mp4', fourcc, fps, (width, height))

    log.checkType(vidFile, 'vidFile', str)
    log.checkType(includeFrame, 'includeFrame', np.ndarray)

    if(speeds[0] == 99999 and speeds[1] != 99999):
        totalFrames = int(np.where(includeFrame == True)[0][-1])
        cframe = int(np.where(includeFrame == True)[0][0])
    elif(speeds[0] != 99999 and speeds[1] == 99999):
        totalFrames = int(np.where(includeFrame == False)[0][-1])
        cframe = int(np.where(includeFrame == False)[0][0])
    else:
        totalFrames = chunks[len(chunks) - 1][1]
        cframe = 0

    starting = cframe
    cap.set(cv2.CAP_PROP_POS_FRAMES, cframe)
    remander = 0
    framesWritten = 0

    videoProgress = ProgressBar(totalFrames - starting, 'Creating new video',
        machineReadable, hideBar)

    while cap.isOpened():
        ret, frame = cap.read()
        if(not ret or cframe > totalFrames):
            break

        cframe = int(cap.get(cv2.CAP_PROP_POS_FRAMES)) # current frame
        try:
            state = includeFrame[cframe]
        except IndexError:
            state = False

        mySpeed = speeds[state]

        if(mySpeed != 99999):
            doIt = (1 / mySpeed) + remander
            for __ in range(int(doIt)):
                out.write(frame)
                framesWritten += 1
            remander = doIt % 1

        videoProgress.tick(cframe - starting)
    log.debug(f'\n   - Frames Written: {framesWritten}')
    log.debug(f'   - Starting: {starting}')
    log.debug(f'   - Total Frames: {totalFrames}')

    if(log.is_debug):
        log.debug('Writing the output file.')
    else:
        log.conwrite('Writing the output file.')

    cap.release()
    out.release()
    cv2.destroyAllWindows()