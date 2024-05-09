import av

from auto_editor.timeline import v3
from auto_editor.utils.log import Log


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
        if stream.type in ("video", "audio", "data", "attachment"):
            out_streams[stream.index] = output.add_stream(template=stream)

    for stream in input_cont.streams:
        if stream.type == "subtitle":
            out_streams[stream.index] = output.add_stream(template=stream)

    for packet in processed.demux():
        if packet.stream.index in out_streams:
            packet.stream = out_streams[packet.stream.index]
            output.mux_one(packet)

    chunks = tl.v1.chunks
    new_start = 0
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

            index = find_chunk(start, chunks)

            new_duration = 0.0
            for chunk in chunks[index:]:
                if chunk[1] >= end:
                    break
                if chunk[2] == 0.0 or chunk[2] >= 99999.0:
                    pass
                else:
                    new_duration += (chunk[1] - chunk[0]) / chunk[2]

            new_start += packet.pts
            packet.pts = new_start
            packet.dts = packet.pts

            if new_duration > 0:
                packet.duration = round(new_duration / tl.tb / packet.time_base)
                packet.stream = out_streams[packet.stream.index]
                output.mux_one(packet)

    input_cont.close()
    processed.close()
    output.close()
