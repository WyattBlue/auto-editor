import os.path
from os.path import abspath
from shutil import move
from urllib.parse import quote
from platform import system

from .utils import indent, get_width_height, safe_mkdir

PIXEL_ASPECT_RATIO = 'square'
COLORDEPTH = '24'
NTSC = 'FALSE'
ANAMORPHIC = 'FALSE'
DEPTH = '16'

def fix_url(path: str) -> str:
    if system() == 'Windows':
        return'file://localhost/' + quote(abspath(path)).replace('%5C', '/')
    return 'file://localhost' + abspath(path)


def speedup(speed: float) -> str:
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


def premiere_xml(inp, temp, output, chunks, sampleRate, fps, log):

    audio_file = len(inp.video_streams) == 0 and len(inp.audio_streams) == 1

    clips = list(filter(lambda chunk: chunk[2] != 99999, chunks))

    duration = chunks[-1][1]
    pathurls = [fix_url(inp.path)]

    tracks = len(inp.audio_streams)

    if tracks > 1:
        name_without_extension = inp.basename[:inp.basename.rfind('.')]

        fold = safe_mkdir(os.path.join(inp.dirname, '{}_tracks'.format(
            name_without_extension)))

        for i in range(1, tracks):
            newtrack = os.path.join(fold, f'{i}.wav')
            move(os.path.join(temp, f'{i}.wav'), newtrack)
            pathurls.append(fix_url(newtrack))

    width, height = get_width_height(inp)
    if width is None or height is None:
        width, height = '1280', '720'

    timebase = str(int(fps))

    group_name = 'Auto-Editor {} Group'.format('Audio' if audio_file else 'Video')

    with open(output, 'w', encoding='utf-8') as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
        outfile.write('<xmeml version="4">\n')
        outfile.write('\t<sequence>\n')
        outfile.write(f'\t\t<name>{group_name}</name>\n')
        outfile.write(f'\t\t<duration>{duration}</duration>\n')
        outfile.write('\t\t<rate>\n')
        outfile.write(f'\t\t\t<timebase>{timebase}</timebase>\n')
        outfile.write(f'\t\t\t<ntsc>{NTSC}</ntsc>\n')
        outfile.write('\t\t</rate>\n')
        outfile.write('\t\t<media>\n')
        outfile.write(indent(3,
            '<video>',
            '\t<format>',
            '\t\t<samplecharacteristics>',
            )
        )

        if len(inp.video_streams) > 0:
            outfile.write(indent(3,
                '\t\t\t<rate>',
                f'\t\t\t\t<timebase>{timebase}</timebase>',
                f'\t\t\t\t<ntsc>{NTSC}</ntsc>',
                '\t\t\t</rate>')
            )

        outfile.write(indent(3,
            '\t\t\t<width>{}</width>'.format(width),
            '\t\t\t<height>{}</height>'.format(height),
            f'\t\t\t<pixelaspectratio>{PIXEL_ASPECT_RATIO}</pixelaspectratio>',
        ))

        if len(inp.video_streams) > 0:
            outfile.write(indent(3,
                '\t\t\t<fielddominance>none</fielddominance>',
                f'\t\t\t<colordepth>{COLORDEPTH}</colordepth>',
                )
            )

        outfile.write(indent(3,
            '\t\t</samplecharacteristics>',
            '\t</format>',
            '</video>' if len(inp.video_streams) == 0 else '\t<track>'
            )
        )

        if len(inp.video_streams) > 0:
            # Handle video clips

            total = 0
            for j, clip in enumerate(clips):

                clip_duration = (clip[1] - clip[0]) / clip[2]

                my_start = int(total)
                my_end = int(total) + int(clip_duration)

                total += clip_duration

                outfile.write(indent(5,
                    '<clipitem id="clipitem-{}">'.format(j+1),
                    '\t<masterclipid>masterclip-2</masterclipid>',
                    '\t<name>{}</name>'.format(inp.basename),
                    '\t<start>{}</start>'.format(my_start),
                    '\t<end>{}</end>'.format(my_end),
                    '\t<in>{}</in>'.format(int(clip[0] / clip[2])),
                    '\t<out>{}</out>'.format(int(clip[1] / clip[2]))
                    )
                )

                if j == 0:
                    outfile.write(indent(6,
                        '<file id="file-1">',
                        '\t<name>{}</name>'.format(inp.basename),
                        '\t<pathurl>{}</pathurl>'.format(pathurls[0]),
                        '\t<rate>',
                        f'\t\t<timebase>{timebase}</timebase>',
                        f'\t\t<ntsc>{NTSC}</ntsc>',
                        '\t</rate>',
                        f'\t<duration>{duration}</duration>',
                        '\t<media>',
                        '\t\t<video>',
                        '\t\t\t<samplecharacteristics>',
                        '\t\t\t\t<rate>',
                        f'\t\t\t\t\t<timebase>{timebase}</timebase>',
                        f'\t\t\t\t\t<ntsc>{NTSC}</ntsc>',
                        '\t\t\t\t</rate>',
                        '\t\t\t\t<width>{}</width>'.format(width),
                        '\t\t\t\t<height>{}</height>'.format(height),
                        f'\t\t\t\t<anamorphic>{ANAMORPHIC}</anamorphic>',
                        f'\t\t\t\t<pixelaspectratio>{PIXEL_ASPECT_RATIO}</pixelaspectratio>',
                        '\t\t\t\t<fielddominance>none</fielddominance>',
                        '\t\t\t</samplecharacteristics>',
                        '\t\t</video>',
                        '\t\t<audio>',
                        '\t\t\t<samplecharacteristics>',
                        f'\t\t\t\t<depth>{DEPTH}</depth>',
                        f'\t\t\t\t<samplerate>{sampleRate}</samplerate>',
                        '\t\t\t</samplecharacteristics>',
                        '\t\t\t<channelcount>2</channelcount>',
                        '\t\t</audio>',
                        '\t</media>',
                        '</file>',
                        )
                    )
                else:
                    outfile.write('\t\t\t\t\t\t<file id="file-1"/>\n')

                if clip[2] != 1:
                    outfile.write(speedup(clip[2] * 100))

                # Linking for video blocks
                for i in range(max(3, tracks + 1)):
                    outfile.write('\t\t\t\t\t\t<link>\n')
                    outfile.write('\t\t\t\t\t\t\t<linkclipref>clipitem-{}</linkclipref>\n'.format((i*(len(clips)))+j+1))
                    if i == 0:
                        outfile.write('\t\t\t\t\t\t\t<mediatype>video</mediatype>\n')
                    else:
                        outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')
                    if i == 2:
                        outfile.write('\t\t\t\t\t\t\t<trackindex>2</trackindex>\n')
                    else:
                        outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')
                    outfile.write('\t\t\t\t\t\t\t<clipindex>{}</clipindex>\n'.format(j+1))
                    if i > 0:
                        outfile.write('\t\t\t\t\t\t\t<groupindex>1</groupindex>\n')
                    outfile.write('\t\t\t\t\t\t</link>\n')

                outfile.write('\t\t\t\t\t</clipitem>\n')
            outfile.write(indent(3, '\t</track>', '</video>'))


        # Audio Clips
        outfile.write(indent(3,
            '<audio>',
            '\t<numOutputChannels>2</numOutputChannels>',
            '\t<format>',
            '\t\t<samplecharacteristics>',
            f'\t\t\t<depth>{DEPTH}</depth>',
            f'\t\t\t<samplerate>{sampleRate}</samplerate>',
            '\t\t</samplecharacteristics>',
            '\t</format>'
            )
        )

        for t in range(tracks):
            outfile.write('\t\t\t\t<track currentExplodedTrackIndex="0" premiereTrackType="Stereo">\n')
            total = 0
            for j, clip in enumerate(clips):

                clip_duration = (clip[1] - clip[0]) / clip[2]

                my_start = int(total)
                my_end = int(total) + int(clip_duration)

                total += clip_duration

                if audio_file:
                    clip_item_num = j + 1
                    master_id = '1'
                else:
                    clip_item_num = len(clips) + 1 + j + (t * len(clips))
                    master_id = '2'

                outfile.write(indent(5,
                    f'<clipitem id="clipitem-{clip_item_num}" premiereChannelType="stereo">',
                    f'\t<masterclipid>masterclip-{master_id}</masterclipid>',
                    f'\t<name>{inp.basename}</name>',
                    f'\t<start>{my_start}</start>',
                    f'\t<end>{my_end}</end>',
                    '\t<in>{}</in>'.format(int(clip[0] / clip[2])),
                    '\t<out>{}</out>'.format(int(clip[1] / clip[2]))
                    )
                )

                if j == 0 and (audio_file or t > 0):
                    outfile.write(indent(6,
                        '<file id="file-{}">'.format(t+1),
                        '\t<name>{}</name>'.format(inp.basename),
                        '\t<pathurl>{}</pathurl>'.format(pathurls[t]),
                        '\t<rate>',
                        f'\t\t<timebase>{timebase}</timebase>',
                        f'\t\t<ntsc>{NTSC}</ntsc>',
                        '\t</rate>',
                        '\t<media>',
                        '\t\t<audio>',
                        '\t\t\t<samplecharacteristics>',
                        f'\t\t\t\t<depth>{DEPTH}</depth>',
                        f'\t\t\t\t<samplerate>{sampleRate}</samplerate>',
                        '\t\t\t</samplecharacteristics>',
                        '\t\t\t<channelcount>2</channelcount>',
                        '\t\t</audio>',
                        '\t</media>',
                        '</file>',
                        )
                    )
                else:
                    outfile.write('\t\t\t\t\t\t<file id="file-{}"/>\n'.format(t+1))

                outfile.write(indent(6,
                    '<sourcetrack>',
                    '\t<mediatype>audio</mediatype>',
                    '\t<trackindex>1</trackindex>',
                    '</sourcetrack>'
                    '<labels>',
                    '\t<label2>Iris</label2>',
                    '</labels>'
                    )
                )

                if clip[2] != 1:
                    outfile.write(speedup(clip[2] * 100))

                outfile.write('\t\t\t\t\t</clipitem>\n')
            if not audio_file:
                outfile.write('\t\t\t\t\t<outputchannelindex>1</outputchannelindex>\n')
            outfile.write('\t\t\t\t</track>\n')

        outfile.write('\t\t\t</audio>\n')
        outfile.write('\t\t</media>\n')
        outfile.write('\t</sequence>\n')
        outfile.write('</xmeml>\n')

    log.conwrite('')
