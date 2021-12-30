'''utils/container.py'''

from typing import Any

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
    'vcodecs': ['h264', 'hevc', 'vp9', 'av1', 'mpeg4', 'mpeg2video', 'mjpeg'],
    'acodecs': ['aac', 'mp3', 'opus', 'flac', 'vorbis', 'mp2'],
    'disallow_v': ['prores', 'apng', 'gif', 'msmpeg4v3', 'flv1', 'vp8', 'rawvideo'],
    'disallow_a': pcm_formats,
}
ogg = {
    'allow_video': True,
    'allow_audio': True,
    'allow_subtitle': True,
    'vcodecs': ['libtheora', 'theora'],
    'acodecs': ['libvorbis', 'vorbis', 'flac', 'opus', 'speex'],
    'vstrict': True,
    'astrict': True,
},

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

    'ogg': ogg,
    'ogv': ogg,

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
        'acodecs': ['opus', 'flac', 'libvorbis', 'vorbis', 'speex'],
        'astrict': True,
    },
    'oga': {
        'allow_audio': True,
        'acodecs': ['flac', 'libvorbis', 'vorbis', 'opus', 'speex'],
        'astrict': True,
    },
    'flac': {
        'name': 'Free Lossless Audio Codec',
        'allow_audio': True,
        'max_audio_streams': 1,
        'acodecs': ['flac'],
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
        'vcodecs': ['mpeg4', 'h264', 'prores', 'mjpeg', 'mpeg2video', 'rawvideo'],
        'acodecs': ['mp3', 'aac', 'vorbis', 'mp2'],
        'disallow_v': ['hevc', 'apng', 'gif'],
    },
    'wmv': {
        'name': 'Windows Media Video',
        'allow_video': True,
        'allow_audio': True,
        'vcodecs': ['msmpeg4v3', 'h264', 'mpeg4', 'mpeg2video', 'mjpeg', 'rawvideo'],
        'acodecs': ['wmav2', 'aac', 'flac'],
        'disallow_v': ['prores', 'hevc', 'apng', 'gif'],
    },
    'mkv': {
        'name': 'Matroska',
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['h264', 'hevc', 'vp9', 'vp8', 'prores', 'mpeg4', 'mpeg2video',
            'msmpeg4v3', 'mjpeg', 'gif', 'rawvideo'],
        'acodecs': ['libvorbis', 'vorbis', 'opus', 'flac', 'aac', 'mp2'],
        'disallow_v': ['apng'],
    },
    'mka': {
        'name': 'Matroska Audio',
        'allow_audio': True,
        'acodecs': ['libvorbis', 'vorbis', 'opus', 'flac', 'aac', 'mp2'],
    },
    'mov': {
        'name': 'QuickTime / MOV',
        'allow_video': True,
        'allow_audio': True,
        'allow_subtitle': True,
        'vcodecs': ['h264', 'hevc', 'prores', 'mpeg4', 'mpeg2video', 'msmpeg4v3', 'mjpeg',
            'gif', 'flv1', 'rawvideo'],
        'acodecs': ['aac', 'mp3', 'mp2', 'vorbis'],
        'disallow_a': ['opus', 'flac'],
        'disallow_v': ['apng', 'vp9', 'vp8'],
    },
    'swf': {
        'name': 'ShockWave Flash / Small Web Format',
        'allow_video': True,
        'allow_audio': True,
        'vcodecs': ['flv1', 'mjpeg'],
        'acodecs': ['mp3'],
        'vstrict': True,
        'astrict': True,
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


def get_rules(key: str) -> Any:
    rules: Any = containers['default']
    if(key in containers):
        rules.update(containers[key])
    else:
        rules.update(containers['not_in_here'])
    return rules

if(__name__ == '__main__'):
    import json
    import subprocess

    from auto_editor.ffwrapper import FFmpeg

    with open('../../container.json', 'w') as outfile:
        json.dump(containers, outfile)

    ffmpeg = FFmpeg()

    out = '../../out.opus'
    ffmpeg.run(['-i', '../../example.mp4', '-c:a', 'flac', '-strict', '-2', out])
    subprocess.call(['aeinfo', out])
