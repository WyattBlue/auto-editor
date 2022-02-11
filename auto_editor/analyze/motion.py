import av
import numpy as np
from PIL import Image, ImageOps, ImageChops, ImageFilter

from auto_editor.utils.progressbar import ProgressBar


def new_size(size, width):
    h, w = size
    r = width / w
    return width, int(h * r)


def display_motion_levels(path: str, width: int, blur: int):

    # TODO: Overwrite level when index is repeated. (Occurs in VFR videos)

    container = av.open(path, 'r')

    video_stream = container.streams.video[0]
    video_stream.thread_type = 'AUTO'

    prev_image = None
    image = None
    total_pixels = None

    for frame in container.decode(video_stream):
        if image is None:
            prev_image = None
        else:
            prev_image = image

        image = frame.to_image()

        if total_pixels is None:
            total_pixels = image.size[0] * image.size[1]

        image.thumbnail(new_size(image.size, width))
        image = ImageOps.grayscale(image)

        if blur > 0:
            image = image.filter(ImageFilter.GaussianBlur(radius=blur))

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))

            sys.stdout.write('{:.20f}\n'.format(count))


def motion_detection(path: str, fps: float, threshold: float, progress: ProgressBar,
    width: int, blur: int) -> np.ndarray:

    container = av.open(path, 'r')

    video_stream = container.streams.video[0]
    video_stream.thread_type = 'AUTO'

    inaccurate_dur = int(float(video_stream.duration * video_stream.time_base) * fps)

    progress.start(inaccurate_dur, 'Analyzing motion')

    prev_image = None
    image = None
    total_pixels = None
    index = 0

    has_motion = np.zeros((1024), dtype=np.bool_)

    for frame in container.decode(video_stream):
        if image is None:
            prev_image = None
        else:
            prev_image = image

        index = int(frame.time * fps)

        progress.tick(index)

        if index > len(has_motion) - 1:
            has_motion = np.concatenate(
                (has_motion, np.zeros((len(has_motion)), dtype=np.bool_)), axis=0
            )

        image = frame.to_image()

        if total_pixels is None:
            total_pixels = image.size[0] * image.size[1]

        image.thumbnail(new_size(image.size, width))
        image = ImageOps.grayscale(image)

        if blur > 0:
            image = image.filter(ImageFilter.GaussianBlur(radius=blur))

        if prev_image is not None:
            count = np.count_nonzero(ImageChops.difference(prev_image, image))

            if count / total_pixels >= threshold:
                has_motion[index] = True

    progress.end()
    return has_motion[:index]
