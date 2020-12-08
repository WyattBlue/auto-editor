'''vanparse.py'''

import difflib
import sys

def printHelp(option, args):
    print(' ', ', '.join(option['names']))
    if(option['action'] == 'grouping'):
        print('   |')
    else:
        print('   ', option['help'])
        print('   ', option['extra'])
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
                    if(op['action'] == 'grouping'):
                        print('     ...')

    elif(option['action'] == 'store_true'):
        print('    type: flag')
    else:
        print('    type: unknown')


def get_option(item, group, the_args: list):
    for options in the_args:
        for option in options:
            if(item in option['names']):
                if(group == 'global' or option['grouping'] == group):
                    return option
    return None


class ParseOptions():
    def __init__(self, userArgs, log, *args):
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

        # Figure out attributes changed by user.
        myList = []
        settingInputs = True
        optionList = 'input'
        i = 0
        group = 'auto-editor'
        while i < len(userArgs):
            item = userArgs[i]
            if(i == len(userArgs) - 1):
                nextItem = None
            else:
                nextItem = userArgs[i+1]

            option = get_option(item, group, args)

            if(option is None and group != 'auto-editor'):
                group = 'auto-editor'
                option = get_option(item, group, args)

            if(option is None):
                if(settingInputs and not item.startswith('-')):
                    # Input file names
                    myList.append(item)
                else:
                    # Unknown Option!
                    hmm = difflib.get_close_matches(item, option_names)
                    append = ''

                    # If there's an exact match.
                    if(len(hmm) > 0 and hmm[0] == item):
                        option = get_option(item, 'global', args)
                        group = option['grouping']
                        myDefault = option['default'] if option['action'] != 'store_true' else ''
                        append = f'\n\nExample:\n    auto-editor {group} {item} {myDefault}'
                        log.error(f'Option {item} needs to be in group: {group}{append}')

                    potential_options = ', '.join(hmm)

                    if(hmm != []):
                        append = f'\n\n    Did you mean:\n        {potential_options}'
                    log.error(f'Unknown option: {item}{append}')
            else:
                if(optionList is not None):
                    setattr(self, optionList, myList)
                settingInputs = False
                optionList = None
                myList = []

                key = option['names'][0].replace('-', '')

                if(option['action'] == 'grouping'):
                    group = key

                if(nextItem == '-h' or nextItem == '--help'):
                    printHelp(option, args)
                    sys.exit()

                if(option['nargs'] != 1):
                    settingInputs = True
                    optionList = key
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
                    if(option['choices'] is not None):
                        if(value not in option['choices']):
                            optionName = option['names'][0]
                            myChoices = ', '.join(option['choices'])
                            log.error(f'{value} is not a choice for {optionName}' \
                                f'\nchoices are:\n  {myChoices}')
                    i += 1
                setattr(self, key, value)

            i += 1
        if(settingInputs):
            setattr(self, optionList, myList)
