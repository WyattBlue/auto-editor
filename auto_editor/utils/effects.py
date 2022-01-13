'''utils/effects.py'''

from PIL import Image, ImageDraw, ImageFont, ImageChops

def _apply_anchor(x, y, width, height, anchor):
    if(anchor == 'ce'):
        x = int((x * 2 - width) / 2)
        y = int((y * 2 - height) / 2)
    if(anchor == 'tr'):
        x -= width
    if(anchor == 'bl'):
        y -= height
    if(anchor == 'br'):
        x -= width
        y -= height
    # Pillow uses 'tl' by default
    return x, y

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

        try:
            new_val = _type(val)
        except Exception:
            self.log.error("variable '{}' is not defined.".format(val))

        return _type(val)

    def set_timing(self, effect, effect_index):
        start = effect.pop('start')
        dur = effect.pop('dur')

        start = self._values(start[1], int)
        dur = self._values(dur[1], int)

        if(dur < 1):
            self.log.error(f"dur's value must be greater than 0. Was '{dur}'.")

        for i in range(start, start + dur, 1):
            if(i in self.sheet):
                self.sheet[i].append(effect_index)
            else:
                self.sheet[i] = [effect_index]

        return effect

    def set_all(self, effect):
        this_type = effect['type']
        new_effect = {'type': this_type}

        for name, my_tup in effect.items():
            if(name != 'type'):
                _type, val = my_tup
                if(isinstance(val, str) and val.startswith('{') and val.endswith('}')):
                    new_effect[name] = new_effect[val[1:-1]]
                else:
                    new_effect[name] = self._values(val, _type)

        return new_effect

    def resolve(self, args):
        self.width = self._vars['width']
        self.height = self._vars['height']

        effect_list = args.add_text + args.add_rectangle + args.add_ellipse + args.add_image

        for i, my_effect in enumerate(effect_list):
            effect = self.set_timing(my_effect, i)
            effect = self.set_all(effect)

            # Change font attr to ImageFont Obj. (must have font and size attr)
            if('font' in effect):
                if(effect['font'] == 'default'):
                    try:
                        effect['font'] = ImageFont.truetype(effect['font'], effect['size'])
                    except OSError:
                        effect['font'] = ImageFont.load_default()
                else:
                    try:
                        effect['font'] = ImageFont.truetype(effect['font'], effect['size'])
                    except OSError:
                        self.log.error(f"Font '{effect['font']}' not found.")

            if(effect['type'] == 'image'):
                source = Image.open(effect['source'])
                source = source.convert('RGBA')

                _op = int(effect['opacity'] * 255)

                source = ImageChops.multiply(source,
                    Image.new('RGBA', source.size, (255, 255, 255, _op))
                )
                effect['source'] = source

            if('anchor' in effect):
                anchor_vals = ['tl', 'tr', 'bl', 'br', 'ce']
                if(effect['anchor'] not in anchor_vals):
                    self.log.error('anchor must be ' + ' '.join(anchor_vals))

            self.all.append(effect)


    def apply(self, index, frame, pix_fmt):
        img = frame.to_image().convert('RGBA')

        for item in self.sheet[index]:
            pars = self.all[item]

            obj_img = Image.new('RGBA', img.size, (255, 255, 255, 0))
            draw = ImageDraw.Draw(obj_img)

            if(pars['type'] == 'text'):

                tw, th = draw.textsize(pars['content'], font=pars['font'])

                new_x, new_y = _apply_anchor(pars['x'], pars['y'], tw, th, 'ce')

                draw.text((new_x, new_y), pars['content'], font=pars['font'],
                    fill=pars['fill'])

            if(pars['type'] == 'rectangle'):
                draw.rectangle([pars['x1'], pars['y1'], pars['x2'], pars['y2']],
                    fill=pars['fill'], width=pars['width'], outline=pars['outline'])

            if(pars['type'] == 'ellipse'):
                draw.ellipse([pars['x1'], pars['y1'], pars['x2'], pars['y2']],
                    fill=pars['fill'], width=pars['width'], outline=pars['outline'])

            if(pars['type'] == 'image'):
                img_w, img_h = pars['source'].size
                pos = _apply_anchor(pars['x'], pars['y'], img_w, img_h, pars['anchor'])
                obj_img.paste(pars['source'], pos)

            img = Image.alpha_composite(img, obj_img)

        frame = frame.from_image(img).reformat(format=pix_fmt)
        return frame
