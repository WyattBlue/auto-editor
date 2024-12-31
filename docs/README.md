# Source Code, Documents, and Resources for https://auto-editor.com.

## Requirements
 - BunJS
 - Python
 - Nim
 - rsync and ssh (for deployment)

```
# Compile Nim, get resources
make compile

# Run local
python build.py 
make

# Publish
make upload
```

## Server Requirements
 - systemd
 - reverse proxy (nginx, etc)
 - BunJS

## Deployment Example

file `/etc/systemd/system/ae.service`

```
[Unit]
Description=AutoEditor Website
After=network.target

[Service]
User=root
WorkingDirectory=/var/www/auto-editor
ExecStart=/root/.bun/bin/bun run server.js

[Install]
WantedBy=multi-user.target
```
