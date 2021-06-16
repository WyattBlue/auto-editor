'''vanparse.py'''

from __future__ import print_function

import os
import sys
import difflib

def out(text):
    import re
    import textwrap
    from shutil import get_terminal_size

    indent_regex = re.compile(r'^(\s+)')
    width = get_terminal_size().columns - 3

    wrapped_lines = []

    for line in text.split('\n'):
        exist_indent = re.search(indent_regex, line)
        pre_indent = exist_indent.groups()[0] if exist_indent else ''

        wrapped_lines.append(
            textwrap.fill(line, width=width, subsequent_indent=pre_indent)
        )

    print('\n'.join(wrapped_lines))

def print_option_help(args, option):
    text = ''
    if(option['action'] == 'grouping'):
        text += '  {}:\n'.format(option['names'][0])
    else:
        text += '  ' + ', '.join(option['names']) + '\n    ' + option['help'] + '\n\n'
        if(option['extra'] != ''):
            text += '\n{}\n\n'.format(option['extra'])

    if(option['action'] == 'default'):
        text += '    type: ' + option['type'].__name__
        text += '\n    default: {}\n'.format(option['default'])
        if(option['range'] is not None):
            text += '    range: ' +  option['range'] + '\n'

        if(option['choices'] is not None):
            text += '    choices: ' +  ', '.join(option['choices']) + '\n'
    elif(option['action'] == 'grouping'):
        for options in args:
            for op in options:
                if(op['grouping'] == option['names'][0]):
                    text += '  ' + ', '.join(op['names']) + ': ' + op['help'] + '\n'
    elif(option['action'] == 'store_true'):
        text += '    type: flag\n'
    else:
        text += '    type: unknown\n'

    if(option['grouping'] is not None):
        text += '    group: ' + option['grouping'] + '\n'
    out(text)

def print_program_help(root, the_args):
    text = ''
    for options in the_args:
        for option in options:
            if(option['action'] == 'grouping'):
                text += "\n  {}:\n".format(option['names'][0])
            else:
                text += '  ' + ', '.join(option['names']) + ': ' + option['help'] + '\n'
    text += '\n'
    if(root == 'auto-editor'):
        text += '  Have an issue? Make an issue. Visit '\
            'https://github.com/wyattblue/auto-editor/issues\n\n  The help option '\
            'can also be used on a specific option:\n     auto-editor '\
            '--frame_margin --help\n'
    out(text)

def get_option(item, group, the_args):
    for options in the_args:
        for option in options:
            if(item in option['names'] and group in ['global', option['grouping']]):
                return option
    return None


class ArgumentParser():
    def __init__(self, program_name, version, description):
        self.program_name = program_name
        self._version = version
        self.description = description

        self.args = []

    def add_argument(self, *names, nargs=1, type=str, default=None, action='default',
        range=None, choices=None, group=None, help='', extra=''):

        self.args.append({
            'names': names,
            'nargs': nargs,
            'type': type,
            'default': default,
            'action': action,
            'help': help,
            'extra': extra,
            'range': range,
            'choices': choices,
            'grouping': group,
        })

    def parse_args(self, sys_args, log, root):

        if(sys_args == []):
            out(self.description)
            sys.exit()

        if(sys_args == ['-v'] or sys_args == ['-V']):
            out('{} version {}'.format(self.program_name, self._version))
            sys.exit()

        return ParseOptions(sys_args, log, root, self.args)


class ParseOptions():
    def setConfig(self, config_path, root):
        if(not os.path.isfile(config_path)):
            return

        with open(config_path, 'r') as file:
            lines = file.readlines()

        # Set attributes based on the config file to act as the new defaults.
        for item in lines:
            if('#' in item):
                item = item[: item.index('#')]
            item = item.replace(' ', '')
            if(item.strip() == '' or (not item.startswith(root))):
                continue
            value = item[item.index('=')+1 :]

            if(value[0] == "'" and value[-1] == "'"):
                value = value[1:-1]
            elif(value == 'None'):
                value = None
            elif('.' in value):
                value = float(value)
            else:
                value = int(value)

            key = item[: item.index('=')]
            key = key[key.rfind('.')+1:]

            if(getattr(self, key) != value):
                print('Setting {} to {}'.format(key, value), file=sys.stderr)
            setattr(self, key, value)

    def __init__(self, sys_args, log, root, *args):
        # Set the default options.
        option_names = []
        for options in args:
            for option in options:
                option_names.append(option['names'][0])
                key = option['names'][0].replace('-', '')
                if(option['action'] == 'store_true'):
                    value = False
                elif(option['nargs'] != 1):
                    value = []
                else:
                    value = option['default']
                setattr(self, key, value)

        dirPath = os.path.dirname(os.path.realpath(__file__))
        self.setConfig(os.path.join(dirPath, 'config.txt'), root)

        # Figure out command line options changed by user.
        my_list = []
        used_options = []
        setting_inputs = True
        option_list = 'input'
        list_type = str
        i = 0
        group = None
        while i < len(sys_args):
            item = sys_args[i]
            label = 'option' if item.startswith('--') else 'short'

            # Find the option.
            if(label == 'option'):
                option = get_option(item, group='global', the_args=args)
            else:
                option = get_option(item, group=group, the_args=args)
                if(option is None and (group is not None)):
                    group = None # Don't consider the next option to be in a group.
                    option = get_option(item, group=group, the_args=args)

            if(option is None):
                # Unknown Option!
                if(setting_inputs and not item.startswith('-')):
                    # Option is actually an input file, like example.mp4
                    my_list.append(item)
                else:
                    # Get the names of all the options and groups.
                    opt_list = []
                    for options in args:
                        for opt in options:
                            for names in opt['names']:
                                opt_list.append(names)

                    close_matches = difflib.get_close_matches(item, opt_list)

                    if(close_matches):
                        if(close_matches[0] == item):
                            log.error('{} {} needs to be in a group'.format(
                                label.capitalize(), item))
                        else:
                            log.error('Unknown {}: {}\n\n    '\
                                'Did you mean:\n        '.format(label, item)
                                + ', '.join(close_matches))
                    else:
                        log.error('Unknown {}: {}'.format(label, item))
            else:
                # We found the option.
                if(option_list is not None):
                    setattr(self, option_list, list(map(list_type, my_list)))

                setting_inputs = False
                option_list = None
                my_list = []

                if(option['names'][0] in used_options and option['stack'] is None):
                    log.error('Cannot repeat option {} twice.'.format(option['names'][0]))

                used_options.append(option['names'][0])

                key = option['names'][0].replace('-', '')
                if(option['action'] == 'grouping'):
                    group = key

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
                else:
                    try:
                        value = option['type'](nextItem)
                    except Exception:
                        typeName = option['type'].__name__
                        log.error('Couldn\'t convert "{}" to {}'.format(
                            nextItem, typeName))

                    # Handle when the option value is not in choices list.
                    if(option['choices'] is not None and value not in option['choices']):
                        option_name = option['names'][0]
                        my_choices = ', '.join(option['choices'])
                        log.error('{} is not a choice for {}\nchoices are:\n  {}'.format(
                            value, option_name, my_choices))
                    i += 1
                setattr(self, key, value)

            i += 1
        if(setting_inputs):
            setattr(self, option_list, list(map(list_type, my_list)))

        if(self.help):
            print_program_help(root, args)
            sys.exit()
