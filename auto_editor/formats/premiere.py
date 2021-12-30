'''formats/premiere.py'''

import os
from shutil import move

from .utils import indent, get_width_height, safe_mkdir

pixelar = 'square' # pixel aspect ratio
colordepth = '24'
ntsc = 'FALSE'
ana = 'FALSE' # anamorphic
depth = '16'

def fix_url(path):
    # type: (str) -> str
    from urllib.parse import quote
    from platform import system
    from os.path import abspath

    if(system() == 'Windows'):
        return'file://localhost/' + quote(abspath(path)).replace('%5C', '/')
    return 'file://localhost' + abspath(path)

def speedup(speed):
    # type: (...) -> str
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

def handle_video_clips(outfile, clips, inp, timebase, duration, width, height, sr,
    pathurls):
    tracks = len(inp.audio_streams)
    total = 0
    for j, clip in enumerate(clips):
        my_start = int(total)
        total += (clip[1] - clip[0]) / (clip[2] / 100)
        my_end = int(total)

        outfile.write(indent(5, '<clipitem id="clipitem-{}">'.format(j+1),
            '\t<masterclipid>masterclip-2</masterclipid>',
            '\t<name>{}</name>'.format(inp.basename),
            '\t<start>{}</start>'.format(my_start),
            '\t<end>{}</end>'.format(my_end),
            '\t<in>{}</in>'.format(int(clip[0] / (clip[2] / 100))),
            '\t<out>{}</out>'.format(int(clip[1] / (clip[2] / 100)))))

        if(j == 0):
            outfile.write(indent(6, '<file id="file-1">',
                '\t<name>{}</name>'.format(inp.basename),
                '\t<pathurl>{}</pathurl>'.format(pathurls[0]),
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
    outfile.write(indent(3, '\t</track>', '</video>'))

def handle_audio_clips(tracks, outfile, audioFile, clips, inp, timebase, sr, pathurls):
    for t in range(tracks):
        outfile.write('\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n')
        total = 0
        for j, clip in enumerate(clips):

            my_start = int(total)
            total += (clip[1] - clip[0]) / (clip[2] / 100)
            my_end = int(total)

            if(audioFile):
                clip_item_num = j + 1
                master_id = '1'
            else:
                clip_item_num = len(clips) + 1 + j + (t * len(clips))
                master_id = '2'

            outfile.write(indent(5,
                '<clipitem id="clipitem-{}" premiereChannelType="stereo">'.format(clip_item_num),
                '\t<masterclipid>masterclip-{}</masterclipid>'.format(master_id),
                '\t<name>{}</name>'.format(inp.basename),
                '\t<start>{}</start>'.format(my_start),
                '\t<end>{}</end>'.format(my_end),
                '\t<in>{}</in>'.format(int(clip[0] / (clip[2] / 100))),
                '\t<out>{}</out>'.format(int(clip[1] / (clip[2] / 100)))))

            if((audioFile and j == 0) or (t > 0 and j == 0)):
                outfile.write(indent(6, '<file id="file-{}">'.format(t+1),
                    '\t<name>{}</name>'.format(inp.basename),
                    '\t<pathurl>{}</pathurl>'.format(pathurls[t]),
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
                '\t<mediatype>audio</mediatype>',
                '\t<trackindex>1</trackindex>',
                '</sourcetrack>'))

            if(audioFile):
                outfile.write('\t\t\t\t\t</clipitem>\n')
            else:
                outfile.write(indent(6, '<labels>', '\t<label2>Iris</label2>', '</labels>'))

            # Add speed effect for audio blocks
            if(clip[2] != 100):
                outfile.write(speedup(clip[2]))

            outfile.write('\t\t\t\t\t</clipitem>\n')
        if(not audioFile):
            outfile.write('\t\t\t\t\t<outputchannelindex>1</outputchannelindex>\n')
        outfile.write('\t\t\t\t</track>\n')

def premiere_xml(inp, temp, output, clips, chunks, sampleRate, audioFile, fps, log):

    duration = chunks[-1][1]
    pathurls = [fix_url(inp.path)]

    tracks = len(inp.audio_streams)

    log.debug('tracks: {}'.format(tracks))
    log.debug(inp.dirname)

    if(tracks > 1):
        name_without_extension = inp.basename[:inp.basename.rfind('.')]

        fold = safe_mkdir(os.path.join(inp.dirname, '{}_tracks'.format(
            name_without_extension)))

        for i in range(1, tracks):
            newtrack = os.path.join(fold, '{}.wav'.format(i))
            move(os.path.join(temp, '{}.wav'.format(i)), newtrack)
            pathurls.append(fix_url(newtrack))

    width, height = get_width_height(inp)
    if(width is None or height is None):
        width, height = '1280', '720'

    timebase = str(int(fps))

    groupName = 'Auto-Editor {} Group'.format('Audio' if audioFile else 'Video')

    with open(output, 'w', encoding='utf-8') as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
        outfile.write('<xmeml version="4">\n')
        outfile.write('\t<sequence>\n')
        outfile.write('\t\t<name>{}</name>\n'.format(groupName))

        if(audioFile):
            outfile.write('\t\t<duration>{}</duration>\n'.format(duration))

        outfile.write('\t\t<rate>\n')
        outfile.write('\t\t\t<timebase>{}</timebase>\n'.format(timebase))
        outfile.write('\t\t\t<ntsc>{}</ntsc>\n'.format(ntsc))
        outfile.write('\t\t</rate>\n')
        outfile.write('\t\t<media>\n')

        if(audioFile):
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
        else:
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
            handle_video_clips(outfile, clips, inp, timebase, duration, width, height,
                sampleRate, pathurls)

        # Audio Clips
        outfile.write(indent(3, '<audio>',
            '\t<numOutputChannels>2</numOutputChannels>',
            '\t<format>',
            '\t\t<samplecharacteristics>',
            '\t\t\t<depth>{}</depth>'.format(depth),
            '\t\t\t<samplerate>{}</samplerate>'.format(sampleRate),
            '\t\t</samplecharacteristics>',
            '\t</format>'))

        print('')
        handle_audio_clips(tracks, outfile, audioFile, clips, inp, timebase, sampleRate,
            pathurls)

        outfile.write('\t\t\t</audio>\n')
        outfile.write('\t\t</media>\n')
        outfile.write('\t</sequence>\n')
        outfile.write('</xmeml>\n')

    log.conwrite('')
