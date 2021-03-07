'''vanparse.py'''

import os
import sys
import difflib

def printHelp(args, option):
    if(option['action'] == 'grouping'):
        print(f'  {option["names"][0]}:')
    else:
        print(' ', ', '.join(option['names']))
        print('   ', option['help'])
        if(option['extra'] == ''):
            print('')
        else:
            print(f"\n{option['extra']}\n")
    if(option['action'] == 'default'):
        print('    type:', option['type'].__name__)
        print('    default:', option['default'])
        if(option['range'] is not None):
            print('    range:', option['range'])
        if(option['choices'] is not None):
            print('    choices:', ', '.join(option['choices']))
    elif(option['action'] == 'grouping'):
        for options in args:
            for op in options:
                if(op['grouping'] == option['names'][0]):
                    print(' ', ', '.join(op['names']) + ':', op['help'])
    elif(option['action'] == 'store_true'):
        print('    type: flag')
    else:
        print('    type: unknown')

    if(option['grouping'] is not None):
        print(f'    group: {option["grouping"]}')


def get_option(item: str, group: str, the_args: list) -> str:
    for options in the_args:
        for option in options:
            if(item in option['names']):
                if(group == 'global' or option['grouping'] == group):
                    return option
    return None


class ParseOptions():
    def __init__(self, userArgs, log, root, *args):
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

        # Read the configuration file.
        dirPath = os.path.dirname(os.path.realpath(__file__))
        with open(dirPath + '/config.txt', 'r') as file:
            lines = file.readlines()

        # Set attributes based on the config file to act as the new defaults.
        for item in lines:
            if('#' in item):
                item = item[: item.index('#')]
            item = item.replace(' ', '')
            if(item.strip() == '' or (not item.startswith(root))):
                continue
            value = item[item.index('=')+1 :]

            if(value[0] == "'" and value[-1] == "'"): # detect string value
                value = value[1:-1]
            elif(value == "None"):
                value = None
            elif('.' in value):
                value = float(value)
            else:
                value = int(value)

            key = item[: item.index('=')]
            key = key[key.rfind('.')+1:]
            setattr(self, key, value)

        # Figure out command line options changed by user.
        myList = []
        used_options = []
        settingInputs = True
        optionList = 'input'
        listType = str
        i = 0
        group = None
        while i < len(userArgs):
            item = userArgs[i]
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
                if(settingInputs and not item.startswith('-')):
                    # Option is actually an input file, like example.mp4
                    myList.append(item)
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
                if(optionList is not None):
                    setattr(self, optionList, list(map(listType, myList)))

                settingInputs = False
                optionList = None
                myList = []

                if(option['names'][0] in used_options and option['stack'] is None):
                    log.error(f'Cannot repeat option {option["names"][0]} twice.')

                used_options.append(option['names'][0])

                key = option['names'][0].replace('-', '')
                if(option['action'] == 'grouping'):
                    group = key

                nextItem = None if i == len(userArgs) - 1 else userArgs[i+1]
                if(nextItem == '-h' or nextItem == '--help'):
                    printHelp(args, option)
                    sys.exit()

                if(option['nargs'] != 1):
                    settingInputs = True
                    optionList = key
                    listType = option['type']
                elif(option['action'] == 'store_true'):
                    value = True
                else:
                    try:
                        # Convert to correct type.
                        value = option['type'](nextItem)
                    except Exception as err:
                        typeName = option['type'].__name__
                        log.debug(f'Exact Error: {err}')
                        log.error(f'Couldn\'t convert "{nextItem}" to {typeName}')

                    # Handle when the option value is not in choices list.
                    if(option['choices'] is not None and value not in option['choices']):
                        optionName = option['names'][0]
                        myChoices = ', '.join(option['choices'])
                        log.error(f'{value} is not a choice for {optionName}' \
                            f'\nchoices are:\n  {myChoices}')
                    i += 1
                setattr(self, key, value)

            i += 1
        if(settingInputs):
            setattr(self, optionList, list(map(listType, myList)))

        if(self.help):
            for options in args:
                for op in options:
                    if(op['action'] == 'grouping'):
                        print(f"\n  {op['names'][0]}:")
                    else:
                        print(' ', ', '.join(op['names']) + ':', op['help'])
            print('')
            if(root == 'auto-editor'):
                print('  Have an issue? Make an issue. '\
                    'Visit https://github.com/wyattblue/auto-editor/issues\n')
                print('  The help option can also be used on a specific option:')
                print('      auto-editor --frame_margin --help\n')
            sys.exit()

