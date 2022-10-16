# AE-FFmpeg
Static FFmpeg and FFprobe binaries for use with Auto-Editor.

## Install
```
pip install ae-ffmpeg
```

## Copyright
The FFmpeg/FFprobe binaires used are under the LGPLv3. Only libraries that are compatible with the LGPLv3 are included.

## How to Compile on MacOS
Use https://github.com/WyattBlue/ffmpeg-build-script/

## How to Compile on Windows
I use https://github.com/m-ab-s/media-autobuild_suite to compile on Windows.

## Is There a Linux Build?
Linux distros generally already ship ffmpeg, so having another ffmpeg would be redundant.

## MacOS flags
```
--enable-videotoolbox --enable-libdav1d --enable-libvpx --enable-libzimg --enable-libmp3lame --enable-libopus --enable-libvorbis --disable-debug --disable-doc --disable-shared --disable-network --disable-indevs --disable-outdevs --disable-sdl2 --disable-xlib --disable-ffplay --enable-pthreads --enable-static --enable-version3 --extra-cflags=-I/Users/wyattblue/projects/ffmpeg-build-script/workspace/include --extra-ldexeflags= --extra-ldflags=-L/Users/wyattblue/projects/ffmpeg-build-script/workspace/lib --extra-libs='-ldl -lpthread -lm -lz' --pkgconfigdir=/Users/wyattblue/projects/ffmpeg-build-script/workspace/lib/pkgconfig --pkg-config-flags=--static --prefix=/Users/wyattblue/projects/ffmpeg-build-script/workspace --extra-version=5.0.1
``` 
