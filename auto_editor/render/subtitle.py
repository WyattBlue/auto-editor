'''render/subtitle.py'''

import os
import re

class SubtitleParser:
    def __init__(self):
        self.supported_codecs = ['ass']

    def parse(self, text, fps, codec):
        self.fps = fps
        self.codec = codec
        self.header = ''
        self.footer = ''
        self.contents = []

        is_footer = False

        for line in text.split('\n'):
            anal = re.match(r'(.*)(\d+:\d+:[\d.]+)(.*)(\d+:\d+:[\d.]+)(.*)', line)
            if(anal is None):
                if(is_footer):
                    self.footer += line + '\n'
                else:
                    self.header += line + '\n'
            else:
                is_footer = True
                starting_str = anal.group(2)
                ending_str = anal.group(4)

                self.contents.append(
                    [self.to_frame(starting_str), self.to_frame(ending_str),
                    anal.group(1), anal.group(3), anal.group(5) + '\n'
                    ]
                )

    def edit(self, chunks, speeds):
        pass

    def write(self, file_path):
        with open(file_path, 'w') as file:
            file.write(self.header)
            for item in self.contents:
                file.write('{before}{start_time}{middle}{end_time}{after}'.format(
                    before=item[2],
                    start_time=self.to_timecode(item[0]),
                    middle=item[3],
                    end_time=self.to_timecode(item[1]),
                    after=item[4],
                ))
            file.write(self.footer)

    # H:MM:SS.MM+
    def to_frame(self, text):
        # type: (str) -> int
        nums = re.match(r'(\d+):(\d+):([\d.]+)', text)
        hours, minutes, seconds = nums.groups()
        return round((int(hours) * 3600 + int(minutes) * 60 + float(seconds)) * self.fps)

    def to_timecode(self, frame):
        # type: (int) -> str
        seconds = frame / self.fps

        m, s = divmod(seconds, 60)
        h, m = divmod(m, 60)

        if(len(str(int(s))) == 1):
            s = '0' + str('{:.2f}'.format(round(s, 3)))
        else:
            s = str('{:.2f}'.format(round(s, 3)))

        return '{:d}:{:02d}:{}'.format(int(h), int(m), s)


def cut_subtitles(ffmpeg, inp, chunks, speeds, fps, temp, log):
    for s, sub in enumerate(inp.subtitle_streams):
        file_path = os.path.join(temp, '{}s.{}'.format(s, sub['ext']))
        new_path = os.path.join(temp, 'new{}s.{}'.format(s, sub['ext']))

        with open(file_path, 'r') as file:
            parser = SubtitleParser()
            if(sub['codec'] in parser.supported_codecs):
                parser.parse(file.read(), fps, sub['codec'])
                parser.write(new_path)
            else:
                import shutil
                shutil.copy(file_path, new_path)
