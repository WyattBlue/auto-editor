'''premiere.py'''

import os
from shutil import move

from auto_editor.formats.utils import fix_url, indent, get_width_height, safe_mkdir

def speedup(speed):
    return indent(6, '<filter>', '\t<effect>', '\t\t<name>Time Remap</name>',
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
        '\t\t\t<value>{}</value>'.format(speed),
        '\t\t</parameter>',
        '\t\t<parameter authoringApp="PremierePro">',
        '\t\t\t<parameterid>reverse</parameterid>',
        '\t\t\t<name>reverse</name>', '\t\t\t<value>FALSE</value>',
        '\t\t</parameter>',
        '\t\t<parameter authoringApp="PremierePro">',
        '\t\t\t<parameterid>frameblending</parameterid>',
        '\t\t\t<name>frameblending</name>', '\t\t\t<value>FALSE</value>',
        '\t\t</parameter>', '\t</effect>', '</filter>')

def premiere_xml(inp, temp, output, clips, chunks, sampleRate, audioFile,
    resolve, fps, log):

    duration = chunks[len(chunks) - 1][1]
    pathurl = fix_url(inp.path, resolve)

    tracks = len(inp.audio_streams)
    name = inp.name

    log.debug('tracks: {}'.format(tracks))
    log.debug(inp.dirname)

    if(tracks > 1):
        name_without_extension = inp.basename[:inp.basename.rfind('.')]

        fold = safe_mkdir(os.path.join(inp.dirname, '{}_tracks'.format(name_without_extension)))

        trackurls = [pathurl]
        for i in range(1, tracks):
            newtrack = os.path.join(fold, f'{i}.wav')
            move(os.path.join(temp, f'{i}.wav'), newtrack)
            trackurls.append(fix_url(newtrack, resolve))

    ntsc = 'FALSE'
    ana = 'FALSE' # anamorphic
    depth = '16'

    width, height = get_width_height(inp)

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
            outfile.write('\t\t<name>{}</name>\n'.format(groupName))
            outfile.write('\t\t<duration>{}</duration>\n'.format(duration))
            outfile.write('\t\t<rate>\n')
            outfile.write('\t\t\t<timebase>{}</timebase>\n'.format(timebase))
            outfile.write('\t\t\t<ntsc>{}</ntsc>\n'.format(ntsc))
            outfile.write('\t\t</rate>\n')
            outfile.write('\t\t<media>\n')

            outfile.write(indent(3, '<video>', '\t<format>',
                '\t\t<samplecharacteristics>',
                '\t\t\t<width>{}</width>'.format(width),
                '\t\t\t<height>{}</height>'.format(height),
                '\t\t\t<pixelaspectratio>{}</pixelaspectratio>'.format(pixelar),
                '\t\t\t<rate>',
                '\t\t\t\t<timebase>{}</timebase>'.format(timebase),
                '\t\t\t\t<ntsc>{}</ntsc>'.format(ntsc),
                '\t\t\t</rate>',
                '\t\t</samplecharacteristics>',
                '\t</format>', '</video>'))

            outfile.write(indent(3, '<audio>',
                '\t<numOutputChannels>2</numOutputChannels>', '\t<format>',
                '\t\t<samplecharacteristics>',
                '\t\t\t<depth>{}</depth>'.format(depth),
                '\t\t\t<samplerate>{}</samplerate>'.format(sr),
                '\t\t</samplecharacteristics>',
                '\t</format>'))

            outfile.write('\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n')

            total = 0
            for j, clip in enumerate(clips):
                myStart = int(total)
                total += (clip[1] - clip[0]) / (clip[2] / 100)
                myEnd = int(total)

                outfile.write(indent(5, '<clipitem id="clipitem-{}">'.format(j+1),
                    '\t<masterclipid>masterclip-1</masterclipid>',
                    '\t<name>{}</name>'.format(inp.name),
                    '\t<start>{}</start>'.format(myStart),
                    '\t<end>{}</end>'.format(myEnd),
                    '\t<in>{}</in>'.format(int(clip[0] / (clip[2] / 100))),
                    '\t<out>{}</out>'.format(int(clip[1] / (clip[2] / 100)))))

                if(j == 0):
                    # Define file-1
                    outfile.write(indent(6, '<file id="file-1">',
                        '\t<name>{}</name>'.format(inp.name),
                        '\t<pathurl>{}</pathurl>'.format(pathurl),
                        '\t<rate>',
                        '\t\t<timebase>{}</timebase>'.format(timebase),
                        '\t\t<ntsc>{}</ntsc>'.format(ntsc),
                        '\t</rate>',
                        '\t<media>',
                        '\t\t<audio>',
                        '\t\t\t<samplecharacteristics>',
                        '\t\t\t\t<depth>{}</depth>'.format(depth),
                        '\t\t\t\t<samplerate>{}</samplerate>'.format(sr),
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

            return None

    groupName = 'Auto-Editor Video Group'

    with open(output, 'w', encoding='utf-8') as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
        outfile.write('<xmeml version="4">\n')
        outfile.write('\t<sequence>\n')
        outfile.write('\t\t<name>{}</name>\n'.format(groupName))
        outfile.write('\t\t<rate>\n')
        outfile.write('\t\t\t<timebase>{}</timebase>\n'.format(timebase))
        outfile.write('\t\t\t<ntsc>{}</ntsc>\n'.format(ntsc))
        outfile.write('\t\t</rate>\n')
        outfile.write('\t\t<media>\n')

        outfile.write(indent(3, '<video>', '\t<format>',
            '\t\t<samplecharacteristics>',
            '\t\t\t<rate>',
            '\t\t\t\t<timebase>{}</timebase>'.format(timebase),
            '\t\t\t\t<ntsc>{}</ntsc>'.format(ntsc),
            '\t\t\t</rate>',
            '\t\t\t<width>{}</width>'.format(width),
            '\t\t\t<height>{}</height>'.format(height),
            '\t\t\t<anamorphic>{}</anamorphic>'.format(ana),
            '\t\t\t<pixelaspectratio>{}</pixelaspectratio>'.format(pixelar),
            '\t\t\t<fielddominance>none</fielddominance>',
            '\t\t\t<colordepth>{}</colordepth>'.format(colordepth),
            '\t\t</samplecharacteristics>',
            '\t</format>',
            '\t<track>'))

        # Handle clips.
        total = 0
        for j, clip in enumerate(clips):
            myStart = int(total)
            total += (clip[1] - clip[0]) / (clip[2] / 100)
            myEnd = int(total)

            outfile.write(indent(5, '<clipitem id="clipitem-{}">'.format(j+1),
                '\t<masterclipid>masterclip-2</masterclipid>',
                '\t<name>{}</name>'.format(inp.name),
                '\t<start>{}</start>'.format(myStart),
                '\t<end>{}</end>'.format(myEnd),
                '\t<in>{}</in>'.format(int(clip[0] / (clip[2] / 100))),
                '\t<out>{}</out>'.format(int(clip[1] / (clip[2] / 100)))))

            if(j == 0):
                outfile.write(indent(6, '<file id="file-1">',
                    '\t<name>{}</name>'.format(inp.name),
                    '\t<pathurl>{}</pathurl>'.format(pathurl),
                    '\t<rate>',
                    '\t\t<timebase>{}</timebase>'.format(timebase),
                    '\t\t<ntsc>{}</ntsc>'.format(ntsc),
                    '\t</rate>',
                    '\t<duration>{}</duration>'.format(duration),
                    '\t<media>', '\t\t<video>',
                    '\t\t\t<samplecharacteristics>',
                    '\t\t\t\t<rate>',
                    '\t\t\t\t\t<timebase>{}</timebase>'.format(timebase),
                    '\t\t\t\t\t<ntsc>{}</ntsc>'.format(ntsc),
                    '\t\t\t\t</rate>',
                    '\t\t\t\t<width>{}</width>'.format(width),
                    '\t\t\t\t<height>{}</height>'.format(height),
                    '\t\t\t\t<anamorphic>{}</anamorphic>'.format(ana),
                    '\t\t\t\t<pixelaspectratio>{}</pixelaspectratio>'.format(pixelar),
                    '\t\t\t\t<fielddominance>none</fielddominance>',
                    '\t\t\t</samplecharacteristics>',
                    '\t\t</video>', '\t\t<audio>',
                    '\t\t\t<samplecharacteristics>',
                    '\t\t\t\t<depth>{}</depth>'.format(depth),
                    '\t\t\t\t<samplerate>{}</samplerate>'.format(sr),
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
                outfile.write('\t\t\t\t\t\t\t<linkclipref>clipitem-{}</linkclipref>\n'.format((i*(len(clips)))+j+1))
                if(i == 0):
                    outfile.write('\t\t\t\t\t\t\t<mediatype>video</mediatype>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')
                if(i == 2):
                    outfile.write('\t\t\t\t\t\t\t<trackindex>2</trackindex>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')
                outfile.write('\t\t\t\t\t\t\t<clipindex>{}</clipindex>\n'.format(j+1))
                if(i > 0):
                    outfile.write('\t\t\t\t\t\t\t<groupindex>1</groupindex>\n')
                outfile.write('\t\t\t\t\t\t</link>\n')

            outfile.write('\t\t\t\t\t</clipitem>\n')

        # End Video; Start Audio
        outfile.write(indent(3, '\t</track>', '</video>', '<audio>',
            '\t<numOutputChannels>2</numOutputChannels>',
            '\t<format>',
            '\t\t<samplecharacteristics>',
            '\t\t\t<depth>{}</depth>'.format(depth),
            '\t\t\t<samplerate>{}</samplerate>'.format(sr),
            '\t\t</samplecharacteristics>',
            '\t</format>'))

        # Audio Clips
        for t in range(tracks):
            if(t == 0):
                print('')
            total = 0
            outfile.write('\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n')

            for j, clip in enumerate(clips):

                clipItemNum = len(clips) + 1 + j + (t * len(clips))

                outfile.write('\t\t\t\t\t<clipitem id="clipitem-{}" premiereChannelType="stereo">\n'.format(clipItemNum))
                outfile.write('\t\t\t\t\t\t<masterclipid>masterclip-2</masterclipid>\n')
                outfile.write('\t\t\t\t\t\t<name>{}</name>\n'.format(name))

                myStart = int(total)
                total += (clip[1] - clip[0]) / (clip[2] / 100)
                myEnd = int(total)

                outfile.write(indent(6,
                    '<start>{}</start>'.format(myStart),
                    '<end>{}</end>'.format(myEnd),
                    '<in>{}</in>'.format(int(clip[0] / (clip[2] / 100))),
                    '<out>{}</out>'.format(int(clip[1] / (clip[2] / 100))),
                ))

                if(t > 0):
                    outfile.write(indent(6, '<file id="file-{}">'.format(t+1),
                        '\t<name>{}{}</name>'.format(name, t),
                        '\t<pathurl>{}</pathurl>'.format(trackurls[t]),
                        '\t<rate>',
                        '\t\t<timebase>{}</timebase>'.format(timebase),
                        '\t\t<ntsc>{}</ntsc>'.format(ntsc),
                        '\t</rate>',
                        '\t<media>',
                        '\t\t<audio>',
                        '\t\t\t<samplecharacteristics>',
                        '\t\t\t\t<depth>{}</depth>'.format(depth),
                        '\t\t\t\t<samplerate>{}</samplerate>'.format(sr),
                        '\t\t\t</samplecharacteristics>',
                        '\t\t\t<channelcount>2</channelcount>',
                        '\t\t</audio>', '\t</media>', '</file>'))
                else:
                    outfile.write('\t\t\t\t\t\t<file id="file-{}"/>\n'.format(t+1))

                outfile.write(indent(6, '<sourcetrack>',
                    '\t<mediatype>audio</mediatype>', '\t<trackindex>1</trackindex>',
                    '</sourcetrack>', '<labels>', '\t<label2>Iris</label2>', '</labels>',
                ))

                # Add speed effect for audio blocks
                if(clip[2] != 100):
                    outfile.write(speedup(clip[2]))

                outfile.write('\t\t\t\t\t</clipitem>\n')
            outfile.write('\t\t\t\t\t<outputchannelindex>1</outputchannelindex>\n')
            outfile.write('\t\t\t\t</track>\n')

        outfile.write('\t\t\t</audio>\n')
        outfile.write('\t\t</media>\n')
        outfile.write('\t</sequence>\n')
        outfile.write('</xmeml>\n')

    log.conwrite('')
