#!/bin/bash
# Hook ApplicationStop — roda a partir da revisao ANTERIOR; no primeiro
# deploy o servico ainda nao existe, por isso tudo tolera ausencia.
set -u

systemctl stop coffee-api.service 2>/dev/null || true
systemctl stop coffee-tui.service 2>/dev/null || true
exit 0
