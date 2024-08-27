#!/usr/bin/env zsh

rsync -rtvzP --delete ./src "root@auto-editor.com:/var/www/auto-editor/src"
rsync -rtvzP --delete ./public "root@auto-editor.com:/var/www/auto-editor/public"
rsync -rtvzP --exclude '.*' ./ "root@auto-editor.com:/var/www/auto-editor"
ssh root@auto-editor.com "systemctl restart ae; echo 'done'"
