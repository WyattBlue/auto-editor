'''utils/effects.py'''

import numpy as np

# Included Libraries
from auto_editor.analyze.audio import audio_detection
from auto_editor.cutting import merge, apply_basic_spacing

from .interpolate import interpolate

class Effect():
    def _values(self, val, _type):
        # just to be clear, val can only be None if the default value is None.
        # Users can't set the argument to None themselves.
        if(val is None):
            return None

        if(_type is str):
            return str(val)

        for key, item in self._vars.items():
            if(val == key):
                return _type(item)

        if(not isinstance(val, int)
            and not (val.replace('.', '', 1)).replace('-', '', 1).isdigit()):
            self.log.error("variable '{}' is not defined.".format(val))
        return _type(val)

    def boolean_expression(self, val):
        # type: (str) -> np.ndarray
        invert = False

        if('>' in val and '<' in val):
            self.log.error('Cannot have both ">" and "<" in same expression.')
        if('>' in val):
            exp = val.split('>')
        else:
            exp = val.split('<')
            invert = True

        if(len(exp) != 2):
            self.log.error('Only 1 expression supported, not {}.'.format(len(exp)-1))

        if(exp[1] == 'audio'):
            self.log.error('audio variable must be on the left side only.')

        if(exp[0] != 'audio'):
            self.log.error('Only audio variable is supported.')

        if(self.audio_samples is None or self.sample_rate is None):
            self.log.error('No audio data found.')

        new_list = audio_detection(self.audio_samples, self.sample_rate,
            self._values(exp[1], float), self.fps, self.log)

        if(invert):
            new_list = np.invert(new_list)

        return new_list

    def set_all(self, effect, my_types):
        for key, _type in my_types.items():
            effect[key] = self._values(effect[key], _type)

        self.all.append(effect)

    def set_start_end(self, start, end, effect_index):

        def resolve_start_end(val):
            # type: (str) -> np.ndarray | int
            if('>' in val or '<' in val):
                return self.boolean_expression(val)
            else:
                return self._values(val, int)

        def add_effect(i, effect_index):
            if(i in self.sheet):
                self.sheet[i].append(effect_index)
            else:
                self.sheet[i] = [effect_index]

        start = resolve_start_end(start)
        end = resolve_start_end(end)

        if(isinstance(start, int) and isinstance(end, int)):
            for i in range(start, end, 1):
                add_effect(i, effect_index)
        elif(isinstance(start, int)):
            self.log.error('The start parameter must also be a boolean expression.')
        elif(isinstance(end, int)):
            # only start is a numpy array
            # If this happens, the end parameter's value doesn't matter.
            indexs = np.where(start)[0]
            for index in indexs:
                add_effect(index, effect_index)
        else:
            # both start and end are numpy arrays
            chunks = apply_basic_spacing(merge(start, end), self.fps, 0, 0, self.log)
            for item in chunks:
                if(item[2] == 1):
                    for i in range(item[0], item[1]):
                        add_effect(i, effect_index)

    def resolve(self, args):
        self.fps = self._vars['fps']
        self.width = self._vars['width']
        self.height = self._vars['height']

        num_effects = 0

        rect_types = {
            'x1': int, 'y1': int, 'x2': int, 'y2': int, 'fill': str, 'width': int,
            'outline': str,
        }
        circle_types = rect_types
        zoom_types = {
            'zoom': float, 'end_zoom': float, 'x': int, 'y': int, 'interpolate': str,
        }

        for rect in args.rectangle:
            effect = rect.copy()
            effect['type'] = 'rectangle'

            start = effect.pop('start', None)
            end = effect.pop('end', None)

            self.set_start_end(start, end, num_effects)
            self.set_all(effect, rect_types)

            num_effects += 1

        for circle in args.circle:
            effect = circle.copy()
            effect['type'] = 'circle'

            start = effect.pop('start', None)
            end = effect.pop('end', None)

            self.set_start_end(start, end, num_effects)
            self.set_all(effect, circle_types)

            num_effects += 1

        for zoom in args.zoom:
            if(zoom['end_zoom'] == '{zoom}'):
                zoom['end_zoom'] = zoom['zoom']

            effect = zoom.copy()
            effect['type'] = 'zoom'

            start = effect.pop('start', None)
            end = effect.pop('end', None)

            self.set_start_end(start, end, num_effects)
            self.set_all(effect, zoom_types)

            num_effects += 1

    def add_var(self, key, item):
        self._vars[key] = item

    def __init__(self, args, log, _vars):
        self.all = []
        self.sheet = {}
        self._vars = _vars
        self.log = log
        self.background = args.background

        self.audio_samples = None
        self.sample_rate = None

    def apply(self, index, frame, pix_fmt):
        from PIL import Image, ImageDraw, ImageFont

        img = frame.to_image()

        for item in self.sheet[index]:
            pars = self.all[item]

            if(pars['type'] == 'rectangle'):
                draw = ImageDraw.Draw(img)
                draw.rectangle([pars['x1'], pars['y1'], pars['x2'], pars['y2']],
                    fill=pars['fill'], width=pars['width'], outline=pars['outline'])

            if(pars['type'] == 'circle'):
                draw = ImageDraw.Draw(img)
                draw.ellipse([pars['x1'], pars['y1'], pars['x2'], pars['y2']],
                    fill=pars['fill'], width=pars['width'], outline=pars['outline'])

            if(pars['type'] == 'zoom'):
                x = pars['x']
                y = pars['y']
                zoom2 = pars['zoom'] * 2

                x1 = round(x - self.width / zoom2)
                y1 = round(y - self.height / zoom2)
                x2 = round(x + self.width / zoom2)
                y2 = round(y + self.height / zoom2)

                bg = Image.new(img.mode, (x2 - x1, y2 - y1), self.background)
                bg.paste(img, (-x1, -y1))

                img = bg.resize((self.width, self.height), Image.LANCZOS)

        frame = frame.from_image(img).reformat(format=pix_fmt)
        return frame
