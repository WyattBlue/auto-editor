'''setup.py'''

import os
import re
import sys
from setuptools import setup, find_packages

def pip_version():
    with open(os.path.abspath('auto_editor/__init__.py')) as f:
        version_content = f.read()

    version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]",
        version_content, re.M)

    if(version_match):
        return version_match.group(1).replace('dev', '')

    raise ValueError('Unable to find version string.')


def replace_version():
    with open(os.path.abspath('auto_editor/__init__.py')) as f:
        version_content = f.read()

    import datetime
    year, week_num, _ = datetime.date.today().isocalendar()
    year = str(year - 2000)

    version_match = re.search(r"^__version__ = ['\"]([^'\"]*)['\"]",
        version_content, re.M)

    informal_match = re.search(r"version = ['\"]([^'\"]*)['\"]",
        version_content, re.M)

    my_version = version_match.group(1)
    informal_version = informal_match.group(1)

    if(not my_version.startswith('{}.{}.'.format(year, week_num))):
        raise ValueError('Pip version with wrong date.')

    if(not informal_version.startswith('{}w{}'.format(year, week_num))):
        raise ValueError('Informal version wrong date.')

    version_content = version_content.replace('-dev', '').replace('dev', '')

    with open(os.path.abspath('auto_editor/__init__.py'), 'w') as f:
        f.write(version_content)


if(sys.argv[-1] == 'replace_version'):
    replace_version()

if(sys.argv[-1] == 'publish'):

    from shutil import rmtree
    rmtree('build')
    rmtree('dist')

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
    author_email='wyattblue@auto-editor.com',
    keywords='video audio media editor editing processing nonlinear automatic ' \
     'silence-detect silence-removal silence-speedup motion-detection',
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'numpy',
        'audiotsm2~=0.2.1',
        'opencv-python>=4.3',
        'youtube-dl',
        'av>=6.0.0',
    ],
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
        'Programming Language :: Python :: 3.6',
        'Programming Language :: Python :: 3.7',
        'Programming Language :: Python :: 3.8',
        'Programming Language :: Python :: 3.9',
        'Programming Language :: Python :: 3.10',
        'Programming Language :: Python :: Implementation :: CPython',
        'Programming Language :: Python :: Implementation :: PyPy',
        'Programming Language :: Python :: Implementation :: IronPython',
        'Programming Language :: Python :: Implementation :: Jython',
    ],
    entry_points={
        "console_scripts": ["auto-editor=auto_editor.__main__:main"]
    }
)
