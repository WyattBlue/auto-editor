'''info.py'''

from mediaMetadata import ffmpegFPS, vidTracks

import os

def getInfo(files, ffmpeg, ffprobe, log):
    for file in files:
        if(os.path.exists(file)):
            print(f'file: {file}')
        else:
            log.error(f'Could not find file: {file}')

        hasVid = ffprobe.pipe(['-show_streams', '-select_streams', 'v', file])
        hasAud = ffprobe.pipe(['-show_streams', '-select_streams', 'a', file])

        hasAud = len(hasAud) > 5
        hasVid = len(hasVid) > 5

        if(hasVid):
            fps = ffmpegFPS(ffmpeg, file, log)
            print(f' - fps: {fps}')

            dur = ffprobe.pipe(['-i', file, '-show_entries', 'format=duration', '-of',
                'csv=p=0']).strip()
            print(f' - duration: {dur}')

            res = ffprobe.pipe(['-select_streams', 'v:0', '-show_entries',
                'stream=height,width', '-of', 'csv=s=x:p=0', file]).strip()
            print(f' - resolution: {res}')

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
                tracks = vidTracks(file, ffprobe, log)
                print(f' - audio tracks: {tracks}')

                for track in range(tracks):
                    print(f'   - Track #{track}')

                    raw_data = ffprobe.pipe(['-select_streams', f'a:{track}',
                        '-show_entries', 'stream=codec_name,sample_rate',
                        '-of', 'compact=p=0:nk=1', file])

                    raw_data = raw_data.replace('\n', '').split('|')

                    acod = raw_data[0]
                    if(len(raw_data) > 1 and raw_data[1].isnumeric()):
                        sr = str(int(raw_data[1]) / 1000) + ' kHz'
                    else:
                        sr = 'N/A'

                    print(f'     - codec: {acod}')
                    print(f'     - samplerate: {sr}')

                    output = ffprobe.pipe(['-select_streams', f'a:{track}',
                        '-show_entries', 'stream=bit_rate', '-of', 'compact=p=0:nk=1',
                        file]).strip()
                    if(output.isnumeric()):
                        abit = str(round(int(output) / 1000)) + 'k'
                        print(f'     - bitrate: {abit}')
            else:
                print(' - audio tracks: 0')
        elif(hasAud):
            raw_data = ffprobe.pipe(['-select_streams', 'a:0', '-show_entries',
                'stream=codec_name,sample_rate', '-of',
                'compact=p=0:nk=1', file]).split('|')

            acod = raw_data[0]
            sr = str(int(raw_data[1]) / 1000) + ' kHz'

            print(f' - codec: {acod}')
            print(f' - samplerate: {sr}')

            output = ffprobe.pipe(['-select_streams',
                'a:0', '-show_entries', 'stream=bit_rate', '-of',
                'compact=p=0:nk=1', file]).strip()
            if(output.isnumeric()):
                abit = str(round(int(output) / 1000)) + 'k'
                print(f' - bitrate: {abit}')
        else:
            print('Invalid media.')
    print('')
