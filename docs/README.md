# Source Code, Documents, and Resources for https://auto-editor.com.

## Requirements
 - BunJS
 - Python
 - Nim
 - rsync and ssh (for deployment)

```
# Install
bun install

# Run local
bun run dev

# Publish
./go.sh
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