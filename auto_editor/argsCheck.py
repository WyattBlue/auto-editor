'''argsCheck.py'''

def hardArgsCheck(args, log):
    if(args.input == []):
        log.error('You need to give auto-editor an input file or folder so it can' \
            'do the work for you.')

    if([args.export_to_premiere, args.export_to_resolve,
        args.export_to_final_cut_pro, args.export_as_audio].count(True) > 1):
        log.error('You must choose only one export option.')

    if(args.export_to_resolve or args.export_to_premiere or args.export_to_final_cut_pro):
        if(args.video_codec != 'uncompressed' or args.constant_rate_factor != 15 or
            args.tune != 'none' or args.sample_rate is not None or
            args.audio_bitrate is not None or args.video_bitrate is not None):
                log.warning('exportMediaOps options are not used when exporting ' \
                    ' as an XML.')

    if(isinstance(args.frame_margin, str)):
        try:
            if(float(args.frame_margin) < 0):
                log.error('Frame margin cannot be negative.')
        except ValueError:
            log.error(f'Frame margin {args.frame_margin}, is not valid.')
    elif(args.frame_margin < 0):
        log.error('Frame margin cannot be negative.')
    if(args.constant_rate_factor < 0 or args.constant_rate_factor > 51):
        log.error('Constant rate factor (crf) must be between 0-51.')
    if(args.width < 1):
        log.error('motionOps --width cannot be less than 1.')
    if(args.dilates < 0):
        log.error('motionOps --dilates cannot be less than 0')
    if(args.video_codec == 'uncompressed'):
        if(args.constant_rate_factor != 15): # default value.
            log.error('Cannot apply constant rate factor if video codec is "uncompressed".')
        if(args.tune != 'none'):
            log.error('Cannot apply tune if video codec is "uncompressed".')
        if(args.preset != 'medium'):
            log.error('Cannot apply preset if video codec is "uncompressed".')

    if(not args.preview):
        if(args.export_to_premiere):
            log.conwrite('Exporting to Adobe Premiere Pro XML file.')
        elif(args.export_to_resolve):
            log.conwrite('Exporting to Final Cut Pro XML file.')
        elif(args.export_to_resolve):
            log.conwrite('Exporting to DaVinci Resolve XML file.')
        elif(args.export_as_audio):
            log.conwrite('Exporting as audio.')
        else:
            log.conwrite('Starting.')

# Quietly modify values without throwing error.
def softArgsCheck(args, log):
    if(args.preview or args.export_to_premiere or args.export_to_resolve or
        args.export_to_final_cut_pro or args.export_as_json):
        args.no_open = True
    args.constant_rate_factor = str(args.constant_rate_factor)
    if(args.blur < 0):
        args.blur = 0
    if(args.silent_speed <= 0 or args.silent_speed > 99999):
        args.silent_speed = 99999
    if(args.video_speed <= 0 or args.video_speed > 99999):
        args.video_speed = 99999
    if(args.output_file is None):
        args.output_file = []
    return args
