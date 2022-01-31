from dataclasses import asdict, fields

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

class Effect:
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

    def set_timing(self, obj, index):
        start = self._values(obj.start, int)
        dur = self._values(obj.dur, int)

        if dur < 1:
            self.log.error(f"dur's value must be greater than 0. Was '{dur}'.")

        for i in range(start, start + dur, 1):
            if i in self.sheet:
                self.sheet[i].append(index)
            else:
                self.sheet[i] = [index]

    def resolve(self, args):
        self.width = self._vars['width']
        self.height = self._vars['height']

        pool = args.add_text + args.add_rectangle + args.add_ellipse + args.add_image

        for i, obj in enumerate(pool):

            if isinstance(obj, str):
                raise TypeError('obj is str')

            dic_value = {}
            for k, v in asdict(obj).items():
                dic_value[k] = v

            dic_type = {}
            for field in fields(obj):
                dic_type[field.name] = field.type

            # Convert to the correct types
            for k, _type in dic_type.items():
                obj.__setattr__(k, self._values(dic_value[k], _type))

            self.set_timing(obj, i)

            # Change font attr to ImageFont Obj. (must have font and size attr)
            if obj._type == 'text':
                try:
                    obj.font = ImageFont.truetype(obj.font, obj.size)
                except OSError:
                    if obj.font == 'default':
                        obj.font = ImageFont.load_default()
                    else:
                        self.log.error(f"Font '{obj.font}' not found.")

            if obj._type == 'image':
                anchor_vals = ['tl', 'tr', 'bl', 'br', 'ce']
                if obj.anchor not in anchor_vals:
                    self.log.error('anchor must be ' + ' '.join(anchor_vals))

                source = Image.open(obj.source)
                source = source.convert('RGBA')

                _op = int(obj.opacity * 255)

                source = ImageChops.multiply(source,
                    Image.new('RGBA', source.size, (255, 255, 255, _op))
                )
                obj.source = source

            self.all.append(obj)


    def apply(self, index, frame, pix_fmt):
        img = frame.to_image().convert('RGBA')

        for item in self.sheet[index]:
            obj = self.all[item]

            obj_img = Image.new('RGBA', img.size, (255, 255, 255, 0))
            draw = ImageDraw.Draw(obj_img)

            if obj._type == 'text':
                text_w, text_h = draw.textsize(obj.content, font=obj.font)
                pos = _apply_anchor(obj.x, obj.y, text_w, text_h, 'ce')
                draw.text(pos, obj.content, font=obj.font, fill=obj.fill)

            if obj._type == 'rectangle':
                draw.rectangle([obj.x1, obj.y1, obj.x2, obj.y2],
                    fill=obj.fill, width=obj.width, outline=obj.outline)

            if obj._type == 'ellipse':
                draw.ellipse([obj.x1, obj.y1, obj.x2, obj.y2],
                    fill=obj.fill, width=obj.width, outline=obj.outline)

            if obj._type == 'image':
                img_w, img_h = obj.source.size
                pos = _apply_anchor(obj.x, obj.y, img_w, img_h, obj.anchor)
                obj_img.paste(obj.source, pos)

            img = Image.alpha_composite(img, obj_img)

        frame = frame.from_image(img).reformat(format=pix_fmt)
        return frame
