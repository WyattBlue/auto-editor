'''motion.py'''

# External Packages
import cv2
import numpy as np

# Motion detection algorithm based on this blog post:
# https://www.pyimagesearch.com/2015/05/25/basic-motion-detection-and-tracking-with-python-and-opencv/

def motionDetection(path, width, dilates, blur):
    cap = cv2.VideoCapture(path)
    prevFrame = None

    gray = None

    difference = [0]
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

    while cap.isOpened():
        if(gray is None):
            prevFrame = None
        else:
            prevFrame = gray

        ret, frame = cap.read()

        if(not ret):
            break

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

            difference.append(np.count_nonzero(thresh) / total)

    cap.release()
    cv2.destroyAllWindows()

    return difference


def main():
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument('--video', help='path to video file')
    args = ap.parse_args()

    difference = motionDetection(args.video, width=500, dilates=2, blur=True)

    print(difference)
    print(max(difference))

if(__name__ == '__main__'):
    main()
