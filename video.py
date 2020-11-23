# import the necessary packages
from imutils.video import VideoStream
import argparse
import datetime
import imutils
import time
import cv2

import numpy as np

ap = argparse.ArgumentParser()
ap.add_argument("-v", "--video", help="path to the video file")
ap.add_argument("-a", "--min-area", type=int, default=500, help="minimum area size")
args = vars(ap.parse_args())
if args.get("video", None) is None:
    vs = VideoStream(src=0).start()
else:
    vs = cv2.VideoCapture(args["video"])
prevFrame = None

gray = None

while True:

    if(gray is None):
        prevFrame = None
    else:
        prevFrame = gray

    frame = vs.read()
    frame = frame if args.get("video", None) is None else frame[1]

    if frame is None:
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

        print(np.count_nonzero(thresh))
        cv2.imshow("Thresh", thresh)


    # cv2.imshow("Frame Delta", frameDelta)
    key = cv2.waitKey(1) & 0xFF
    # if the `q` key is pressed, break from the lop
    if key == ord("q"):
        break
# cleanup the camera and close any open windows
vs.stop() if args.get("video", None) is None else vs.release()
cv2.destroyAllWindows()