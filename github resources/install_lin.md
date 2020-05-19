# Installing Auto-Editor for Linux
## Python 3
This project is written in python 3. Check if you have it by running this command in the Terminal.
```terminal
python --version
```

If Terminal says this:

```terminal
zsh: command not found: python
```

or this
```terminal
Python 2.7.16
```

you need to install [python 3](https://www.python.org/downloads/).

## Homebrew
Check if you have Homebrew.

```terminal
brew --version
```

If not, then install it by running:

```terminal
- git clone https://github.com/Homebrew/brew ~/.linuxbrew/Homebrew
- mkdir ~/.linuxbrew/bin
- ln -s ~/.linuxbrew/Homebrew/bin/brew ~/.linuxbrew/bin
- eval $(~/.linuxbrew/bin/brew shellenv)
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

Wait for all the libraries to install and once that's done, close and reopen Terminal.

## Running Auto-Editor

If you have git, then you can simply run:
```terminal
git clone https://github.com/WyattBlue/auto-editor.git
```

to download the repo or download the zip version [here.](https://github.com/WyattBlue/auto-editor/archive/master.zip)

Run
```terminal
python auto-editor.py --help
```
to test it and if that runs successfully, then congratulations, you have successfully installed auto-editor. See the usage section for more examples.
