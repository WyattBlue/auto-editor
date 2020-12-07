'''premiere.py'''

"""
Export an XML file that can be imported by Adobe Premiere.
"""

# Internal libraries
import os

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
        '\t\t</parameter>',
        '\t</effect>',
        '</filter>')


def exportToPremiere(myInput: str, temp: str, output, clips, tracks: int, sampleRate,
    audioFile, log):

    def makepath(filepath: str) -> str:
        return 'file://localhost' + os.path.abspath(filepath)

    pathurl = makepath(myInput)

    name = os.path.basename(myInput)

    log.debug('tracks: ' + str(tracks))
    log.debug(os.path.dirname(os.path.abspath(myInput)))

    if(tracks > 1):
        # XML in Adobe Premiere doesn't support multiple audio tracks so
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
            os.rename(os.path.join(temp, f'{i}.wav'), newtrack)
            trackurls.append(newtrack)

    ntsc = 'FALSE'
    ana = 'FALSE' # anamorphic
    depth = '16'
    timebase = '30'
    if(not audioFile):
        try:
            import cv2

            cap = cv2.VideoCapture(myInput)
            width = str(int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)))
            height = str(int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)))
            cap.release()
            cv2.destroyAllWindows()
        except ImportError:
            width = '1280'
            height = '720'

    pixelar = 'square' # pixel aspect ratio
    colordepth = '24'
    sr = sampleRate

    if(audioFile):
        groupName = 'Auto-Editor Audio Group'
        with open(output, 'w', encoding='utf-8') as outfile:
            outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
            outfile.write('<xmeml version="4">\n')
            outfile.write('\t<sequence>\n')
            outfile.write('\t<rate>\n')
            outfile.write(f'\t\t<timebase>{timebase}</timebase>\n')
            outfile.write('\t\t<ntsc>TRUE</ntsc>\n')
            outfile.write('\t</rate>\n')
            outfile.write(f'\t\t<name>{groupName}</name>\n')
            outfile.write('\t\t<media>\n')
            outfile.write('\t\t\t<audio>\n')
            outfile.write('\t\t\t\t<numOutputChannels>2</numOutputChannels>\n')
            outfile.write('\t\t\t\t<format>\n')
            outfile.write('\t\t\t\t\t<samplecharacteristics>\n')
            outfile.write(f'\t\t\t\t\t\t<depth>{depth}</depth>\n')
            outfile.write(f'\t\t\t\t\t\t<samplerate>{sr}</samplerate>\n')
            outfile.write('\t\t\t\t\t</samplecharacteristics>\n')
            outfile.write('\t\t\t\t</format>\n')
            outfile.write('\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n')

            total = 0
            for j, clip in enumerate(clips):
                myStart = int(total)
                total += (clip[1] - clip[0]) / (clip[2] / 100)
                myEnd = int(total)

                outfile.write(f'\t\t\t\t\t<clipitem id="clipitem-{j+1}">\n')
                outfile.write('\t\t\t\t\t\t<masterclipid>masterclip-1</masterclipid>\n')
                outfile.write(f'\t\t\t\t\t\t<name>{name}</name>\n')
                outfile.write(f'\t\t\t\t\t\t<start>{myStart}</start>\n')
                outfile.write(f'\t\t\t\t\t\t<end>{myEnd}</end>\n')
                outfile.write(f'\t\t\t\t\t\t<in>{int(clip[0] / (clip[2] / 100))}</in>\n')
                outfile.write(f'\t\t\t\t\t\t<out>{int(clip[1] / (clip[2] / 100))}</out>\n')

                if(j == 0):
                    outfile.write('\t\t\t\t\t\t<file id="file-1">\n')
                    outfile.write(f'\t\t\t\t\t\t\t<name>{name}</name>\n')
                    outfile.write(f'\t\t\t\t\t\t\t<pathurl>{pathurl}</pathurl>\n')
                    outfile.write('\t\t\t\t\t\t\t<rate>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t<timebase>{timebase}</timebase>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
                    outfile.write('\t\t\t\t\t\t\t</rate>\n')
                    outfile.write('\t\t\t\t\t\t\t<media>\n')
                    outfile.write('\t\t\t\t\t\t\t\t<audio>\n')
                    outfile.write('\t\t\t\t\t\t\t\t\t<samplecharacteristics>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t\t\t<depth>{depth}</depth>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t\t\t<samplerate>{sr}</samplerate>\n')
                    outfile.write('\t\t\t\t\t\t\t\t\t</samplecharacteristics>\n')
                    outfile.write('\t\t\t\t\t\t\t\t\t<channelcount>2</channelcount>\n')
                    outfile.write('\t\t\t\t\t\t\t\t</audio>\n')
                    outfile.write('\t\t\t\t\t\t\t</media>\n')
                    outfile.write('\t\t\t\t\t\t</file>\n')
                else:
                    outfile.write('\t\t\t\t\t\t<file id="file-1"/>\n')
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
        outfile.write('\t\t<media>\n')
        outfile.write('\t\t\t<video>\n')
        outfile.write('\t\t\t\t<format>\n')
        outfile.write('\t\t\t\t\t<samplecharacteristics>\n')
        outfile.write('\t\t\t\t\t\t<rate>\n')
        outfile.write(f'\t\t\t\t\t\t\t<timebase>{timebase}</timebase>\n')
        outfile.write(f'\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
        outfile.write('\t\t\t\t\t\t</rate>\n')
        outfile.write(f'\t\t\t\t\t\t<width>{width}</width>\n')
        outfile.write(f'\t\t\t\t\t\t<height>{height}</height>\n')
        outfile.write(f'\t\t\t\t\t\t<anamorphic>{ana}</anamorphic>\n')
        outfile.write(f'\t\t\t\t\t\t<pixelaspectratio>{pixelar}</pixelaspectratio>\n')
        outfile.write('\t\t\t\t\t\t<fielddominance>none</fielddominance>\n')
        outfile.write(f'\t\t\t\t\t\t<colordepth>{colordepth}</colordepth>\n')
        outfile.write('\t\t\t\t\t</samplecharacteristics>\n')
        outfile.write('\t\t\t\t</format>\n')
        outfile.write('\t\t\t\t<track>\n')

        # Handle clips.
        total = 0
        for j, clip in enumerate(clips):
            myStart = int(total)
            total += (clip[1] - clip[0]) / (clip[2] / 100)
            myEnd = int(total)

            outfile.write(f'\t\t\t\t\t<clipitem id="clipitem-{j+1}">\n')
            outfile.write('\t\t\t\t\t\t<masterclipid>masterclip-2</masterclipid>\n')
            outfile.write(f'\t\t\t\t\t\t<name>{name}</name>\n')
            outfile.write(f'\t\t\t\t\t\t<start>{myStart}</start>\n')
            outfile.write(f'\t\t\t\t\t\t<end>{myEnd}</end>\n')
            outfile.write(f'\t\t\t\t\t\t<in>{int(clip[0] / (clip[2] / 100))}</in>\n')
            outfile.write(f'\t\t\t\t\t\t<out>{int(clip[1] / (clip[2] / 100))}</out>\n')

            if(j == 0):
                outfile.write('\t\t\t\t\t\t<file id="file-1">\n')
                outfile.write(f'\t\t\t\t\t\t\t<name>{name}</name>\n')
                outfile.write(f'\t\t\t\t\t\t\t<pathurl>{pathurl}</pathurl>\n')
                outfile.write('\t\t\t\t\t\t\t<rate>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t<timebase>{timebase}</timebase>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
                outfile.write('\t\t\t\t\t\t\t</rate>\n')
                outfile.write('\t\t\t\t\t\t\t<media>\n')
                outfile.write('\t\t\t\t\t\t\t\t<video>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<samplecharacteristics>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t\t<rate>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t\t<timebase>{timebase}</timebase>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t\t</rate>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t<width>{width}</width>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t<height>{height}</height>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t<anamorphic>{ana}</anamorphic>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t<pixelaspectratio>{pixelar}</pixelaspectratio>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t\t<fielddominance>none</fielddominance>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t</samplecharacteristics>\n')
                outfile.write('\t\t\t\t\t\t\t\t</video>\n')
                outfile.write('\t\t\t\t\t\t\t\t<audio>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<samplecharacteristics>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t<depth>{depth}</depth>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t\t<samplerate>{sr}</samplerate>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t</samplecharacteristics>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<channelcount>2</channelcount>\n')
                outfile.write('\t\t\t\t\t\t\t\t</audio>\n')
                outfile.write('\t\t\t\t\t\t\t</media>\n')
                outfile.write('\t\t\t\t\t\t</file>\n')
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
        outfile.write('\t\t\t\t</track>\n')
        outfile.write('\t\t\t</video>\n')
        outfile.write('\t\t\t<audio>\n')
        outfile.write('\t\t\t\t<numOutputChannels>2</numOutputChannels>\n')
        outfile.write('\t\t\t\t<format>\n')
        outfile.write('\t\t\t\t\t<samplecharacteristics>\n')
        outfile.write(f'\t\t\t\t\t\t<depth>{depth}</depth>\n')
        outfile.write(f'\t\t\t\t\t\t<samplerate>{sr}</samplerate>\n')
        outfile.write('\t\t\t\t\t</samplecharacteristics>\n')
        outfile.write('\t\t\t\t</format>\n')

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
                    outfile.write(f'\t\t\t\t\t\t<file id="file-{t+1}">\n')
                    outfile.write(f'\t\t\t\t\t\t\t<name>{name}{t}</name>\n')
                    outfile.write(f'\t\t\t\t\t\t\t<pathurl>{trackurls[t]}</pathurl>\n')
                    outfile.write('\t\t\t\t\t\t\t<rate>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t<timebase>{timebase}</timebase>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
                    outfile.write('\t\t\t\t\t\t\t</rate>\n')
                    outfile.write('\t\t\t\t\t\t\t<media>\n')
                    outfile.write('\t\t\t\t\t\t\t\t<audio>\n')
                    outfile.write('\t\t\t\t\t\t\t\t\t<samplecharacteristics>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t\t\t<depth>{depth}</depth>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t\t\t<samplerate>{sr}</samplerate>\n')
                    outfile.write('\t\t\t\t\t\t\t\t\t</samplecharacteristics>\n')
                    outfile.write('\t\t\t\t\t\t\t\t\t<channelcount>2</channelcount>\n')
                    outfile.write('\t\t\t\t\t\t\t\t</audio>\n')
                    outfile.write('\t\t\t\t\t\t\t</media>\n')
                    outfile.write('\t\t\t\t\t\t</file>\n')
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
