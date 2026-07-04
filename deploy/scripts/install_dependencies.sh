#!/bin/bash
# Hook AfterInstall — venv + dependencias + unit systemd + env file.
set -euo pipefail

APP_DIR=/opt/coffee-shop
VENV=$APP_DIR/venv

if [[ ! -x $VENV/bin/pip ]]; then
  python3 -m venv "$VENV"
fi
"$VENV/bin/pip" install -q --upgrade pip
"$VENV/bin/pip" install -q -r "$APP_DIR/api/requirements.txt"

mkdir -p "$APP_DIR/api/data" /etc/coffee-shop
install -m 0644 "$APP_DIR/deploy/env/coffee-api.env" /etc/coffee-shop/env
install -m 0644 "$APP_DIR/deploy/systemd/coffee-api.service" /etc/systemd/system/coffee-api.service
systemctl daemon-reload

chown -R coffee:coffee "$APP_DIR"
