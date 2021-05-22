'''final_cut_pro.py'''

import os

from auto_editor.formats.utils import indent

def fcp_xml(myInput: str, temp: str, output, ffprobe, clips, chunks, tracks: int,
    sampleRate, audioFile, fps, log):

    pathurl = 'file://' + os.path.abspath(myInput)
    name = os.path.splitext(os.path.basename(myInput))[0]

    def fraction(inp, fps) -> str:
        from fractions import Fraction

        if(inp == 0):
            return '0s'

        if(isinstance(inp, float)):
            inp = Fraction(inp)
        if(isinstance(fps, float)):
            fps = Fraction(fps)

        frac = Fraction(inp, fps).limit_denominator()
        num = frac.numerator
        dem = frac.denominator

        if(dem < 3000):
            factor = int(3000 / dem)

            if(factor == 3000 / dem):
                num *= factor
                dem *= factor
            else:
                # Good enough but has some error that are impacted at speeds such as 150%.
                total = 0
                while(total < frac):
                    total += Fraction(1, 30)
                num = total.numerator
                dem = total.denominator

        return f'{num}/{dem}s'

    if(not audioFile):
        width, height = ffprobe.getResolution(myInput).split('x')
        total_dur = ffprobe.getDuration(myInput)
        if(total_dur == 'N/A'):
            total_dur = ffprobe.pipe(['-show_entries', 'format=duration', '-of',
                'default=noprint_wrappers=1:nokey=1', myInput]).strip()
    else:
        width, height = '1920', '1080'
        total_dur = ffprobe.getAudioDuration(myInput)
    total_dur = float(total_dur) * fps

    with open(output, 'w', encoding='utf-8') as outfile:

        frame_duration = fraction(1, fps)

        outfile.write('<?xml version="1.0" encoding="UTF-8"?>\n')
        outfile.write('<!DOCTYPE fcpxml>\n\n')
        outfile.write('<fcpxml version="1.9">\n')
        outfile.write('\t<resources>\n')
        outfile.write(f'\t\t<format id="r1" name="FFVideoFormat{height}p{fps}" '\
            f'frameDuration="{frame_duration}" width="{width}" height="{height}"'\
            ' colorSpace="1-1-1 (Rec. 709)"/>\n')

        outfile.write(f'\t\t<asset id="r2" name="{name}" start="0s" '\
            'hasVideo="1" format="r1" hasAudio="1" '\
            f'audioSources="1" audioChannels="2" audioRate="{sampleRate}">\n')

        outfile.write(f'\t\t\t<media-rep kind="original-media" '\
            f'src="{pathurl}"></media-rep>\n')
        outfile.write('\t\t</asset>\n')
        outfile.write('\t</resources>\n')
        outfile.write('\t<library>\n')
        outfile.write('\t\t<event name="auto-editor output">\n')
        outfile.write(f'\t\t\t<project name="{name}">\n')
        outfile.write(indent(4,
            '<sequence format="r1" tcStart="0s" tcFormat="NDF" '\
            'audioLayout="stereo" audioRate="48k">',
            '\t<spine>')
        )

        last_dur = 0

        for _, clip in enumerate(clips):
            clip_dur = (clip[1] - clip[0]) / (clip[2] / 100)
            dur = fraction(clip_dur, fps)

            close = '/' if clip[2] == 100 else ''

            if(last_dur == 0):
                outfile.write(indent(6, f'<asset-clip name="{name}" offset="0s" ref="r2"'\
                f' duration="{dur}" audioRole="dialogue" tcFormat="NDF"{close}>'))
            else:
                start = fraction(clip[0] / (clip[2] / 100), fps)
                off = fraction(last_dur, fps)
                outfile.write(indent(6,
                    f'<asset-clip name="{name}" offset="{off}" ref="r2" '\
                    f'duration="{dur}" start="{start}" audioRole="dialogue" '\
                    f'tcFormat="NDF"{close}>',
                ))

            if(clip[2] != 100):
                # See the "Time Maps" section.
                # https://developer.apple.com/library/archive/documentation/FinalCutProX
                #    /Reference/FinalCutProXXMLFormat/StoryElements/StoryElements.html

                frac_total = fraction(total_dur, fps)
                total_dur_divided_by_speed = fraction((total_dur) / (clip[2] / 100), fps)

                outfile.write(indent(6,
                    '\t<timeMap>',
                    '\t\t<timept time="0s" value="0s" interp="smooth2"/>',
                    f'\t\t<timept time="{total_dur_divided_by_speed}" value="{frac_total}" interp="smooth2"/>',
                    '\t</timeMap>',
                    '</asset-clip>'
                ))

            last_dur += clip_dur

        outfile.write('\t\t\t\t\t</spine>\n')
        outfile.write('\t\t\t\t</sequence>\n')
        outfile.write('\t\t\t</project>\n')
        outfile.write('\t\t</event>\n')
        outfile.write('\t</library>\n')
        outfile.write('</fcpxml>\n')
