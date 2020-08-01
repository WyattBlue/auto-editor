import os
import sys
from setuptools import setup, find_packages

def find_version():
    return '20.31.1.1'


# 'setup.py publish' shortcut.
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
    version=find_version(),
    description='Auto-Editor: Effort free video editing!',
    long_description=long_description,
    long_description_content_type='text/markdown',
    license='MIT',
    url='https://github.com/WyattBlue/auto-editor',
    author='WyattBlue',
    author_email='wyattbluesandbox@gmail.com',
    packages=find_packages(),
    include_package_data=True,
    install_requires=[
        'opencv-python',
        'audiotsm2',
        'youtube-dl',
        'pillow',
        'pydub',
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