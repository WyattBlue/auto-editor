'''info.py'''

import os

def getInfo(files, ffmpeg, ffprobe, log):
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

            raw_data = ffprobe.pipe(['-select_streams', 'v:0', '-show_entries',
                'stream=codec_name,bit_rate', '-of',
                'compact=p=0:nk=1', file]).split('|')

            print(f' - video codec: {raw_data[0]}')

            if(raw_data[1].strip().isnumeric()):
                vbit = str(int(int(raw_data[1]) / 1000)) + 'k'
            else:
                vbit = 'N/A'
            print(f' - video bitrate: {vbit}')

            if(hasAud):
                tracks = ffprobe.getAudioTracks(file)
                print(f' - audio tracks: {tracks}')

                for track in range(tracks):
                    print(f'   - Track #{track}')
                    print(f'     - codec: {ffprobe.getAudioCodec(file, track)}')
                    print(f'     - samplerate: {ffprobe.getPrettySampleRate(file, track)}')
                    print(f'     - bitrate: {ffprobe.getPrettyABitrate(file, track)}')
            else:
                print(' - audio tracks: 0')
        elif(hasAud):
            print(f' - codec: {ffprobe.getAudioCodec(file, track=0)}')
            print(f' - samplerate: {ffprobe.getPrettySampleRate(file, track=0)}')
            print(f' - bitrate: {ffprobe.getPrettyABitrate(file, track=0)}')
        else:
            print('Invalid media.')
    print('')
