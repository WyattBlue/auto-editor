import re
import sys
import difflib
import textwrap
from shutil import get_terminal_size

from typing import List, Optional


class ParserError(Exception):
    pass


def indent(text: str, prefix, predicate=None) -> str:
    if predicate is None:
        def predicate(line):
            return line.strip()

    def prefixed_lines():
        for line in text.splitlines(True):
            yield (prefix + line if predicate(line) else line)
    return ''.join(prefixed_lines())


def out(text: str) -> None:
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


def print_option_help(option):
    from dataclasses import fields, _MISSING_TYPE

    text = '  ' + ', '.join(option['names']) + '\n    ' + option['help'] + '\n\n'
    if option['dataclass'] is not None:
        text += '    Arguments:\n    '

        args = []
        for field in fields(option['dataclass']):
            if field.name != '_type':
                arg = '{' + field.name
                if not isinstance(field.default, _MISSING_TYPE):
                    arg += '=' + str(field.default)
                arg += '}'
                args.append(arg)

        text += ','.join(args)

    if option['manual'] != '':
        text += '{}\n\n'.format(indent(option['manual'], '    '))

    if option['dataclass'] is not None:
        pass
    elif option['action'] == 'default':
        text += f"    type: {option['type'].__name__}\n"
        text += f"    nargs: {option['nargs']}\n"
        text += f"    default: {option['default']}\n"

        if option['range'] is not None:
            text += f"    range: {option['range']}\n"

        if option['choices'] is not None:
            text += '    choices: ' +  ', '.join(option['choices']) + '\n'
    elif option['action'] in ('store_true', 'store_false'):
        text += '    type: flag\n'
    else:
        text += '    type: unknown\n'

    out(text)


def print_program_help(options):
    text = ''
    for option in options:
        if option['_type'] == 'text':
            text += '\n  ' + option['text'] + '\n'
        elif option['_type'] == 'blank':
            text += '\n'
        elif (option['_type'] == 'required' or
            (option['_type'] == 'option' and not option['hidden'])):
            text += '  ' + ', '.join(option['names']) + ': ' + option['help'] + '\n'
    text += '\n'
    out(text)


def to_underscore(name: str) -> str:
    """Convert new style options to old style.  e.g. --hello-world -> --hello_world"""
    return name[:2] + name[2:].replace('-', '_')


def to_key(val: dict) -> str:
    """Convert option name to arg key.  e.g. --hello-world -> hello_world"""
    return val['names'][0][:2].replace('-', '') + val['names'][0][2:].replace('-', '_')


def get_option(name: str, options: List[dict]) -> Optional[dict]:
    for option in options:
        if name in option['names'] or name in map(to_underscore, option['names']):
            return option
    return None


class ArgumentParser:
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
            'help': '',
            'dataclass': None,
            'hidden': False,
            'manual': '',
            '_type': 'option',
        }

        self.required_defaults = {
            'nargs': '*',
            'type': str,
            'choices': None,
            'help': '',
            '_type': 'required',
        }

    def add_argument(self, *args, **kwargs):
        my_dict = self.kwarg_defaults.copy()
        my_dict['names'] = args

        for key, val in kwargs.items():
            my_dict[key] = val

        self.args.append(my_dict)


    def add_required(self, *args, **kwargs):
        my_dict = self.required_defaults.copy()
        my_dict['names'] = args

        for key, val in kwargs.items():
            my_dict[key] = val

        self.args.append(my_dict)


    def add_text(self, text: str):
        self.args.append({'text': text, '_type': 'text'});


    def add_blank(self):
        self.args.append({'_type': 'blank'});


    def parse_args(self, sys_args: list):
        if sys_args == [] and self.description:
            out(self.description)
            sys.exit()

        if sys_args == ['-v'] or sys_args == ['-V']:
            out('{} version {}'.format(self.program_name, self._version))
            sys.exit()

        return ParseOptions(sys_args, self.args)


class ParseOptions:

    @staticmethod
    def parse_dataclass(unsplit_arguments, op):
        """
        Positional Arguments
            --rectangle 0,end,10,20,20,30,#000, ...

        Keyword Arguments
            --rectangle start=0,end=end,x1=10, ...
        """

        from dataclasses import fields

        ARG_SEP = ','
        KEYWORD_SEP = '='

        d_name = op['dataclass'].__name__

        keys = []
        for field in fields(op['dataclass']):
            keys.append(field.name)

        kwargs = {}
        args = []

        allow_positional_args = True

        for i, arg in enumerate(unsplit_arguments.split(ARG_SEP)):
            if i+1 > len(keys):
                raise ParserError(f"{d_name} has too many arguments, starting "
                    f"with '{arg}'.")

            if KEYWORD_SEP in arg:
                allow_positional_args = False

                parameters = arg.split(KEYWORD_SEP)
                if len(parameters) > 2:
                    raise ParserError(f"{d_name} invalid syntax: '{arg}'.")
                key, val = parameters
                if key not in keys:
                    raise ParserError(f"{d_name} got an unexpected keyword '{key}'")

                kwargs[key] = val
            elif allow_positional_args:
                args.append(arg)
            else:
                raise ParserError(f'{d_name} positional argument follows keyword argument.')

        try:
            dataclass_instance = op['dataclass'](*args, **kwargs)
        except TypeError as err:
            err_list = [d_name] + str(err).split(' ')[1:]
            raise ParserError(' '.join(err_list))

        return dataclass_instance


    @staticmethod
    def parse_arg(option: dict, arg):

        option_name = option['names'][0]

        if arg is None and option['nargs'] == 1:
            raise ParserError(f"{option_name} needs argument.")

        try:
            value = option['type'](arg)
        except TypeError as e:
            raise ParserError(str(e))

        if option['choices'] is not None and value not in option['choices']:
            my_choices = ', '.join(option['choices'])

            raise ParserError(f'{value} is not a choice for {option_name}\n'
                f'choices are:\n  {my_choices}')

        return value


    def set_arg_list(self, option_list: str, my_list: list, list_type: type) -> None:
        if list_type is not None:
            setattr(self, option_list, list(map(list_type, my_list)))
        else:
            setattr(self, option_list, my_list)


    def __init__(self, sys_args: List[str], options_reqs: List[dict]) -> None:

        # Partition options and requireds.
        options = []
        requireds = []
        option_names = []

        for item in options_reqs:
            if item['_type'] == 'option':
                options.append(item)

                for name in item['names']:
                    option_names.append(name)

                if item['action'] == 'store_true':
                    value = False
                elif item['action'] == 'store_false':
                    value = True
                elif item['nargs'] != 1:
                    value = []
                elif item['default'] is None:
                    value = None
                else:
                    value = item['type'](item['default'])
                setattr(self, to_key(item), value)

            if item['_type'] == 'required':
                requireds.append(item)

        # Figure out command line options changed by user.
        used_options = []

        req_list = []
        req_list_name = requireds[0]['names'][0]
        req_list_type = requireds[0]['type']
        setting_req_list = requireds[0]['nargs'] != 1

        option_list = []
        op_list_name = None
        op_list_type = str
        setting_op_list = False

        i = 0
        while i < len(sys_args):
            arg = sys_args[i]
            option = get_option(arg, options)

            if option is None:
                if setting_op_list:
                    if used_options and used_options[-1]['dataclass'] is not None:
                        op_list_type = None
                        arg = self.parse_dataclass(arg, used_options[-1])

                    option_list.append(arg)

                elif requireds and not arg.startswith('--'):

                    if requireds[0]['nargs'] == 1:
                        setattr(self, req_list_name, self.parse_arg(requireds[0], arg))
                        requireds.pop()
                    else:
                        req_list.append(arg)
                else:
                    label = 'option' if arg.startswith('--') else 'short'

                    # 'Did you mean' message might appear that options need a comma.
                    if arg.replace(',', '') in option_names:
                        raise ParserError(f"Option '{arg}' has an unnecessary comma.")

                    close_matches = difflib.get_close_matches(arg, option_names)
                    if close_matches:
                        raise ParserError(
                            'Unknown {}: {}\n\n    Did you mean:\n        '.format(
                            label, arg) + ', '.join(close_matches)
                        )
                    raise ParserError(f'Unknown {label}: {arg}')
            else:
                if op_list_name is not None:
                    self.set_arg_list(op_list_name, option_list, op_list_type)

                if option in used_options:
                    raise ParserError(f"Cannot repeat option {option['names'][0]} twice.")

                used_options.append(option)

                setting_op_list = False
                option_list = []
                op_list_name = None

                key = to_key(option)

                next_arg = None if i == len(sys_args) - 1 else sys_args[i+1]
                if next_arg == '-h' or next_arg == '--help':
                    print_option_help(option)
                    sys.exit()

                if option['nargs'] != 1:
                    setting_op_list = True
                    op_list_name = key
                    op_list_type = option['type']
                elif option['action'] == 'store_true':
                    value = True
                elif option['action'] == 'store_false':
                    value = False
                else:
                    value = self.parse_arg(option, next_arg)
                    i += 1
                setattr(self, key, value)

            i += 1

        if setting_op_list:
            self.set_arg_list(op_list_name, option_list, op_list_type)

        if setting_req_list:
            self.set_arg_list(req_list_name, req_list, req_list_type)

        if self.help:
            print_program_help(options_reqs)
            sys.exit()
