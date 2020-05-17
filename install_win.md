# Installing Auto-Editor for Windows
## Python 3
This project is written in python 3. Check if you have it by running this command in Command Prompt.
```terminal
python --version
```

If Command Prompt says this:

```terminal
command not found: python
```

or this
```terminal
Python 2.7.16
```

you need to install [python3](https://www.python.org/downloads/).

## Choco
Check if you have Choco

```terminal
choco --version
```

If not, then install it by running:

```terminal
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install.sh)"
```

## Dependencies
To install all of the needed dependencies, run this:
```terminal
brew update
brew install ffmpeg
brew install youtube-dl
pip3 install scipy audiotsm pillow
```
> This ususally takes about 5 minutes.

Wait for all the libraries to install and once that's done, close and reopen Command Prompt

## Running Auto-Editor

If you have git, then you can simply run:
```terminal
git clone https://github.com/WyattBlue/auto-editor.git
```

to download the repo or download it [here.](https://github.com/WyattBlue/auto-editor/archive/master.zip)

Run 
```terminal
python auto-editor.py --help
```
to test it and if that runs successfully, then congratulations, you have successfully installed auto-editor. See the usage section for more examples.
