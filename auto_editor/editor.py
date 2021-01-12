'''editor.py'''

# Internal libraries
import os
from shutil import move

def formatXML(base: int, *args: str) -> str:
    r = ''
    for line in args:
        r += ('\t' * base) + line + '\n'
    return r

def speedup(speed) -> str:
    return formatXML(6, '<filter>', '\t<effect>', '\t\t<name>Time Remap</name>',
        '\t\t<effectid>timeremap</effectid>',
        '\t\t<effectcategory>motion</effectcategory>',
        '\t\t<effecttype>motion</effecttype>',
        '\t\t<mediatype>video</mediatype>',
        '\t\t<parameter authoringApp="PremierePro">',
        '\t\t\t<parameterid>variablespeed</parameterid>',
        '\t\t\t<name>variablespeed</name>', '\t\t\t<valuemin>0</valuemin>',
        '\t\t\t<valuemax>1</valuemax>',
        '\t\t\t<value>0</value>',
        '\t\t</parameter>',
        '\t\t<parameter authoringApp="PremierePro">',
        '\t\t\t<parameterid>speed</parameterid>',  '\t\t\t<name>speed</name>',
        '\t\t\t<valuemin>-100000</valuemin>', '\t\t\t<valuemax>100000</valuemax>',
        f'\t\t\t<value>{speed}</value>',
        '\t\t</parameter>',
        '\t\t<parameter authoringApp="PremierePro">',
        '\t\t\t<parameterid>reverse</parameterid>',
        '\t\t\t<name>reverse</name>', '\t\t\t<value>FALSE</value>',
        '\t\t</parameter>',
        '\t\t<parameter authoringApp="PremierePro">',
        '\t\t\t<parameterid>frameblending</parameterid>',
        '\t\t\t<name>frameblending</name>', '\t\t\t<value>FALSE</value>',
        '\t\t</parameter>', '\t</effect>', '</filter>')

def editorXML(myInput: str, temp: str, output, clips, chunks, tracks: int,
    sampleRate, audioFile, fps, log):

    def makepath(filepath: str) -> str:

        import platform

        if(platform.system() == 'Windows'):
            return 'file://localhost/' + os.path.abspath(filepath).replace(':', f'%3a')
        return 'file://localhost' + os.path.abspath(filepath)

    duration = chunks[len(chunks) - 1][1]

    pathurl = makepath(myInput)

    name = os.path.basename(myInput)

    log.debug('tracks: ' + str(tracks))
    log.debug(os.path.dirname(os.path.abspath(myInput)))

    if(tracks > 1):
        # XML's don't support multiple audio tracks so
        # we need to do some stupid things to get it working.
        from shutil import rmtree

        inFolder = os.path.dirname(os.path.abspath(myInput))

        hmm = name[:name.rfind('.')]

        newFolderName = os.path.join(inFolder, hmm + '_tracks')
        try:
            os.mkdir(newFolderName)
        except OSError:
            rmtree(newFolderName)
            os.mkdir(newFolderName)

        trackurls = [pathurl]
        for i in range(1, tracks):
            newtrack = os.path.join(newFolderName, f'{i}.wav')
            move(os.path.join(temp, f'{i}.wav'), newtrack)
            trackurls.append(newtrack)

    ntsc = 'FALSE'
    ana = 'FALSE' # anamorphic
    depth = '16'
    if(not audioFile):
        try:
            import cv2
            log.conwrite('Grabbing video dimensions.')

            cap = cv2.VideoCapture(myInput)
            width = str(int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)))
            height = str(int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
            cap.release()
            cv2.destroyAllWindows()
        except ImportError:
            width = '1920'
            height = '1080'
    else:
        width = '1920'
        height = '1080'

    pixelar = 'square' # pixel aspect ratio
    colordepth = '24'
    sr = sampleRate
    timebase = str(int(fps))

    if(audioFile):
        groupName = 'Auto-Editor Audio Group'
        with open(output, 'w', encoding='utf-8') as outfile:
            outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
            outfile.write('<xmeml version="4">\n')
            outfile.write('\t<sequence>\n')
            outfile.write(f'\t\t<name>{groupName}</name>\n')
            outfile.write(f'\t\t<duration>{duration}</duration>\n')
            outfile.write('\t\t<rate>\n')
            outfile.write(f'\t\t\t<timebase>{timebase}</timebase>\n')
            outfile.write(f'\t\t\t<ntsc>{ntsc}</ntsc>\n')
            outfile.write('\t\t</rate>\n')
            outfile.write('\t\t<media>\n')

            outfile.write(formatXML(3, '<video>', '\t<format>',
                '\t\t<samplecharacteristics>',
                f'\t\t\t<width>{width}</width>',
                f'\t\t\t<height>{height}</height>',
                f'\t\t\t<pixelaspectratio>{pixelar}</pixelaspectratio>',
                '\t\t\t<rate>',
                f'\t\t\t\t<timebase>{timebase}</timebase>',
                f'\t\t\t\t<ntsc>{ntsc}</ntsc>',
                '\t\t\t</rate>',
                '\t\t</samplecharacteristics>',
                '\t</format>', '</video>'))

            outfile.write(formatXML(3, '<audio>',
                '\t<numOutputChannels>2</numOutputChannels>', '\t<format>',
                '\t\t<samplecharacteristics>',
                '\t\t\t<depth>{depth}</depth>',
                '\t\t\t<samplerate>{sr}</samplerate>',
                '\t\t</samplecharacteristics>',
                '\t</format>'))

            outfile.write('\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n')

            total = 0
            for j, clip in enumerate(clips):
                myStart = int(total)
                total += (clip[1] - clip[0]) / (clip[2] / 100)
                myEnd = int(total)

                outfile.write(formatXML(5, f'<clipitem id="clipitem-{j+1}">',
                    '\t<masterclipid>masterclip-1</masterclipid>',
                    f'\t<name>{name}</name>',
                    f'\t<start>{myStart}</start>',
                    f'\t<end>{myEnd}</end>',
                    f'\t<in>{int(clip[0] / (clip[2] / 100))}</in>',
                    f'\t<out>{int(clip[1] / (clip[2] / 100))}</out>'))

                if(j == 0):
                    # Define file-1
                    outfile.write(formatXML(6, '<file id="file-1">',
                        f'\t<name>{name}</name>',
                        f'\t<pathurl>{pathurl}</pathurl>',
                        '\t<rate>',
                        f'\t\t<timebase>{timebase}</timebase>',
                        f'\t\t<ntsc>{ntsc}</ntsc>',
                        '\t</rate>',
                        '\t<media>',
                        '\t\t<audio>',
                        '\t\t\t<samplecharacteristics>',
                        f'\t\t\t\t<depth>{depth}</depth>',
                        f'\t\t\t\t<samplerate>{sr}</samplerate>',
                        '\t\t\t</samplecharacteristics>',
                        '\t\t\t<channelcount>2</channelcount>',
                        '\t\t</audio>', '\t</media>', '</file>'))
                else:
                    outfile.write('\t\t\t\t\t\t<file id="file-1"/>\n')
                outfile.write('\t\t\t\t\t\t<sourcetrack>\n')
                outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')
                outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')
                outfile.write('\t\t\t\t\t\t</sourcetrack>\n')
                outfile.write('\t\t\t\t\t</clipitem>\n')

            outfile.write('\t\t\t\t</track>\n')
            outfile.write('\t\t\t</audio>\n')
            outfile.write('\t\t</media>\n')
            outfile.write('\t</sequence>\n')
            outfile.write('</xmeml>')

            # Exit out of this function prematurely.
            return None

    groupName = 'Auto-Editor Video Group'

    with open(output, 'w', encoding='utf-8') as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
        outfile.write('<xmeml version="4">\n')
        outfile.write('\t<sequence>\n')
        outfile.write(f'\t\t<name>{groupName}</name>\n')
        outfile.write('\t\t<rate>\n')
        outfile.write(f'\t\t\t<timebase>{timebase}</timebase>\n')
        outfile.write(f'\t\t\t<ntsc>{ntsc}</ntsc>\n')
        outfile.write('\t\t</rate>\n')
        outfile.write('\t\t<media>\n')

        outfile.write(formatXML(3, '<video>', '\t<format>',
            '\t\t<samplecharacteristics>',
            '\t\t\t<rate>',
            f'\t\t\t\t<timebase>{timebase}</timebase>',
            f'\t\t\t\t<ntsc>{ntsc}</ntsc>',
            '\t\t\t</rate>',
            f'\t\t\t<width>{width}</width>',
            f'\t\t\t<height>{height}</height>',
            f'\t\t\t<anamorphic>{ana}</anamorphic>',
            f'\t\t\t<pixelaspectratio>{pixelar}</pixelaspectratio>',
            '\t\t\t<fielddominance>none</fielddominance>',
            f'\t\t\t<colordepth>{colordepth}</colordepth>',
            '\t\t</samplecharacteristics>',
            '\t</format>',
            '\t<track>'))

        # Handle clips.
        total = 0
        for j, clip in enumerate(clips):
            myStart = int(total)
            total += (clip[1] - clip[0]) / (clip[2] / 100)
            myEnd = int(total)

            outfile.write(formatXML(5, f'<clipitem id="clipitem-{j+1}">',
                '\t<masterclipid>masterclip-2</masterclipid>',
                f'\t<name>{name}</name>',
                f'\t<start>{myStart}</start>',
                f'\t<end>{myEnd}</end>',
                f'\t<in>{int(clip[0] / (clip[2] / 100))}</in>',
                f'\t<out>{int(clip[1] / (clip[2] / 100))}</out>'))

            if(j == 0):
                outfile.write(formatXML(6, '<file id="file-1">',
                    f'\t<name>{name}</name>',
                    f'\t<pathurl>{pathurl}</pathurl>',
                    '\t<rate>',
                    f'\t\t<timebase>{timebase}</timebase>',
                    f'\t\t<ntsc>{ntsc}</ntsc>',
                    '\t</rate>',
                    f'\t<duration>{duration}</duration>',
                    '\t<media>', '\t\t<video>',
                    '\t\t\t<samplecharacteristics>',
                    '\t\t\t\t<rate>',
                    f'\t\t\t\t\t<timebase>{timebase}</timebase>',
                    f'\t\t\t\t\t<ntsc>{ntsc}</ntsc>',
                    '\t\t\t\t</rate>',
                    f'\t\t\t\t<width>{width}</width>',
                    f'\t\t\t\t<height>{height}</height>',
                    f'\t\t\t\t<anamorphic>{ana}</anamorphic>',
                    f'\t\t\t\t<pixelaspectratio>{pixelar}</pixelaspectratio>',
                    '\t\t\t\t<fielddominance>none</fielddominance>',
                    '\t\t\t</samplecharacteristics>',
                    '\t\t</video>', '\t\t<audio>',
                    '\t\t\t<samplecharacteristics>',
                    f'\t\t\t\t<depth>{depth}</depth>',
                    f'\t\t\t\t<samplerate>{sr}</samplerate>',
                    '\t\t\t</samplecharacteristics>',
                    '\t\t\t<channelcount>2</channelcount>',
                    '\t\t</audio>', '\t</media>', '</file>'))
            else:
                outfile.write('\t\t\t\t\t\t<file id="file-1"/>\n')

            if(clip[2] != 100):
                outfile.write(speedup(clip[2]))

            # Linking for video blocks
            for i in range(max(3, tracks + 1)):
                outfile.write('\t\t\t\t\t\t<link>\n')
                outfile.write(f'\t\t\t\t\t\t\t<linkclipref>clipitem-{(i*(len(clips)))+j+1}</linkclipref>\n')
                if(i == 0):
                    outfile.write('\t\t\t\t\t\t\t<mediatype>video</mediatype>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')
                if(i == 2):
                    outfile.write('\t\t\t\t\t\t\t<trackindex>2</trackindex>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')
                outfile.write(f'\t\t\t\t\t\t\t<clipindex>{j+1}</clipindex>\n')
                if(i > 0):
                    outfile.write('\t\t\t\t\t\t\t<groupindex>1</groupindex>\n')
                outfile.write('\t\t\t\t\t\t</link>\n')

            outfile.write('\t\t\t\t\t</clipitem>\n')

        # End Video; Start Audio
        outfile.write(formatXML(3, '\t</track>', '</video>', '<audio>',
            '\t<numOutputChannels>2</numOutputChannels>',
            '\t<format>',
            '\t\t<samplecharacteristics>',
            f'\t\t\t<depth>{depth}</depth>',
            f'\t\t\t<samplerate>{sr}</samplerate>',
            '\t\t</samplecharacteristics>',
            '\t</format>'))

        # Audio Clips
        for t in range(tracks):
            if(t == 0):
                print('')
            log.debug('t variable: ' + str(t))
            total = 0
            outfile.write('\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n')

            for j, clip in enumerate(clips):

                clipItemNum = len(clips) + 1 + j + (t * len(clips))

                outfile.write(f'\t\t\t\t\t<clipitem id="clipitem-{clipItemNum}" premiereChannelType="stereo">\n')
                outfile.write('\t\t\t\t\t\t<masterclipid>masterclip-2</masterclipid>\n')
                outfile.write(f'\t\t\t\t\t\t<name>{name}</name>\n')

                myStart = int(total)
                total += (clip[1] - clip[0]) / (clip[2] / 100)
                myEnd = int(total)

                outfile.write(f'\t\t\t\t\t\t<start>{myStart}</start>\n')
                outfile.write(f'\t\t\t\t\t\t<end>{myEnd}</end>\n')

                outfile.write(f'\t\t\t\t\t\t<in>{int(clip[0] / (clip[2] / 100))}</in>\n')
                outfile.write(f'\t\t\t\t\t\t<out>{int(clip[1] / (clip[2] / 100))}</out>\n')

                if(t > 0):
                    # Define arbitrary file
                    outfile.write(formatXML(6, f'<file id="file-{t+1}">',
                        f'\t<name>{name}{t}</name>',
                        f'\t<pathurl>{trackurls[t]}</pathurl>',
                        '\t<rate>',
                        f'\t\t<timebase>{timebase}</timebase>',
                        f'\t\t<ntsc>{ntsc}</ntsc>',
                        '\t</rate>',
                        '\t<media>',
                        '\t\t<audio>',
                        '\t\t\t<samplecharacteristics>',
                        f'\t\t\t\t<depth>{depth}</depth>',
                        f'\t\t\t\t<samplerate>{sr}</samplerate>',
                        '\t\t\t</samplecharacteristics>',
                        '\t\t\t<channelcount>2</channelcount>',
                        '\t\t</audio>', '\t</media>', '</file>'))
                else:
                    outfile.write(f'\t\t\t\t\t\t<file id="file-{t+1}"/>\n')
                outfile.write('\t\t\t\t\t\t<sourcetrack>\n')
                outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')
                outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')
                outfile.write('\t\t\t\t\t\t</sourcetrack>\n')
                outfile.write('\t\t\t\t\t\t<labels>\n')
                outfile.write('\t\t\t\t\t\t\t<label2>Iris</label2>\n')
                outfile.write('\t\t\t\t\t\t</labels>\n')

                # Add speed effect for audio blocks
                if(clip[2] != 100):
                    outfile.write(speedup(clip[2]))

                outfile.write('\t\t\t\t\t</clipitem>\n')
            outfile.write('\t\t\t\t\t<outputchannelindex>1</outputchannelindex>\n')
            outfile.write('\t\t\t\t</track>\n')

        outfile.write('\t\t\t</audio>\n')
        outfile.write('\t\t</media>\n')
        outfile.write('\t</sequence>\n')
        outfile.write('</xmeml>')

    log.conwrite('')
