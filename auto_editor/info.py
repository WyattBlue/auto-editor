'''info.py'''

from mediaMetadata import ffmpegFPS, vidTracks
from usefulFunctions import pipeToConsole

def getInfo(files, ffmpeg, ffprobe, log):
    for file in files:
        print(f'file: {file}')

        hasVid = pipeToConsole([ffprobe, '-v', 'error', '-show_streams',
            '-select_streams', 'v', file])
        hasAud = pipeToConsole([ffprobe, '-v', 'error', '-show_streams',
            '-select_streams', 'a', file])

        hasAud = len(hasAud) > 5
        hasVid = len(hasVid) > 5

        if(hasVid):
            fps = ffmpegFPS(ffmpeg, file, log)
            print(f' - fps: {fps}')

            res = pipeToConsole([ffprobe, '-v', 'error', '-select_streams', 'v:0',
                '-show_entries', 'stream=height,width', '-of', 'csv=s=x:p=0', file])
            print(f' - resolution: {res.strip()}')

            raw_data = pipeToConsole([ffprobe, '-v', 'error', '-select_streams',
                'v:0', '-show_entries', 'stream=codec_name,bit_rate', '-of',
                'compact=p=0:nk=1', file]).split('|')

            vcod = raw_data[0]
            vbit = str(int(int(raw_data[1]) / 1000)) + 'k'

            print(f' - video codec: {vcod}')
            print(f' - video bitrate: {vbit}')

            if(hasAud):
                tracks = vidTracks(file, ffprobe, log)
                print(f' - audio tracks: {tracks}')

                for track in range(tracks):
                    print(f'   - Track #{track}')

                    raw_data = pipeToConsole([ffprobe, '-v', 'error', '-select_streams',
                        f'a:{track}', '-show_entries', 'stream=codec_name,sample_rate', '-of',
                        'compact=p=0:nk=1', file])

                    raw_data = raw_data.split('|')

                    acod = raw_data[0]
                    sr = str(int(raw_data[1]) / 1000) + ' kHz'

                    print(f'     - codec: {acod}')
                    print(f'     - samplerate: {sr}')

                    output = pipeToConsole([ffprobe, '-v', 'error', '-select_streams',
                        f'a:{track}', '-show_entries', 'stream=bit_rate', '-of',
                        'compact=p=0:nk=1', file]).strip()
                    if(output.isnumeric()):
                        abit = str(round(int(output) / 1000)) + 'k'
                        print(f'     - bitrate: {abit}')
            else:
                print(' - audio tracks: 0')
        elif(hasAud):
            raw_data = pipeToConsole([ffprobe, '-v', 'error', '-select_streams',
                'a:0', '-show_entries', 'stream=codec_name,sample_rate', '-of',
                'compact=p=0:nk=1', file]).split('|')

            acod = raw_data[0]
            sr = str(int(raw_data[1]) / 1000) + ' kHz'

            print(f' - codec: {acod}')
            print(f' - samplerate: {sr}')

            output = pipeToConsole([ffprobe, '-v', 'error', '-select_streams',
                'a:0', '-show_entries', 'stream=bit_rate', '-of',
                'compact=p=0:nk=1', file]).strip()
            if(output.isnumeric()):
                abit = str(round(int(output) / 1000)) + 'k'
                print(f' - bitrate: {abit}')
        else:
            print('Invalid media.')
    print('')
