# Contributing

## Making a Great Issue

### Nice formatting

 - For option names, surround them with a single backtick (\`). \`--example\` will be rendered as `--example` 
 - For auto-editor output or tracebacks, surround them with triple backticks. 

\`\`\`
auto-editor --version

Auto-Editor Version: x 
\`\`\`

Will be rendered as:

```
auto-editor --version

Auto-Editor Version: x 
```

### General Tips
 - See what does and doesn't work.  
 - If you're confused what `--option` does. Run `auto-editor --option --help`

## Contributing Code

Fork the main repo and then clone your repo. Replacing `USER` with your actual GitHub username.

```
git clone https://github.com/USER/auto-editor.git
cd auto-editor
```

Then make a new branch and call it something like `patch-1`, `support-for-gif`,  or `fix-typo`

```
git branch patch-1
git checkout patch-1
```

Then open up your favorite text editor and apply your changes.

### Code styling

Auto-Editor uses black to keep the code tidy and consistent. Install black with:
```
pip install black
```

Run black on the root folder. Do this every time you make a change.
```
black auto_editor
```

### Making a Pull Request
Go to https://github.com/WyattBlue/auto-editor/pulls and hit the "New Pull Request" button.

GitHub should autofill in the rest since you've made a fork. Make sure you select the branch you've made and not `master`.
