'''render/av.py'''

# Internal Libraries
import os
import subprocess

# Included Libraries
from auto_editor.utils.progressbar import ProgressBar
from auto_editor.cutting import chunkify, chunks_to_has_loud
from .utils import properties, scale_to_sped, pix_fmt_allowed

def split_chunks(chunks, split):

    has_loud = chunks_to_has_loud(chunks)
    new_chunks = []

    duration = chunks[len(chunks) - 1][1]
    for i in range(0, duration, split):
        new_chunks.append(chunkify(has_loud[i:i+split]))

    return new_chunks


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

    new_chunks = split_chunks(chunks, int(SPLIT_DURATION * fps))

    pickle_data = []
    concat_file = ''
    n = 0
    for i in range(0, total_seconds, SPLIT_DURATION):

        vid_file = os.path.join(vid_space, '{}{}'.format(n, inp.ext))

        if(len(new_chunks[n]) == 1 and speeds[new_chunks[n][0][2]] == 99999):
            pass
        # elif(len(new_chunks[n]) == 1 and speeds[new_chunks[n][0][2]] == 1):
        #     concat_file += "file '{}'\n".format(vid_file)
        else:
            cmd = ['-i', inp.path, '-vcodec', 'copy']
            if(n != 0):
                cmd.extend(['-ss', str(i)])
            cmd.extend(['-to', str(i + SPLIT_DURATION), vid_file])
            ffmpeg.run(cmd)

            hmm = os.path.join(temp, 'video', 'sped{}{}'.format(n, inp.ext))
            concat_file += "file '{}'\n".format(hmm)

            pickle_data.append({
                'path': vid_file,
                'log': log,
                'n': n,
                'inp': inp.__dict__,
                'args': args,
                'chunks': new_chunks[n],
                'speeds': speeds,
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

    new_file = os.path.join(temp, 'joined{}'.format(inp.ext))

    joiner = os.path.join(temp, 'concat_list.txt')
    with open(joiner, 'w') as file:
        file.write(concat_file)

    ffmpeg.run(['-f', 'concat', '-safe', '0', '-i', joiner, '-c', 'copy', new_file])
    return new_file
