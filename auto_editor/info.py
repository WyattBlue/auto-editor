'''info.py'''

import os
import sys

def getInfo(files, ffmpeg, ffprobe, log):

    if(len(files) == 0):
        print('info: subcommand for inspecting media contents.')
        print('Add a file to inspect. Example:')
        print('    auto-editor info example.mp4')
        sys.exit()

    for file in files:
        if(os.path.exists(file)):
            print(f'file: {file}')
        else:
            log.error(f'Could not find file: {file}')

        hasVid = len(ffprobe.pipe(['-show_streams', '-select_streams', 'v', file])) > 5
        hasAud = len(ffprobe.pipe(['-show_streams', '-select_streams', 'a', file])) > 5

        if(hasVid):
            print(f' - fps: {ffprobe.getFrameRate(file)}')
            print(f' - duration: {ffprobe.getDuration(file)}')
            print(f' - resolution: {ffprobe.getResolution(file)}')
            print(f' - video codec: {ffprobe.getVideoCodec(file)}')

            vbit = ffprobe.getPrettyBitrate(file, 'v', track=0)
            print(f' - video bitrate: {vbit}')

            if(hasAud):
                tracks = ffprobe.getAudioTracks(file)
                print(f' - audio tracks: {tracks}')

                for track in range(tracks):
                    print(f'   - Track #{track}')
                    print(f'     - codec: {ffprobe.getAudioCodec(file, track)}')
                    print(f'     - samplerate: {ffprobe.getPrettySampleRate(file, track)}')

                    abit = ffprobe.getPrettyBitrate(file, 'a', track)
                    print(f'     - bitrate: {abit}')
            else:
                print(' - audio tracks: 0')
        elif(hasAud):
            print(f' - duration: {ffprobe.getAudioDuration(file)}')
            print(f' - codec: {ffprobe.getAudioCodec(file, track=0)}')
            print(f' - samplerate: {ffprobe.getPrettySampleRate(file, track=0)}')
            abit = ffprobe.getPrettyBitrate(file, 'a', track=0)
            print(f' - bitrate: {abit}')
        else:
            print('Invalid media.')
    print('')
