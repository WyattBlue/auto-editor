.PHONY: html upload default

default: html

SRC_FILES := $(shell find src -type f)

html: $(SRC_FILES)
	hunim

download:
	rsync -rtvzP "root@auto-editor.com:/var/www/auto-editor/public/img" src

upload: html
	rsync -rtvzP --delete ./public "root@auto-editor.com:/var/www/auto-editor"
	rsync server.js "root@auto-editor.com:/var/www/auto-editor/server.js"
	rsync package.json "root@auto-editor.com:/var/www/auto-editor/package.json"
	ssh root@auto-editor.com "systemctl restart ae; echo 'done'"
