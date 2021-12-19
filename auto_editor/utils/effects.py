'''utils/effects.py'''

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

    def set_start_end(self, start, end, effect_index):
        start = self._values(start, int)
        end = self._values(end, int)

        for i in range(start, end, 1):
            if(i in self.sheet):
                self.sheet[i].append(effect_index)
            else:
                self.sheet[i] = [effect_index]

    def set_all(self, effect, my_types):
        for key, _type in my_types.items():
            effect[key] = self._values(effect[key], _type)

        self.all.append(effect)

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

        for rect in args.add_rectangle:
            effect = rect.copy()
            effect['type'] = 'rectangle'

            start = effect.pop('start', None)
            end = effect.pop('end', None)

            self.set_start_end(start, end, num_effects)
            self.set_all(effect, rect_types)

            num_effects += 1

        for circle in args.add_circle:
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
