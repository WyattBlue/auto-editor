.PHONY: local compile html upload default

default: local

SRC_FILES := $(shell find src -type f)

compile:
	nim c -d:danger make
ifeq ($(shell uname),Darwin)
	strip -ur make && du --si -A make
else
	strip make && du -sh make
endif

html: $(SRC_FILES)
	rm -rf public
	cp -R src public
	python3 build.py
	./make

htmldev: $(SRC_FILES)
	rm -rf public
	cp -R src public
	python3 build.py
	./make --dev

local: html
	bun run dev

download:
	rsync -rtvzP "root@auto-editor.com:/var/www/auto-editor/public/img" src

upload: html
	rsync -rtvzP --delete ./public "root@auto-editor.com:/var/www/auto-editor"
	rsync server.js "root@auto-editor.com:/var/www/auto-editor/server.js"
	rsync package.json "root@auto-editor.com:/var/www/auto-editor/package.json"
	ssh root@auto-editor.com "systemctl restart ae; echo 'done'"
