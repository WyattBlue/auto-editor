import av

from auto_editor.timeline import v3
from auto_editor.utils.log import Log

import numpy as np

def find_chunk(target: int, chunks: list[tuple[int, int, float]]) -> int:
    low = 0
    high = len(chunks) - 1

    while low <= high:
        mid = (low + high) // 2
        start, end, _ = chunks[mid]

        if start <= target < end:
            return mid
        elif target < start:
            high = mid - 1
        else:
            low = mid + 1

    raise ValueError("")


def chunk_unroll(chunks: list[tuple[int, int, float]]) -> np.ndarray:
    result = np.zeros((chunks[-1][1]), dtype=np.float64)

    for chunk in chunks:
        result[chunk[0]:chunk[1]] = chunk[2]

    return result

# TODO: This
def make_new_subtitles(tl: v3, old_out: str, out_path: str, log: Log) -> None:
    if tl.v1 is None:
        return None

    try:
        input_cont = av.open(tl.v1.source.path, "r")
        processed = av.open(old_out, "r")
        output = av.open(out_path, "w")
    except Exception as e:
        log.error(e)

    out_streams = {}
    for stream in processed.streams:
        if stream.type in ("video", "audio", "data", "attachment", ""):
            out_streams[stream.index] = output.add_stream(template=stream)

    for stream in input_cont.streams:
        if stream.type == "subtitle":
            out_streams[stream.index] = output.add_stream(template=stream)

    for packet in processed.demux():
        packet.stream = out_streams[packet.stream.index]
        output.mux(packet)

    scroll = chunk_unroll(tl.v1.chunks)
    lock = 0
    for packet in input_cont.demux():
        if packet.dts is None:
            continue

        if packet.stream.type == "subtitle":
            if packet.pts is None or packet.duration is None:
                continue

            if not packet.decode():
                continue  # Skip empty packets

            start = round(packet.pts * packet.time_base * tl.tb)
            end = round((packet.pts + packet.duration) * packet.time_base * tl.tb)

            new_duration = 0.0
            for i in range(start, end):
                if i < len(scroll) and scroll[i] != 99999.0:
                    new_duration += 1 * scroll[i]

            new_duration = int(new_duration)
            if new_duration > 0.0:
                packet.pts = lock
                packet.dts = lock

                lock += 1000

                packet.duration = int(new_duration / (packet.time_base * tl.tb))
                packet.stream = out_streams[packet.stream.index]
                output.mux_one(packet)

    output.close()
    processed.close()
    input_cont.close()
