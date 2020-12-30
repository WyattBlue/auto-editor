'''setup.py'''

"""
This code should only be executed by developers, not users.

The purose of this script is to create the build for pip.
"""

import os
import sys
from setuptools import setup, find_packages

def pip_version():
    # pip doesn't allow standard version format (20w10a), so we have to
    # conform it to match Semantic Versioning.
    return '20.53.1'

if(sys.argv[-1] == 'publish'):
    os.system('rm -rf build')
    os.system('rm -rf dist')
    os.system('python3 setup.py sdist bdist_wheel')
    os.system('twine upload dist/*')
    sys.exit()

with open('README.md', 'r') as f:
    long_description = f.read()

setup(
    name='auto-editor',
    version=pip_version(),
    description='Auto-Editor: Effort free video editing!',
    long_description=long_description,
    long_description_content_type='text/markdown',
    license='Unlicense',
    url='https://github.com/WyattBlue/auto-editor',
    author='WyattBlue',
    author_email='wyattbluesandbox@gmail.com',
    keywords='video audio media editor editing processing nonlinear automatic ' \
     'silence-detect silence-removal silence-speedup motion-detection',
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'numpy==1.19.3',
        'audiotsm2',
        'opencv-python',
        'youtube-dl',
        'requests',
    ],
    classifiers=[
        'Topic :: Multimedia :: Video',
        'License :: Public Domain',
        'License :: OSI Approved :: The Unlicense (Unlicense)',
        'Environment :: Console',
        'Natural Language :: English',
        'Development Status :: 5 - Production/Stable',
        'Programming Language :: Python',
        'Programming Language :: Python :: 3',
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: Implementation :: CPython',
        'Programming Language :: Python :: Implementation :: PyPy',
        'Programming Language :: Python :: Implementation :: IronPython',
        'Programming Language :: Python :: Implementation :: Jython',
    ],
    entry_points={
        "console_scripts": ["auto-editor=auto_editor.__main__:main"]
    }
)