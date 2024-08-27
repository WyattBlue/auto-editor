.PHONY: local compile html upload default

default: local

compile:
	nim c -d:danger make
ifeq ($(shell uname),Darwin)
	strip -ur make && du --si -A make
else
	strip make && du -sh make
endif

html:
	rm -rf public
	cp -R src public
	python3 build.py
	./make

local: html
	bun run dev

download:
	rsync -rtvzP "root@auto-editor.com:/var/www/auto-editor/public/img" src

upload:
	rsync -rtvzP --delete ./public "root@auto-editor.com:/var/www/auto-editor/public"
	rsync server.js "root@auto-editor.com:/var/www/auto-editor/server.js"
	rsync package.json "root@auto-editor.com:/var/www/auto-editor/package.json"
	ssh root@auto-editor.com "systemctl restart ae; echo 'done'"
