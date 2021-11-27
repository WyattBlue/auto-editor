'''utils/encoder.py'''

encoders = {
    'h264': {
        'pix_fmt': {'videotoolbox_vld', 'nv12', 'yuv420p'},
    },
    'hevc': {
        'pix_fmt': {'yuv420p', 'yuvj420p', 'yuv422p', 'yuvj422p', 'yuv444p', 'yuvj444p',
            'gbrp', 'yuv420p10le', 'yuv422p10le', 'yuv444p10le', 'gbrp10le', 'yuv420p12le',
            'yuv422p12le', 'yuv444p12le', 'gbrp12le', 'gray', 'gray10le', 'gray12le'},
    },
    'vp9': {
        'pix_fmt': {'yuv420p', 'yuva420p', 'yuv422p', 'yuv440p', 'yuv444p', 'yuv420p10le',
            'yuv422p10le', 'yuv440p10le', 'yuv444p10le', 'yuv420p12le', 'yuv422p12le',
            'yuv440p12le', 'yuv444p12le', 'gbrp', 'gbrp10le', 'gbrp12le'},
    },
    'vp8': {
        'pix_fmt': {'yuv420p', 'yuva420p'},
    },
    'prores': {
        'pix_fmt': {'yuv422p10le', 'yuv444p10le', 'yuva444p10le'},
    },
    'av1': {
        'pix_fmt': {'yuv420p', 'yuv422p', 'yuv444p', 'gbrp', 'yuv420p10le', 'yuv422p10le',
            'yuv444p10le', 'yuv420p12le', 'yuv422p12le', 'yuv444p12le', 'gbrp10le',
            'gbrp12le', 'gray', 'gray10le', 'gray12le'},
    },
    'mpeg4': {
        'pix_fmt': {'yuv420p'},
    },
    'mpeg2video': {
        'pix_fmt': {'yuv420p', 'yuv422p'},
    },
    'mjpeg': {
        'pix_fmt': {'yuvj420p', 'yuvj422p', 'yuvj444p'},
    },
}
