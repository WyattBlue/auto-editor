---
title: The Optimization That Reduced Memory Consumption by 99%
author: WyattBlue
date: April 11, 2023
desc: Every time auto-editor processes a media file with audio, auto-editor reads, does analysis, then writes new the audio file. The most common type of files auto-editor processes...
---

Every time auto-editor processes a media file with audio, auto-editor reads, does analysis, then writes new the audio file. The most common type of files auto-editor processes are `mp4` containers with an AAC audio track, but many other audio codecs could be used as well. Therefore, Auto-Editor converts them into WAV files.

However, the data needs to be in a form that can be viewed or changed by the Python runtime. That's where [wavfile.py](https://github.com/WyattBlue/auto-editor/blob/master/auto_editor/wavfile.py) comes in. wavfile.py reads WAV file data and returns a data structure that Python can use. I won't spoil what is used in the final version, but first, let's examine a naïve approach.

## Python's List
```python
# A 2-channel stereo audio samples
samples = [[0, 0, 345, 578, 345 ...], [0, 0, 235, 456, 234 ...]]
```

The code above represents samples as a native Python list, however, this is incredibly memory inefficient. A typical audio file is has a sample rate of 44.1kHz. That means that one second of audio needs to store 44,100 numbers. Let's see how well Python stores all this data.

```python
>>> sys.getsizeof([0] * 44100) + 44100 * 28
1587656  # 1,587,656 bytes -> 1.5 megabytes
```

That's pretty bad.

The reason why memory usage is so high is that the lists can't store int objects directly. They store a 4 byte reference to a Python Object, which in this case is a 28 byte sized int. In order to reduce memory, we'll need to pick a more suitable data structure.

## Numpy Arrays
Using [numpy arrays](https://github.com/numpy/numpy) allows us to pack fixed-size data extremely tightly and efficiently.

```python
>>> sys.getsizeof(np.zeros([44100, 1], dtype=np.int32))
176528  # 176,528 bytes -> 176 kilobytes
```

The memory used is much more reasonable. By using numpy arrays, we see a 10x improvement in memory.

However, even with numpy arrays, working with large audio files can still consume a lot of memory. For example, a 6-hour stereo audio file can take up around 2GB of memory. Since auto-editor reads and writes big audio files. It's important that auto-editor doesn't have these big files in memory at the same time, but at one point, that was exactly what was happening.

In [commit 9657cfa](https://github.com/WyattBlue/auto-editor/commit/9657cfaf99a17eb25f99dc20f96cc3dc7033bb07), I had to give a hint to Python's Garbage Collector using the `del` keyword because the input audio samples weren't being cleaned up soon enough. This reduced peak memory consumption by half, but I actually figured out a substantial optimization that made this patch irrelevant.

I knew before writing even a single piece of audio rendering code that lists were unsuitable to the task, but I what didn't know that applying this optimization would save so much memory, and would make my fix obsolete in the process.

## Memory Maps
The optimization was swapping `numpy.array` to `numpy.memmap` when reading and writing audio WAV files. memory-maps are a way of reading and writing files as if it were in memory, but can be lazy-loaded from storage. Otherwise, `numpy.memmap` has basically the same interface as `numpy.array`.

Memory-maps really shine in our use-case because since we've already paid for the storage cost by storing audio data in the WAV format, we've reduced the memory used in this operation to almost zero!

## Conclusion
Thinking about your data structures is essential if you care about performance. Sometimes researching more than what is typically used/well known. The best way to catch these issues is to test your program with very large input and profile the memory, storage, and time used.

Creating fast, efficient programs is everyone's responsibly.

---

## Other Paths
Python has a built-in alternative to numpy arrays, which is the [array.array](https://docs.python.org/3/library/array.html#module-array) datatype. However, there are many problems. One is that you don't have nice guaranteed, only platform-dependent `int` `long` and `long long` values. Another is that numpy has speed optimizations like SIMD and `array.array` doesn't. `array.array` is really only a thin layer other a fixed size C array, but C Compilers don't include these arithmetic optimizations like numpy does.

