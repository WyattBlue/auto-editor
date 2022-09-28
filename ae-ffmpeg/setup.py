import re

from setuptools import find_packages, setup


def pip_version():
    with open("ae_ffmpeg/__init__.py") as f:
        version_content = f.read()

    version_match = re.search(
        r"^__version__ = ['\"]([^'\"]*)['\"]", version_content, re.M
    )

    if version_match:
        return version_match.group(1)

    raise ValueError("Unable to find version string.")


with open("README.md") as f:
    long_description = f.read()

setup(
    name="ae-ffmpeg",
    version=pip_version(),
    description="Static FFmpeg binaries for Auto-Editor",
    long_description=long_description,
    long_description_content_type="text/markdown",
    license="LGPLv3",
    url="https://auto-editor.com",
    project_urls={
        "Bug Tracker": "https://github.com/WyattBlue/auto-editor/issues",
        "Source Code": "https://github.com/WyattBlue/auto-editor",
    },
    author="WyattBlue",
    author_email="wyattblue@auto-editor.com",
    keywords="video audio media",
    packages=find_packages(),
    package_data={
        "ae_ffmpeg": [
            "LICENSE.txt",
            "Windows/ffmpeg.exe",
            "Windows/ffprobe.exe",
            "Windows/libopenh264.dll",
            "Darwin-x86_64/ffmpeg",
            "Darwin-x86_64/ffprobe",
            "Darwin-arm64/ffmpeg",
            "Darwin-arm64/ffprobe",
            "py.typed",
        ],
    },
    include_package_data=True,
    zip_safe=False,
    python_requires=">=3.8",
    classifiers=[
        "Topic :: Multimedia :: Sound/Audio",
        "Topic :: Multimedia :: Video",
        "License :: OSI Approved :: GNU Lesser General Public License v3 (LGPLv3)",
        "Intended Audience :: Developers",
        "Operating System :: MacOS :: MacOS X",
        "Operating System :: Microsoft :: Windows",
        "Development Status :: 5 - Production/Stable",
        "Programming Language :: Python :: 3",
    ],
)
