'''utils/effects.py'''

class Effect():
    __slots__ = ('all', 'sheet', '_vars', 'log', 'background', 'width', 'height')
    def __init__(self, args, log, _vars):
        self.all = []
        self.sheet = {}
        self._vars = _vars
        self.log = log
        self.background = args.background

    def add_var(self, key, item):
        self._vars[key] = item

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

    def set_start_end(self, effect, effect_index):
        start = effect.pop('start')
        end = effect.pop('end')

        start = self._values(start[1], int)
        end = self._values(end[1], int)

        for i in range(start, end, 1):
            if(i in self.sheet):
                self.sheet[i].append(effect_index)
            else:
                self.sheet[i] = [effect_index]

        return effect

    def set_all(self, effect):
        new_effect = {}
        for name, my_tup in effect.items():
            if(name == 'type'):
                new_effect['type'] = my_tup
            else:
                _type, val = my_tup
                if(val.startswith('{') and val.endswith('}')):
                    new_effect[name] = new_effect[val[1:-1]]
                else:
                    new_effect[name] = self._values(val, _type)

        self.all.append(new_effect)

    def resolve(self, args):
        self.width = self._vars['width']
        self.height = self._vars['height']

        effect_list = args.add_rectangle + args.add_ellipse + args.zoom

        for i, my_effect in enumerate(effect_list):
            effect = self.set_start_end(my_effect, i)
            self.set_all(effect)

    def apply(self, index, frame, pix_fmt):
        from PIL import Image, ImageDraw, ImageFont

        img = frame.to_image()

        for item in self.sheet[index]:
            pars = self.all[item]

            if(pars['type'] == 'rectangle'):
                draw = ImageDraw.Draw(img)
                draw.rectangle([pars['x1'], pars['y1'], pars['x2'], pars['y2']],
                    fill=pars['fill'], width=pars['width'], outline=pars['outline'])

            if(pars['type'] == 'ellipse'):
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
