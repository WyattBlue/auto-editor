'''utils/container.py'''

wav_formats = [
    'pcm_s16le', # default format

    'pcm_alaw',
    'pcm_f32be',
    'pcm_f32le',
    'pcm_f64be',
    'pcm_f64le',
    'pcm_mulaw',
    'pcm_s16be',
    'pcm_s24be',
    'pcm_s24le',
    'pcm_s32be',
    'pcm_s32le',
    'pcm_s8',
    'pcm_u16be',
    'pcm_u16le',
    'pcm_u24be',
    'pcm_u24le',
    'pcm_u32be',
    'pcm_u32le',
    'pcm_u8',
    'pcm_vidc',

    'mp3',
]

containers = {
    'gif': {
        'allow_video': True,
        'max_video_streams': 1,
        'vcodecs': ['gif'],
    },
    'aac': {
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': ['aac'],
    },
    'adts': {
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': ['aac'],
    },
    'wav': {
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': wav_formats,
    },
    'mp3': {
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': ['mp3'],
    },
    'opus': {
        'allow_audio': True,
    },
    'oga': {
        'allow_audio': True,
    },
    'flac': {
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': ['flac'],
    },
    'ogg': {
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['theora'],
        'acodecs': ['opus', 'flac', 'vorbis'],
    },
    'ogv': {
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['theora'],
        'acodecs': ['opus', 'vorbis'],
    },
    'webm': {
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['vp9', 'vp8', 'av1', 'libaom-av1'],
        'acodecs': ['opus', 'vorbis'],
    },
    'h264': {
        'allow_video': True,
    },
    'not_in_here': {
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
    },
    'default': {
        'allow_video': False,
        'allow_audio': False,
        'allow_subtitle': False,
        'max_video_streams': None,
        'max_audio_streams': None,
        'vcodecs': None,
        'acodecs': None,
    },
}

# Any container not listed is assumed to accept anything.
