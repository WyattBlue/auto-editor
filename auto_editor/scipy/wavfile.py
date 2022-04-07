# Forked from: github.com/scipy/scipy/blob/main/scipy/io/wavfile.py

import io
import numpy
import struct

from typing import Tuple


PCM = 0x0001
IEEE_FLOAT = 0x0003
EXTENSIBLE = 0xFFFE

def _read_fmt_chunk(
    fid: io.BufferedReader, is_big_endian: bool
) -> Tuple[int, int, int, int, int]:
    if is_big_endian:
        fmt = ">"
    else:
        fmt = "<"

    size: int = struct.unpack(fmt + "I", fid.read(4))[0]

    if size < 16:
        raise ValueError("Binary structure of wave file is not compliant")

    res = struct.unpack(fmt + "HHIIHH", fid.read(16))
    bytes_read = 16

    format_tag, channels, fs, bytes_per_second, block_align, bit_depth = res

    if format_tag == EXTENSIBLE and size >= (16 + 2):
        ext_chunk_size = struct.unpack(fmt + "H", fid.read(2))[0]
        bytes_read += 2
        if ext_chunk_size >= 22:
            extensible_chunk_data = fid.read(22)
            bytes_read += 22
            raw_guid = extensible_chunk_data[2 + 4 : 2 + 4 + 16]
            # GUID template {XXXXXXXX-0000-0010-8000-00AA00389B71} (RFC-2361)
            # MS GUID byte order: first three groups are native byte order,
            # rest is Big Endian
            if is_big_endian:
                tail = b"\x00\x00\x00\x10\x80\x00\x00\xAA\x00\x38\x9B\x71"
            else:
                tail = b"\x00\x00\x10\x00\x80\x00\x00\xAA\x00\x38\x9B\x71"
            if raw_guid.endswith(tail):
                format_tag = struct.unpack(fmt + "I", raw_guid[:4])[0]
        else:
            raise ValueError("Binary structure of wave file is not compliant")

    if format_tag not in {PCM, IEEE_FLOAT}:
        raise ValueError(
            f"Encountered unknown format tag: {format_tag:#06x}, while reading fmt chunk."
        )

    # move file pointer to next chunk
    if size > bytes_read:
        fid.read(size - bytes_read)

    # fmt should always be 16, 18 or 40, but handle it just in case
    _handle_pad_byte(fid, size)

    return format_tag, channels, fs, block_align, bit_depth


def _read_data_chunk(
    fid: io.BufferedReader,
    format_tag: int,
    channels: int,
    bit_depth: int,
    is_big_endian: bool,
    block_align: int,
) -> numpy.ndarray:
    if is_big_endian:
        fmt = ">"
    else:
        fmt = "<"

    # Size of the data subchunk in bytes
    size: int = struct.unpack(fmt + "I", fid.read(4))[0]

    # Number of bytes per sample (sample container size)
    bytes_per_sample = block_align // channels
    n_samples = size // bytes_per_sample

    if format_tag == PCM:
        if 1 <= bit_depth <= 8:
            dtype = "u1"  # WAV of 8-bit integer or less are unsigned
        elif bytes_per_sample in {3, 5, 6, 7}:
            # No compatible dtype.  Load as raw bytes for reshaping later.
            dtype = "V1"
        elif bit_depth <= 64:
            # Remaining bit depths can map directly to signed numpy dtypes
            dtype = f"{fmt}i{bytes_per_sample}"
        else:
            raise ValueError(
                f"Unsupported bit depth: the WAV file has {bit_depth}-bit integer data."
            )
    elif format_tag == IEEE_FLOAT:
        if bit_depth in {32, 64}:
            dtype = f"{fmt}f{bytes_per_sample}"
        else:
            raise ValueError(
                f"Unsupported bit depth: the WAV file has {bit_depth}-bit floating-point data."
            )
    else:
        raise ValueError(
            f"Unknown wave file format: {format_tag:#06x}. Supported formats: PCM, IEEE_FLOAT"
        )

    start = fid.tell()

    if bytes_per_sample in (1, 2, 4, 8):
        data = numpy.memmap(
            fid, dtype=dtype, mode="c", offset=start, shape=(n_samples,)
        )
        fid.seek(start + size)
    else:
        try:
            count = size if dtype == "V1" else n_samples
            data = numpy.fromfile(fid, dtype=dtype, count=count)
        except io.UnsupportedOperation:  # not a C-like file
            fid.seek(start, 0)  # just in case it seeked, though it shouldn't
            data = numpy.frombuffer(fid.read(size), dtype=dtype)

        if dtype == "V1":
            # Rearrange raw bytes into smallest compatible numpy dtype
            dt = numpy.int32 if bytes_per_sample == 3 else numpy.int64
            a = numpy.zeros((len(data) // bytes_per_sample, dt().itemsize), dtype="V1")
            a[:, -bytes_per_sample:] = data.reshape((-1, bytes_per_sample))
            data = a.view(dt).reshape(a.shape[:-1])

    _handle_pad_byte(fid, size)

    if channels > 1:
        try:
            data = data.reshape(-1, channels)
        except ValueError:
            data = data[:-1].reshape(-1, channels)

    return data


def _skip_unknown_chunk(fid: io.BufferedReader, is_big_endian: bool) -> None:
    if is_big_endian:
        fmt = ">I"
    else:
        fmt = "<I"

    data = fid.read(4)
    # call unpack() and seek() only if we have really read data from file
    # otherwise empty read at the end of the file would trigger
    # unnecessary exception at unpack() call
    # in case data equals somehow to 0, there is no need for seek() anyway
    if data:
        size = struct.unpack(fmt, data)[0]
        fid.seek(size, 1)
        _handle_pad_byte(fid, size)


def _read_riff_chunk(fid: io.BufferedReader) -> Tuple[int, bool]:

    # TODO: Add support for RF64

    str1 = fid.read(4)  # File signature
    if str1 == b"RIFF":
        is_big_endian = False
        fmt = "<I"
    elif str1 == b"RIFX":
        is_big_endian = True
        fmt = ">I"
    else:
        raise ValueError(
            f"File format {repr(str1)} not understood. Only 'RIFF' and 'RIFX' supported."
        )

    # Size of entire file
    file_size: int = struct.unpack(fmt, fid.read(4))[0] + 8

    str2 = fid.read(4)
    if str2 != b"WAVE":
        raise ValueError(f"Not a WAV file. RIFF form type is {repr(str2)}.")

    return file_size, is_big_endian


def _handle_pad_byte(fid: io.BufferedReader, size: int) -> None:
    # "If the chunk size is an odd number of bytes, a pad byte with value zero
    # is written after ckData." So we need to seek past this after each chunk.
    if size % 2:
        fid.seek(1, 1)


def read(filename: str) -> Tuple[int, numpy.ndarray]:
    fid = open(filename, "rb")

    try:
        file_size, is_big_endian = _read_riff_chunk(fid)
        fmt_chunk_received = False
        data_chunk_received = False
        while fid.tell() < file_size:
            # read the next chunk
            chunk_id = fid.read(4)

            if not chunk_id:
                if data_chunk_received:
                    # End of file but data successfully read
                    break
                else:
                    raise ValueError("Unexpected end of file.")
            elif len(chunk_id) < 4:
                if fmt_chunk_received and data_chunk_received:
                    pass
                else:
                    raise ValueError(f"Incomplete chunk ID: {repr(chunk_id)}")

            if chunk_id == b"fmt ":
                fmt_chunk_received = True
                format_tag, channels, fs, block_align, bit_depth = _read_fmt_chunk(
                    fid, is_big_endian
                )
            elif chunk_id == b"data":
                data_chunk_received = True
                if not fmt_chunk_received:
                    raise ValueError("No fmt chunk before data")
                data = _read_data_chunk(
                    fid,
                    format_tag,
                    channels,
                    bit_depth,
                    is_big_endian,
                    block_align,
                )
            else:
                _skip_unknown_chunk(fid, is_big_endian)

    finally:
        fid.seek(0)

    return fs, data
