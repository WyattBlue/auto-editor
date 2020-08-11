import os
import sys
from setuptools import setup, find_packages

def find_version():
    return '20.33.1.0'


def changes():
    text = '''
    * Added `--video_bitrate` which allows you to change the video size when you use
    video codec like h264.'
    * Exporting to premiere shows more useful information.
    * `--clear_cache` has been removed.
    * `--sample_rate` has been moved to size options.
    '''

    text = text.replace('\n', '')
    text = text.replace('    ', '')
    text = text.replace('*', '\n*')
    return text

def numToNormal(text):
    import string
    alphabet = list(string.ascii_lowercase)
    nums = text.split('.')
    return nums[0] + 'w' + nums[1] + alphabet[int(nums[2]) - 1]

# 'setup.py publish' shortcut.
if(sys.argv[-1] == 'publish'):
    vr = numToNormal(find_version()) # proper version for docs

    with open('README.md', 'r') as file:
        readMeContent = file.read()

    lines = readMeContent.split('\n')
    newDoc = ''
    for line in lines:
        if(line.startswith('<img src="https://img.shields.io/badge/version-')):
            newDoc += '<img src="https://img.shields.io/badge/version-' + vr + '-blue.svg">\n'
            continue
        if(line.startswith('## New in ')):
            newDoc += '## New in ' + vr + changes() + '\n'
            continue
        if(not line.startswith('* ')):
            newDoc += line + '\n'

    newDoc = newDoc.rstrip('\n')

    with open('README.md', 'w') as file:
        file.write(newDoc)

    # os.system('rm -rf build')
    # os.system('rm -rf dist')
    # os.system('python3 setup.py sdist bdist_wheel')
    # os.system('twine upload dist/*')

    sys.exit()

with open('README.md', 'r') as f:
    long_description = f.read()

setup(
    name='auto-editor',
    version=find_version(),
    description='Auto-Editor: Effort free video editing!',
    long_description=long_description,
    long_description_content_type='text/markdown',
    license='MIT',
    url='https://github.com/WyattBlue/auto-editor',
    author='WyattBlue',
    author_email='wyattbluesandbox@gmail.com',
    keywords='video editing editor audio processing nonlinear',
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'audiotsm2',
        'opencv-python',
        'youtube-dl',
    ],
    classifiers=[
        'Topic :: Multimedia :: Video',
        'License :: OSI Approved :: MIT License',
        'Environment :: Console',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: Implementation :: CPython',
        'Programming Language :: Python :: Implementation :: PyPy',
        'Programming Language :: Python :: Implementation :: IronPython',
        'Programming Language :: Python :: Implementation :: Jython',
    ],
    entry_points={
        "console_scripts": ["auto-editor=auto_editor.__main__:main"]
    }
)