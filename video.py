# Internal Packages
import time
import argparse
import datetime

# External Packages
import cv2
import imutils
import numpy as np
from imutils.video import VideoStream

# Motion detection algorithm based on this blog post:
# https://www.pyimagesearch.com/2015/05/25/basic-motion-detection-and-tracking-with-python-and-opencv/

ap = argparse.ArgumentParser()
ap.add_argument("-v", "--video", help="path to the video file")
args = ap.parse_args()

cap = cv2.VideoCapture(args.video)
prevFrame = None

gray = None

difference = [0]
total = None

while cap.isOpened():

    if(gray is None):
        prevFrame = None
    else:
        prevFrame = gray

    ret, frame = cap.read()

    if(not ret):
        break
    # resize the frame, convert it to grayscale, and blur it
    frame = imutils.resize(frame, width=500)
    gray = cv2.cvtColor(frame, cv2.COLOR_BGR2GRAY)
    gray = cv2.GaussianBlur(gray, (21, 21), 0)

    if(prevFrame is not None):
        frameDelta = cv2.absdiff(prevFrame, gray)
        thresh = cv2.threshold(frameDelta, 25, 255, cv2.THRESH_BINARY)[1]
        # dilate the thresholded image to fill in holes, then find contours
        # on thresholded image

        thresh = cv2.dilate(thresh, None, iterations=2)

        if(total is None):
            total = thresh.shape[0] * thresh.shape[1]

        difference.append(np.count_nonzero(thresh) / total)

# cleanup the camera and close any open windows
cap.release()
cv2.destroyAllWindows()

print(difference)


print(max(difference))