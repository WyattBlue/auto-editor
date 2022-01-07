'''setup.py'''

import re
from setuptools import setup, find_packages

def pip_version():
    with open('auto_editor/__init__.py') as f:
        version_content = f.read()

    version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]",
        version_content, re.M)

    if(version_match):
        return version_match.group(1)

    raise ValueError('Unable to find version string.')

with open('README.md', 'r') as f:
    long_description = f.read()

setup(
    name='auto-editor',
    version=pip_version(),
    description='Auto-Editor: Effort free video editing!',
    long_description=long_description,
    long_description_content_type='text/markdown',
    license='Unlicense',
    url='https://auto-editor.com',
    project_urls={
        'Bug Tracker': 'https://github.com/WyattBlue/auto-editor/issues',
        'Source Code': 'https://github.com/WyattBlue/auto-editor',
    },
    author='WyattBlue',
    author_email='wyattblue@auto-editor.com',
    keywords='video audio media editor editing processing nonlinear automatic '
     'silence-detect silence-removal silence-speedup motion-detection',
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'numpy>=1.21.0',
        'yt-dlp>=2021.12.27',
        'pillow>=8.4.0',
        'av>=8.1.0',
        'opencv-python>=4.5.5.62',
    ],
    python_requires='>=3.7,<3.12',
    classifiers=[
        'Topic :: Multimedia :: Sound/Audio',
        'Topic :: Multimedia :: Video',
        'License :: Public Domain',
        'License :: OSI Approved :: The Unlicense (Unlicense)',
        'Environment :: Console',
        'Natural Language :: English',
        'Intended Audience :: End Users/Desktop',
        'Development Status :: 5 - Production/Stable',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3 :: Only',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: Implementation :: CPython',
        'Programming Language :: Python :: Implementation :: PyPy',
    ],
    entry_points={
        "console_scripts": [
            "auto-editor=auto_editor.__main__:main",
            "aecreate=auto_editor.subcommands.create:main",
            "aedesc=auto_editor.subcommands.desc:main",
            "aeinfo=auto_editor.subcommands.info:main",
            "aesubdump=auto_editor.subcommands.subdump:main",
            "aegrep=auto_editor.subcommands.grep:main",
            "aelevels=auto_editor.subcommands.levels:main",
        ]
    }
)
