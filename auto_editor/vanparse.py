'''vanparse.py'''

import sys
import difflib

class ParserError(Exception):
    pass

def indent(text, prefix, predicate=None):
    if predicate is None:
        def predicate(line):
            return line.strip()

    def prefixed_lines():
        for line in text.splitlines(True):
            yield (prefix + line if predicate(line) else line)
    return ''.join(prefixed_lines())

def out(text):
    import re
    import textwrap

    from shutil import get_terminal_size
    width = get_terminal_size().columns - 3

    indent_regex = re.compile(r'^(\s+)')
    wrapped_lines = []

    for line in text.split('\n'):
        exist_indent = re.search(indent_regex, line)
        pre_indent = exist_indent.groups()[0] if exist_indent else ''

        wrapped_lines.append(
            textwrap.fill(line, width=width, subsequent_indent=pre_indent)
        )

    print('\n'.join(wrapped_lines))

def print_option_help(args, option):
    text = '  ' + ', '.join(option['names']) + '\n    ' + option['help'] + '\n\n'
    if(option['keywords'] != []):
        text += '    Arguments:\n    '
        for n, item in enumerate(option['keywords']):
            [[k, v]] = item.items()

            if(k != 'type'):
                _, default = v
                text += '{' + k
                text += '' if default == '' else '=' + str(default)
                text += '}' if n + 1 == len(option['keywords']) else '},'

    if(option['manual'] != ''):
        text += '{}\n\n'.format(indent(option['manual'], '    '))

    if(option['keywords'] != []):
        pass
    elif(option['action'] == 'default'):
        text += '    type: ' + option['type'].__name__
        text += '\n    default: {}\n'.format(option['default'])
        if(option['range'] is not None):
            text += '    range: ' +  option['range'] + '\n'

        if(option['choices'] is not None):
            text += '    choices: ' +  ', '.join(option['choices']) + '\n'
    elif(option['action'] in ['store_true', 'store_false']):
        text += '    type: flag\n'
    else:
        text += '    type: unknown\n'

    out(text)

def print_program_help(the_args):
    text = ''
    for options in the_args:
        for option in options:
            if(option['action'] == 'text'):
                text += '\n  ' + option['names'][0] + '\n'
            elif(option['action'] == 'blank'):
                text += '\n'
            elif(not option['hidden']):
                text += '  ' + ', '.join(option['names']) + ': ' + option['help'] + '\n'
    text += '\n'
    out(text)

def get_option(item, the_args):
    for options in the_args:
        for option in options:
            if(option['action'] != 'text' and option['action'] != 'blank'):
                dash = list(map(lambda n: n.replace('_', '-'), option['names']))
                if((item in option['names'] or item in dash)):
                    return option
    return None

def _to_key(val):
    # (val: dict) -> str
    return val['names'][0].replace('-', '')

class ArgumentParser():
    def __init__(self, program_name, version, description=None):
        self.program_name = program_name
        self._version = version
        self.description = description

        self.args = []
        self.kwarg_defaults = {
            'nargs': 1,
            'type': str,
            'default': None,
            'action': 'default',
            'range': None,
            'choices': None,
            'group': None,
            'help': '',
            'keywords': [],
            'hidden': False,
            'manual': '',
        }

    def add_argument(self, *args, **kwargs):
        my_dict = {
            'names': list(args),
        }

        for key, item in self.kwarg_defaults.items():
            my_dict[key] = item

        for key, item in kwargs.items():
            if(key not in self.kwarg_defaults):
                raise ValueError('key {} not found.'.format(key))
            my_dict[key] = item

        self.args.append(my_dict)

    def add_text(self, text):
        self.args.append({
            'names': [text],
            'action': 'text',
        });

    def add_blank(self):
        self.args.append({'action': 'blank'});

    def parse_args(self, sys_args):
        if(sys_args == [] and self.description):
            out(self.description)
            sys.exit()

        if(sys_args == ['-v'] or sys_args == ['-V']):
            out('{} version {}'.format(self.program_name, self._version))
            sys.exit()

        return ParseOptions(sys_args, self.args)


"""
    Positional Arguments
        --rectangle 0,end,10,20,20,30,#000, ...

    Keyword Arguments
        --rectangle start=0,end=end,x1=10, ...

"""

class ParseOptions():

    @staticmethod
    def parse_parameters(unsplit_arguments, op):

        ARG_SEP = ','
        KEYWORD_SEP = '='
        REQUIRED = ''

        dic = {}
        keys = []
        for key in op['keywords']:
            [[k, v]] = key.items()
            keys.append(k)
            dic[k] = v

        allow_positional_args = True

        for i, item in enumerate(unsplit_arguments.split(ARG_SEP)):
            if(i+1 > len(keys)):
                raise ParserError(f"Too many arguments, starting with '{item}'.")

            if(KEYWORD_SEP in item):
                allow_positional_args = False

                parameters = item.split(KEYWORD_SEP)
                if(len(parameters) > 2):
                    raise ParserError(f"Invalid Syntax: '{item}'.")
                key, val = parameters
                if(key not in dic):
                    raise ParserError(f"Parameter '{key}' does not exist.")
                dic[key] = (dic[key][0], val)
            elif(allow_positional_args):
                dic[keys[i]] = (dic[keys[i]][0], item)
            else:
                raise ParserError('Positional argument follows keyword argument.')

        # Check if any required args are not specified.
        for key, type_val in dic.items():
            if(type_val[1] == REQUIRED):
                raise ParserError(f"Parameter '{key}' is required.")
        return dic

    def __init__(self, sys_args, *args):
        # Set the default options.
        for options in args:
            for option in options:
                if(option['action'] == 'text' or option['action'] == 'blank'):
                    continue

                key = _to_key(option)
                if(option['action'] == 'store_true'):
                    value = False
                elif(option['action'] == 'store_false'):
                    value = True
                elif(option['nargs'] != 1):
                    value = []
                elif(option['default'] is None):
                    value = None
                else:
                    value = option['type'](option['default'])
                setattr(self, key, value)

        # Figure out command line options changed by user.
        my_list = []
        used_options = []
        _set = []
        setting_inputs = True
        option_list = 'input'
        list_type = str
        i = 0
        while i < len(sys_args):
            item = sys_args[i]
            label = 'option' if item.startswith('--') else 'short'

            option = get_option(item, the_args=args)

            def error_message(args, item, label):

                def all_names(args):
                    name_set = set()
                    for options in args:
                        for opt in options:
                            if(opt['action'] not in ['text', 'blank']):
                                for names in opt['names']:
                                    name_set.add(names)
                    return name_set

                opt_list = all_names(args)
                close_matches = difflib.get_close_matches(item, opt_list)
                if(close_matches):
                    return 'Unknown {}: {}\n\n    Did you mean:\n        '.format(
                        label, item) + ', '.join(close_matches)
                return 'Unknown {}: {}'.format(label, item)

            if(option is None):
                # Unknown Option!
                if(setting_inputs and (option_list != 'input' or (option_list == 'input' and not item.startswith('-')))):
                    # Option is actually an input file, like example.mp4

                    if(option_list != 'input'):
                        _op = used_options[-1]
                        if(_op['keywords'] != []):
                            item = self.parse_parameters(item, _op)
                    my_list.append(item)
                else:
                    raise ParserError(error_message(args, item, label))
            else:
                # We found the option.
                if(option_list is not None):
                    setattr(self, option_list, list(map(list_type, my_list)))

                setting_inputs = False
                option_list = None
                my_list = []

                if(option in used_options):
                    raise ParserError('Cannot repeat option {} twice.'.format(option['names'][0]))

                used_options.append(option)

                key = _to_key(option)
                _set.append(key)

                nextItem = None if i == len(sys_args) - 1 else sys_args[i+1]
                if(nextItem == '-h' or nextItem == '--help'):
                    print_option_help(args, option)
                    sys.exit()

                if(option['nargs'] != 1):
                    setting_inputs = True
                    option_list = key
                    list_type = option['type']
                elif(option['action'] == 'store_true'):
                    value = True
                elif(option['action'] == 'store_false'):
                    value = False
                else:
                    if(nextItem is None and option['nargs'] == 1):
                        raise ParserError(f"{option['names'][0]} needs argument.")
                    value = option['type'](nextItem)

                    if(option['choices'] is not None and value not in option['choices']):
                        option_name = option['names'][0]
                        my_choices = ', '.join(option['choices'])

                        raise ParserError('{} is not a choice for {}\nchoices are:\n  {}'.format(
                            value, option_name, my_choices))
                    i += 1
                setattr(self, key, value)

            i += 1
        if(setting_inputs):
            setattr(self, option_list, list(map(list_type, my_list)))
        setattr(self, '_set', _set)
        if(self.help):
            print_program_help(args)
            sys.exit()
