'''argsCheck.py'''

from usefulFunctions import hex_to_bgr

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
    if(args.constant_rate_factor != 'unset'):
        if(int(args.constant_rate_factor) < 0 or int(args.constant_rate_factor) > 51):
            log.error('Constant rate factor (crf) must be between 0-51.')
    if(args.width < 1):
        log.error('motionOps --width cannot be less than 1.')
    if(args.dilates < 0):
        log.error('motionOps --dilates cannot be less than 0')
