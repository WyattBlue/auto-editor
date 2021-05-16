'''vanparse.py'''

import os
import sys
import difflib

def out(text: str):
    import re
    import textwrap
    from shutil import get_terminal_size

    indent_regex = re.compile(r'^(\s+)')
    width = get_terminal_size().columns

    wraped_lines = []

    for line in text.split('\n'):
        exist_indent = re.search(indent_regex, line)
        pre_indent = exist_indent.groups()[0] if exist_indent else ''

        wraped_lines.append(
            textwrap.fill(line, width=width, subsequent_indent=pre_indent)
        )

    print('\n'.join(wraped_lines))

def printOptionHelp(args, option):
    text = ''
    if(option['action'] == 'grouping'):
        text += f'  {option["names"][0]}:\n'
    else:
        text += '  ' + ', '.join(option['names']) + '\n    ' + option['help'] + '\n\n'
        if(option['extra'] != ''):
            text += f'\n{option["extra"]}\n\n'

    if(option['action'] == 'default'):
        text += '    type: ' + option['type'].__name__
        text += f'\n    default: {option["default"]}\n'
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

def printProgramHelp(root, the_args: list):
    text = ''
    for options in the_args:
        for option in options:
            if(option['action'] == 'grouping'):
                text += f"\n  {option['names'][0]}:\n"
            else:
                text += '  ' + ', '.join(option['names']) + ': ' + option['help'] + '\n'
    text += '\n'
    if(root == 'auto-editor'):
        text += '  Have an issue? Make an issue. Visit '\
            'https://github.com/wyattblue/auto-editor/issues\n\n  The help option can '\
            'also be used on a specific option:\n      auto-editor --frame_margin '\
            '--help\n'
    out(text)

def getOption(item: str, group: str, the_args: list) -> str:
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
        range=None, choices=None, group=None, stack=None, help='', extra=''):
        newDic = {}
        newDic['names'] = names
        newDic['nargs'] = nargs
        newDic['type'] = type
        newDic['default'] = default
        newDic['action'] = action
        newDic['help'] = help
        newDic['extra'] = extra
        newDic['range'] = range
        newDic['choices'] = choices
        newDic['grouping'] = group
        newDic['stack'] = stack

        self.args.append(newDic)

    def parse_args(self, sys_args, log, root):

        if(sys_args == []):
            out(self.description)
            sys.exit()

        if(sys_args == ['-v'] or sys_args == ['-V']):
            out(f'{self.program_name} version {self.version}\nPlease use --version instead.')
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
            elif(value == "None"):
                value = None
            elif('.' in value):
                value = float(value)
            else:
                value = int(value)

            key = item[: item.index('=')]
            key = key[key.rfind('.')+1:]

            if(getattr(self, key) != value):
                print(f'Setting {key} to {value}', file=sys.stderr)
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
        self.setConfig(dirPath + '/config.txt', root)

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
                option = getOption(item, group='global', the_args=args)
            else:
                option = getOption(item, group=group, the_args=args)
                if(option is None and (group is not None)):
                    group = None # Don't consider the next option to be in a group.
                    option = getOption(item, group=group, the_args=args)

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
                    # Throw an error of some kind.
                    if(close_matches):
                        if(close_matches[0] == item):
                            # Option exists but is not in the right group.
                            log.error(f'{label.capitalize()} {item} needs to be in a group')
                        else:
                            log.error(f'Unknown {label}: {item}\n\n\t' \
                                'Did you mean:\n\t\t' + ', '.join(close_matches))
                    else:
                        log.error(f'Unknown {label}: {item}')
            else:
                # We found the option.
                if(option_list is not None):
                    setattr(self, option_list, list(map(list_type, my_list)))

                setting_inputs = False
                option_list = None
                my_list = []

                if(option['names'][0] in used_options and option['stack'] is None):
                    log.error(f'Cannot repeat option {option["names"][0]} twice.')

                used_options.append(option['names'][0])

                key = option['names'][0].replace('-', '')
                if(option['action'] == 'grouping'):
                    group = key

                nextItem = None if i == len(sys_args) - 1 else sys_args[i+1]
                if(nextItem == '-h' or nextItem == '--help'):
                    printOptionHelp(args, option)
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
                    except Exception as err:
                        typeName = option['type'].__name__
                        log.debug(f'Exact Error: {err}')
                        log.error(f'Couldn\'t convert "{nextItem}" to {typeName}')

                    # Handle when the option value is not in choices list.
                    if(option['choices'] is not None and value not in option['choices']):
                        option_name = option['names'][0]
                        my_choices = ', '.join(option['choices'])
                        log.error(f'{value} is not a choice for {option_name}' \
                            f'\nchoices are:\n  {my_choices}')
                    i += 1
                setattr(self, key, value)

            i += 1
        if(setting_inputs):
            setattr(self, option_list, list(map(list_type, my_list)))

        if(self.help):
            printProgramHelp(root, args)
            sys.exit()
