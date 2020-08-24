'''resolve.py'''

"""
Export an XML file that can be imported by DaVinci Resolve.
"""

# Included functions
from usefulFunctions import conwrite, isAudioFile

# Internal libraries
import os

def exportToResolve(myInput, output, clips, duration, sampleRate, log):
    pathurl = 'file://localhost' + os.path.abspath(myInput)

    name = os.path.basename(myInput)
    audioFile = isAudioFile(myInput)

    ntsc = 'FALSE'
    ana = 'FALSE' # anamorphic
    depth = '16'
    if(not audioFile):
        try:
            import cv2
            conwrite('Grabbing video dimensions.')

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

    if(audioFile):
        with open(output, 'w', encoding='utf-8') as outfile:
            outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
            outfile.write('<xmeml version="5">\n')
            outfile.write('\t<sequence>\n')
            outfile.write('\t\t<name>Auto-Editor Audio Group</name>\n')
            outfile.write(f'\t\t<duration>{duration}</duration>\n')
            outfile.write('\t\t<rate>\n')
            outfile.write('\t\t\t<timebase>30</timebase>\n')
            outfile.write(f'\t\t\t<ntsc>{ntsc}</ntsc>\n')
            outfile.write('\t\t</rate>\n')
            outfile.write('\t\t<in>-1</in>\n')
            outfile.write('\t\t<out>-1</out>\n')
            outfile.write('\t\t<media>\n')
            outfile.write('\t\t\t<video>\n')
            outfile.write('\t\t\t\t<format>\n')
            outfile.write('\t\t\t\t\t<samplecharacteristics>\n')
            outfile.write(f'\t\t\t\t\t\t<width>{width}</width>\n')
            outfile.write(f'\t\t\t\t\t\t<height>{height}</height>\n')
            outfile.write(f'\t\t\t\t\t\t<pixelaspectratio>{pixelar}</pixelaspectratio>\n')
            outfile.write('\t\t\t\t\t\t<rate>\n')
            outfile.write('\t\t\t\t\t\t\t<timebase>30</timebase>\n')
            outfile.write(f'\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
            outfile.write('\t\t\t\t\t\t</rate>\n')
            outfile.write('\t\t\t\t\t</samplecharacteristics>\n')
            outfile.write('\t\t\t\t</format>\n')
            outfile.write('\t\t\t</video>\n')
            outfile.write('\t\t\t<audio>\n')
            outfile.write('\t\t\t\t<track>\n')

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
                    outfile.write('\t\t\t\t\t\t\t\t<timebase>30</timebase>\n')
                    outfile.write(f'\t\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
                    outfile.write('\t\t\t\t\t\t\t</rate>\n')
                    outfile.write('\t\t\t\t\t\t\t<media>\n')
                    outfile.write('\t\t\t\t\t\t\t\t<audio>\n')
                    outfile.write('\t\t\t\t\t\t\t\t\t<channelcount>1</channelcount>\n')
                    outfile.write('\t\t\t\t\t\t\t\t</audio>\n')
                    outfile.write('\t\t\t\t\t\t\t</media>\n')
                    outfile.write('\t\t\t\t\t\t</file>\n')
                else:
                    outfile.write(f'\t\t\t\t\t\t<file id="file-1"/>\n')
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

            # End of audio file code.

    with open(output, 'w', encoding='utf-8') as outfile:
        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE xmeml>\n')
        outfile.write('<xmeml version="4">\n')
        outfile.write('\t<sequence id="sequence-1" TL.SQAudioVisibleBase="0" TL.SQVideoVisibleBase="0" TL.SQVisibleBaseTime="0" TL.SQAVDividerPosition="0.5" TL.SQHideShyTracks="0" TL.SQHeaderWidth="236" TL.SQTimePerPixel="0.013085939262623341" MZ.EditLine="0" MZ.Sequence.PreviewFrameSizeHeight="720" MZ.Sequence.AudioTimeDisplayFormat="200" MZ.Sequence.PreviewRenderingClassID="1297106761" MZ.Sequence.PreviewRenderingPresetCodec="1297107278" MZ.Sequence.PreviewRenderingPresetPath="EncoderPresets/SequencePreview/795454d9-d3c2-429d-9474-923ab13b7018/I-Frame Only MPEG.epr" MZ.Sequence.PreviewUseMaxRenderQuality="false" MZ.Sequence.PreviewUseMaxBitDepth="false" MZ.Sequence.EditingModeGUID="795454d9-d3c2-429d-9474-923ab13b7018" MZ.Sequence.VideoTimeDisplayFormat="104" MZ.WorkOutPoint="10770278400000" MZ.WorkInPoint="0" explodedTracks="true">\n')
        outfile.write('\t\t<rate>\n')
        outfile.write('\t\t\t<timebase>30</timebase>\n')
        outfile.write(f'\t\t\t<ntsc>{ntsc}</ntsc>\n')
        outfile.write('\t\t</rate>\n')
        outfile.write('\t\t<name>Auto-Editor Video Group</name>\n')
        outfile.write('\t\t<media>\n')
        outfile.write('\t\t\t<video>\n')
        outfile.write('\t\t\t\t<format>\n')
        outfile.write('\t\t\t\t\t<samplecharacteristics>\n')
        outfile.write('\t\t\t\t\t\t<rate>\n')
        outfile.write('\t\t\t\t\t\t\t<timebase>30</timebase>\n')
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

            outfile.write(f'\t\t\t\t\t<clipitem id="clipitem-{j+7}">\n')
            outfile.write('\t\t\t\t\t\t<masterclipid>masterclip-2</masterclipid>\n')
            outfile.write(f'\t\t\t\t\t\t<name>{name}</name>\n')
            outfile.write(f'\t\t\t\t\t\t<start>{myStart}</start>\n')
            outfile.write(f'\t\t\t\t\t\t<end>{myEnd}</end>\n')
            outfile.write(f'\t\t\t\t\t\t<in>{int(clip[0] / (clip[2] / 100))}</in>\n')
            outfile.write(f'\t\t\t\t\t\t<out>{int(clip[1] / (clip[2] / 100))}</out>\n')

            if(j == 0):
                outfile.write('\t\t\t\t\t\t<file id="file-2">\n')
                outfile.write(f'\t\t\t\t\t\t\t<name>{name}</name>\n')
                outfile.write(f'\t\t\t\t\t\t\t<pathurl>{pathurl}</pathurl>\n')
                outfile.write('\t\t\t\t\t\t\t<rate>\n')
                outfile.write('\t\t\t\t\t\t\t\t<timebase>30</timebase>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t<ntsc>{ntsc}</ntsc>\n')
                outfile.write('\t\t\t\t\t\t\t</rate>\n')
                outfile.write(f'\t\t\t\t\t\t\t<duration>{duration}</duration>\n')
                outfile.write('\t\t\t\t\t\t\t<media>\n')
                outfile.write('\t\t\t\t\t\t\t\t<video>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<samplecharacteristics>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t\t<rate>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t\t\t<timebase>30</timebase>\n')
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
                outfile.write(f'\t\t\t\t\t\t<file id="file-2"/>\n')

            # Add the speed effect if nessecary
            if(clip[2] != 100):
                outfile.write('\t\t\t\t\t\t<filter>\n')
                outfile.write('\t\t\t\t\t\t\t<effect>\n')
                outfile.write('\t\t\t\t\t\t\t\t<name>Time Remap</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t<effectid>timeremap</effectid>\n')
                outfile.write('\t\t\t\t\t\t\t\t<effectcategory>motion</effectcategory>\n')
                outfile.write('\t\t\t\t\t\t\t\t<effecttype>motion</effecttype>\n')
                outfile.write('\t\t\t\t\t\t\t\t<mediatype>video</mediatype>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>variablespeed</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>variablespeed</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemin>0</valuemin>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemax>1</valuemax>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<value>0</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>speed</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>speed</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemin>-100000</valuemin>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemax>100000</valuemax>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t<value>{clip[2]}</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>reverse</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>reverse</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<value>FALSE</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>frameblending</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>frameblending</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<value>FALSE</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t</effect>\n')
                outfile.write('\t\t\t\t\t\t</filter>\n')

            # Linking for video blocks
            for i in range(3):
                outfile.write('\t\t\t\t\t\t<link>\n')
                outfile.write(f'\t\t\t\t\t\t\t<linkclipref>clipitem-{(i*(len(clips)+1))+7+j}</linkclipref>\n')
                if(i == 0):
                    outfile.write('\t\t\t\t\t\t\t<mediatype>video</mediatype>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')
                if(i == 2):
                    outfile.write('\t\t\t\t\t\t\t<trackindex>2</trackindex>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')
                outfile.write(f'\t\t\t\t\t\t\t<clipindex>{j+1}</clipindex>\n')
                if(i == 1 or i == 2):
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
        outfile.write('\t\t\t\t<track PannerIsInverted="true" PannerStartKeyframe="-91445760000000000,0.5,0,0,0,0,0,0" PannerName="Balance" currentExplodedTrackIndex="0" totalExplodedTrackCount="2" premiereTrackType="Stereo">\n')

        # Audio Clips
        total = 0
        for j, clip in enumerate(clips):
            outfile.write(f'\t\t\t\t\t<clipitem id="clipitem-{len(clips)+8+j}" premiereChannelType="stereo">\n')
            outfile.write(f'\t\t\t\t\t\t<masterclipid>masterclip-2</masterclipid>\n')
            outfile.write(f'\t\t\t\t\t\t<name>{name}</name>\n')

            myStart = int(total)
            total += (clip[1] - clip[0]) / (clip[2] / 100)
            myEnd = int(total)

            outfile.write(f'\t\t\t\t\t\t<start>{myStart}</start>\n')
            outfile.write(f'\t\t\t\t\t\t<end>{myEnd}</end>\n')

            outfile.write(f'\t\t\t\t\t\t<in>{int(clip[0] / (clip[2] / 100))}</in>\n')
            outfile.write(f'\t\t\t\t\t\t<out>{int(clip[1] / (clip[2] / 100))}</out>\n')
            outfile.write('\t\t\t\t\t\t<file id="file-2"/>\n')
            outfile.write('\t\t\t\t\t\t<sourcetrack>\n')
            outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')
            outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')
            outfile.write('\t\t\t\t\t\t</sourcetrack>\n')

            # Add speed effect for audio blocks
            if(clip[2] != 100):
                outfile.write('\t\t\t\t\t\t<filter>\n')
                outfile.write('\t\t\t\t\t\t\t<effect>\n')
                outfile.write('\t\t\t\t\t\t\t\t<name>Time Remap</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t<effectid>timeremap</effectid>\n')
                outfile.write('\t\t\t\t\t\t\t\t<effectcategory>motion</effectcategory>\n')
                outfile.write('\t\t\t\t\t\t\t\t<effecttype>motion</effecttype>\n')
                outfile.write('\t\t\t\t\t\t\t\t<mediatype>video</mediatype>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>variablespeed</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>variablespeed</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemin>0</valuemin>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemax>1</valuemax>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<value>0</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>speed</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>speed</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemin>-100000</valuemin>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<valuemax>100000</valuemax>\n')
                outfile.write(f'\t\t\t\t\t\t\t\t\t<value>{clip[2]}</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>reverse</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>reverse</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<value>FALSE</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t\t<parameter authoringApp="PremierePro">\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<parameterid>frameblending</parameterid>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<name>frameblending</name>\n')
                outfile.write('\t\t\t\t\t\t\t\t\t<value>FALSE</value>\n')
                outfile.write('\t\t\t\t\t\t\t\t</parameter>\n')
                outfile.write('\t\t\t\t\t\t\t</effect>\n')
                outfile.write('\t\t\t\t\t\t</filter>\n')

            if(audioFile):
                startOn = 1
            else:
                startOn = 0
            for i in range(startOn, 3):
                outfile.write('\t\t\t\t\t\t<link>\n')
                outfile.write(f'\t\t\t\t\t\t\t<linkclipref>clipitem-{(i*(len(clips)+1))+7+j}</linkclipref>\n')
                if(i == 0):
                    outfile.write('\t\t\t\t\t\t\t<mediatype>video</mediatype>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<mediatype>audio</mediatype>\n')

                if(i == 2):
                    outfile.write('\t\t\t\t\t\t\t<trackindex>2</trackindex>\n')
                else:
                    outfile.write('\t\t\t\t\t\t\t<trackindex>1</trackindex>\n')

                outfile.write(f'\t\t\t\t\t\t\t<clipindex>{j+1}</clipindex>\n')

                if(i == 1 or i == 2):
                    outfile.write('\t\t\t\t\t\t\t<groupindex>1</groupindex>\n')
                outfile.write('\t\t\t\t\t\t</link>\n')
            outfile.write('\t\t\t\t\t</clipitem>\n')
        outfile.write('\t\t\t\t\t<outputchannelindex>1</outputchannelindex>\n')
        outfile.write('\t\t\t\t</track>\n')
        outfile.write('\t\t\t</audio>\n')
        outfile.write('\t\t</media>\n')
        outfile.write('\t</sequence>\n')
        outfile.write('</xmeml>')

    conwrite('')
