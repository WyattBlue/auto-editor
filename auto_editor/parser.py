import difflib

class parse_options():
    def __init__(self, userArgs, log, *args):
        # Set the default options.
        for options in args:
            for option in options:
                key = option['names'][0].replace('-', '')
                if(option['action'] == 'store_true'):
                    value = False
                elif(option['nargs'] != 1):
                    value = []
                else:
                    value = option['default']
                setattr(self, key, value)

        def get_option(item, the_args: list):
            for options in the_args:
                for option in options:
                    if(item in option['names']):
                        return option
            return None

        # Figure out attributes changed by user.
        myList = []
        settingInputs = True
        optionList = 'input'
        i = 0
        while i < len(userArgs):
            item = userArgs[i]
            if(i == len(userArgs) - 1):
                nextItem = None
            else:
                nextItem = userArgs[i+1]

            option = get_option(item, args)

            if(option is not None):
                if(optionList is not None):
                    setattr(self, optionList, myList)
                settingInputs = False
                optionList = None
                myList = []

                key = option['names'][0].replace('-', '')

                # Show help for specific option.
                if(nextItem == '-h' or nextItem == '--help'):
                    print(' ', ', '.join(option['names']))
                    print('   ', option['help'])
                    print('   ', option['extra'])
                    if(option['action'] == 'default'):
                        print('    type:', option['type'].__name__)
                        print('    default:', option['default'])
                        if(option['range'] is not None):
                            print('    range:', option['range'])
                        if(option['choices'] is not None):
                            print('    choices:', ', '.join(option['choices']))
                    else:
                        print('    type: flag')
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
                        log.error(f'Couldn\'t convert "{nextItem}" to {typeName}')
                        log.debug(f'Exact Error: {err}')
                    if(option['choices'] is not None):
                        if(value not in option['choices']):
                            optionName = option['names'][0]
                            myChoices = ', '.join(option['choices'])
                            log.error(f'{value} is not a choice for {optionName}' \
                                f'\nchoices are:\n  {myChoices}')
                    i += 1
                setattr(self, key, value)
            else:
                if(settingInputs and not item.startswith('-')):
                    # Input file names
                    myList.append(item)
                else:
                    # Unknown Option!
                    hmm = difflib.get_close_matches(item, option_names)
                    potential_options = ', '.join(hmm)
                    append = ''
                    if(hmm != []):
                        append = f'\n\n    Did you mean:\n        {potential_options}'
                    log.error(f'Unknown option: {item}{append}')
            i += 1
        if(settingInputs):
            setattr(self, optionList, myList)