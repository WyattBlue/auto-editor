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

        # from operator import itemgetter
        # self.contents = sorted(self.contents, key=itemgetter(0))


    #[[0, 26, 1], [26, 34, 0], [34, 396, 1], [396, 410, 0], [410, 522, 1], [522, 1192, 0], [1192, 1220, 1], [1220, 1273, 0]]

    # chunk[start_inclusive, ending_exclusive, speed_index[]

    def edit(self, chunks, speeds):

        # lexicon cuts
        lexicon_cuts = []

        for chunk in chunks:
            the_speed = speeds[chunk[2]]
            if(the_speed == 1):
                continue

            label = "NULL" if the_speed == 99999 else the_speeds
            lexicon_cuts.append([chunk[0], chunk[1], label])

        for cut in lexicon_cuts:
            i = 0
            print(cut)
            while(i < len(self.contents)):
                content = self.contents[i]

                if(content[0] >= cut[0] and content[1] <= cut[1]):
                    self.contents.pop(i)
                    i -= 1
                elif(cut[0] <= content[1] and cut[1] > content[0]):

                    diff = min(cut[1], content[1]) - max(cut[0], content[0])
                    if(content[0] > cut[0]):
                        self.contents[i][0] -= diff
                        self.contents[i][1] -= diff

                    self.contents[i][1] -= diff

                elif(content[0] >= cut[0]):
                    diff = (cut[1] - cut[0])
                    self.contents[i][0] -= diff
                    self.contents[i][1] -= diff

                i += 1

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


if __name__ == '__main__':
    test = SubtitleParser()
    test.contents = [
        [0, 10, "A"], [0, 10, "a"],
        [10, 20, "B"], [10, 20, "b"],
        [20, 30, "C"],
        [30, 40, "D"], [30, 40, 'd'],
    ]

    speeds = [99999, 1]
    chunks = [[0, 15, 1], [15, 25, 0], [25, 100, 1]]
    print(test.contents)
    test.edit(chunks, speeds)
    print('\nResults:')
    print(test.contents)


def cut_subtitles(ffmpeg, inp, chunks, speeds, fps, temp, log):
    for s, sub in enumerate(inp.subtitle_streams):
        file_path = os.path.join(temp, '{}s.{}'.format(s, sub['ext']))
        new_path = os.path.join(temp, 'new{}s.{}'.format(s, sub['ext']))

        with open(file_path, 'r') as file:
            parser = SubtitleParser()
            if(sub['codec'] in parser.supported_codecs):
                parser.parse(file.read(), fps, sub['codec'])
                parser.edit(chunks, speeds)
                parser.write(new_path)
            else:
                import shutil
                shutil.copy(file_path, new_path)
