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

# Regiao correta a partir do IMDS (IMDSv2): a app le /coffee-shop/* via boto3 e
# precisa apontar para a regiao onde a instancia — e os parametros — estao.
# Sem hardcode: funciona igual em us-east-1, us-east-2 ou qualquer outra.
TOKEN=$(curl -sfX PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 120" 2>/dev/null || true)
REGION=$(curl -sf -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/region 2>/dev/null || true)
if [ -n "$REGION" ]; then
  echo "AWS_DEFAULT_REGION=$REGION" >> /etc/coffee-shop/env
fi

install -m 0644 "$APP_DIR/deploy/systemd/coffee-api.service" /etc/systemd/system/coffee-api.service
systemctl daemon-reload

chown -R coffee:coffee "$APP_DIR"
