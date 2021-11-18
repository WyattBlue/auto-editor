'''utils/container.py'''

pcm_formats = [
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
]

# Define aliases
h265 = {
    'name': 'H.265 / High Efficiency Video Coding (HEVC) / MPEG-H Part 2',
    'allow_video': True,
    'vcodecs': ['hevc', 'mpeg4', 'h264'],
}
h264 = {
    'name': 'H.264 / Advanced Video Coding (AVC) / MPEG-4 Part 10',
    'allow_video': True,
    'vcodecs': ['h264', 'mpeg4', 'hevc'],
}
aac = {
    'name': 'Advanced Audio Coding',
    'allow_audio': True,
    'max_audio_streams': 1,
    'acodecs': ['aac'],
    'astrict': True,
}
ass = {
    'name': 'SubStation Alpha',
    'allow_subtitle': True,
    'scodecs': ['ass', 'ssa'],
    'max_subtitle_streams': 1,
    'sstrict': True,
}
mp4 = {
    'name': 'MP4 / MPEG-4 Part 14',
    'allow_video': True,
    'allow_audio': True,
    'allow_subtitle': True,
    'vcodecs': ['mpeg4', 'h264', 'hevc'],
    'acodecs': ['aac', 'mp3', 'opus'],
    'disallow_v': ['prores', 'apng', 'gif'],
}

containers = {

    # Aliases section

    'aac': aac,
    'adts': aac,
    'ass': ass,
    'ssa': ass,
    '264': h264,
    'h264': h264,
    '265': h265,
    'h265': h265,
    'hevc': h265,

    'mp4': mp4,
    'm4a': mp4,

    'apng': {
        'name': 'Animated Portable Network Graphics',
        'allow_video': True,
        'max_video_streams': 1,
        'vcodecs': ['apng'],
        'vstrict': True,
    },
    'gif': {
        'name': 'Graphics Interchange Format',
        'allow_video': True,
        'max_video_streams': 1,
        'vcodecs': ['gif'],
        'vstrict': True,
    },
    'wav': {
        'name': 'Waveform Audio File Format',
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': pcm_formats + ['mp3'],
        'astrict': True,
    },
    'ast': {
        'name': 'AST / Audio Stream',
        'allow_audio': True,
        'acodecs': ['pcm_s16be_planar'],
    },
    'mp3': {
        'name': 'MP3 / MPEG-2 Audio Layer 3',
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': ['mp3'],
        'astrict': True,
    },
    'opus': {
        'name': 'Opus',
        'allow_audio': True,
    },
    'oga': {
        'allow_audio': True,
    },
    'flac': {
        'name': 'Free Lossless Audio Codec',
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
        'name': 'WebM',
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['vp9', 'vp8', 'av1', 'libaom-av1'],
        'acodecs': ['opus', 'vorbis'],
        'scodecs': ['webvtt'],
        'vstrict': True,
        'astrict': True,
        'sstrict': True,
    },
    'srt': {
        'name': 'SubRip Text / Subtitle Resource Tracks',
        'allow_subtitle': True,
        'scodecs': ['srt'],
        'max_subtitle_streams': 1,
        'sstrict': True,
    },
    'vtt': {
        'name': 'Web Video Text Track',
        'allow_subtitle': True,
        'scodecs': ['webvtt'],
        'max_subtitle_streams': 1,
        'sstrict': True,
    },
    'avi': {
        'name': 'Audio Video Interleave',
        'allow_video': True,
        'allow_audio': True,
        'vcodecs': ['mpeg4'],
        'acodecs': ['mp3'],
    },
    'wmv': {
        'name': 'Windows Media Video',
        'allow_video': True,
        'allow_audio': True,
        'vcodecs': ['msmpeg4v3'],
        'acodecs': ['wmav2', 'flac'],
        'disallow_v': ['prores'],
    },
    'mkv': {
        'name': 'Matroska',
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['h264', 'prores'],
        'acodecs': ['vorbis', 'opus', 'flac', 'aac'],
    },
    'mka': {
        'name': 'Matroska Audio',
        'allow_audio': True,
        'acodecs': ['vorbis', 'opus', 'flac', 'aac'],
    },
    'mov': {
        'name': 'QuickTime / MOV',
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['h264', 'prores', 'hevc'],
        'acodecs': ['aac', 'mp3', 'vorbis'],
        'disallow_a': ['opus', 'flac'],
    },
    'swf': {
        'name': 'ShockWave Flash / Small Web Format',
        'allow_video': True,
        'allow_audio': True,
        'vcodecs': ['flv1'],
        'acodecs': ['mp3'],
        'samplerate': [44100, 22050, 11025],
    },
    'not_in_here': {
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
    },
    'default': {
        'name': None,
        'allow_video': False,
        'allow_audio': False,
        'allow_subtitle': False,
        'max_video_streams': None,
        'max_audio_streams': None,
        'max_subtitle_streams': None,
        'vcodecs': None,
        'acodecs': None,
        'scodecs': None,
        'vstrict': False,
        'astrict': False,
        'sstrict': False,
        'disallow_v': [],
        'disallow_a': [],
        'samplerate': None, # Any samplerate is allowed.
    },
}
