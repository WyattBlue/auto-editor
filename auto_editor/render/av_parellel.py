'''render/av.py'''

# NOTE: this is basically pseudo-code at this point.

# External Libraries
import av

# Internal Libraries
import os
import subprocess

# Included Libraries
from auto_editor.utils.progressbar import ProgressBar
from .utils import properties, scale_to_sped

def pix_fmt_allowed(pix_fmt):
    # type: (str) -> bool

    # From: github.com/PyAV-Org/PyAV/blob/main/av/video/frame.pyx
    allowed_formats = ['yuv420p', 'yuvj420p', 'rgb24', 'bgr24', 'argb', 'rgba',
        'abgr', 'bgra', 'gray', 'gray8', 'rgb8', 'bgr8', 'pal8']

    return pix_fmt in allowed_formats


def split_chunks(chunks, split):

    chunk_list = []
    new_chunks = []

    s_dir = split

    for chunk in chunks:
        new_chunks.append(chunk)

        s_dir -= chunk[1] - chunk[0]
        print(s_dir)

        if(s_dir == 0):
            chunk_list.append(new_chunks)
            new_chunks = []
            s_dir = split
        elif(s_dir < 0):
            pass

    if(new_chunks != []):
        chunk_list.append(new_chunks)
    return chunk_list

# if __name__ == '__main__':
    #chunks = [[0, 26, 1], [26, 34, 0], [34, 396, 1], [396, 410, 0], [410, 522, 1], [522, 1192, 0], [1192, 1220, 1], [1220, 1273, 0]]
    # chunks = [[0, 5, 1], [5, 10, 2], [10, 15, 3], [15, 20, 4]]
    # print(split_chunks(chunks, split=2))

def multi_render(pickle_data):

    try:
        import av

        path = pickle_data['path']

        log = pickle_data['log']
        fps = pickle_data['fps']
        n = pickle_data['n']
        args = pickle_data['args']
        speeds = pickle_data['speeds']
        chunks = pickle_data['chunks']
        temp = pickle_data['temp']
        ffmpeg = pickle_data['ffmpeg']

        class AttrDict(dict):
            def __init__(self, *args, **kwargs):
                super(AttrDict, self).__init__(*args, **kwargs)
                self.__dict__ = self

        inp = AttrDict(pickle_data['inp'])

        inp.path = path
        print(inp.path)

        input_ = av.open(path)
        pix_fmt = input_.streams.video[0].pix_fmt

        # # if(not pix_fmt_allowed(pix_fmt)):
        # #     throw_pix_fmt(inp, pix_fmt, log)

        inputVideoStream = input_.streams.video[0]
        inputVideoStream.thread_type = 'AUTO'

        width = inputVideoStream.width
        height = inputVideoStream.height

        log.debug('pix_fmt: {}'.format(pix_fmt))

        cmd = ['-hide_banner', '-y', '-f', 'rawvideo', '-vcodec', 'rawvideo',
            '-pix_fmt', pix_fmt, '-s', '{}*{}'.format(width, height), '-framerate', str(fps),
            '-i', '-', '-pix_fmt', pix_fmt]

        correct_ext = '.mp4' if inp.ext == '.gif' else inp.ext

        spedup = os.path.join(temp, 'video', 'sped{}{}'.format(n, correct_ext))
        scale = os.path.join(temp, 'video', 'scale{}{}'.format(n, correct_ext))

        if(args.scale != 1):
            cmd.extend(['-vf', 'scale=iw*{}:ih*{}'.format(args.scale, args.scale), scale])
        else:
            cmd = properties(cmd, args, inp)
            cmd.append(spedup)

        process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE)

        inputEquavalent = 0.0
        outputEquavalent = 0
        index = 0
        chunk = chunks.pop(0)

        try:
            for packet in input_.demux(inputVideoStream):
                for frame in packet.decode():
                    index += 1
                    if(len(chunks) > 0 and index >= chunk[1]):
                        chunk = chunks.pop(0)

                    if(speeds[chunk[2]] != 99999):
                        inputEquavalent += (1 / speeds[chunk[2]])

                    while inputEquavalent > outputEquavalent:
                        in_bytes = frame.to_ndarray().tobytes()
                        process2.stdin.write(in_bytes)
                        outputEquavalent += 1

            process2.stdin.close()
            process2.wait()
        except BrokenPipeError:
            log.print(cmd)
            process2 = ffmpeg.Popen(cmd, stdin=subprocess.PIPE)
            log.error('Broken Pipe Error!')

        if(args.scale != 1):
            scale_to_sped(ffmpeg, spedup, scale, inp, args, temp)

        print('hi')
        import time
        time.sleep(1)
    except Exception as e:
        print(e)
        raise e


def render_av(ffmpeg, inp, args, chunks, speeds, fps, has_vfr, temp, log):
    totalFrames = chunks[len(chunks) - 1][1]

    SPLIT_DURATION = 5 # Split the video into 5 second chunks

    total_seconds = int(totalFrames / fps)

    vid_space = os.path.join(temp, 'video')
    os.mkdir(vid_space)

    split_prog = ProgressBar(total_seconds, 'Splitting video',
        args.machine_readable_progress, args.no_progress)

    pickle_data = []
    n = 0
    for i in range(0, total_seconds, SPLIT_DURATION):
        vid_file = os.path.join(vid_space, '{}{}'.format(n, inp.ext))
        ffmpeg.run(['-i', inp.path, '-vcodec', 'copy', '-ss', str(i), '-to',
            str(i + SPLIT_DURATION), vid_file])

        pickle_data.append({
            'path': vid_file,
            'log': log,
            'n': n,
            'inp': inp.__dict__,
            'args': args,
            'chunks': [[0, 75, 1], [75, 150, 0]],
            'speeds': [99999, 1],
            'fps': fps,
            'temp': temp,
            'ffmpeg': ffmpeg,
            })
        split_prog.tick(i)
        n += 1

    # Using multi-processing, which is better for CPU bound tasks.
    # You can try threading, which is better for IO and networking bound
    # tasks just by changing ProcessPoolExecutor() to ThreadPoolExecutor()

    import concurrent.futures
    with concurrent.futures.ProcessPoolExecutor() as executor:
        executor.map(multi_render, pickle_data)


    # TODO: add video concatenating script

    print(vid_space)
    quit()

    return spedup

