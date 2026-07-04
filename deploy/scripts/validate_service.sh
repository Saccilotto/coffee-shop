#!/bin/bash
# Hook ValidateService — /health precisa responder 200 em ate ~60s.
# Falha aqui => deployment Failed => rollback automatico para a revisao
# anterior (AutoRollbackConfiguration do deployment group). E exatamente
# este hook que a demo de rollback derruba com COFFEE_FORCE_UNHEALTHY=1.
set -u

URL=http://localhost:8000/health
for attempt in $(seq 1 12); do
  status=$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$URL" || echo 000)
  echo "tentativa $attempt/12: HTTP $status"
  if [[ "$status" == "200" ]]; then
    echo "ValidateService OK"
    exit 0
  fi
  sleep 5
done

echo "ValidateService FALHOU: $URL nao respondeu 200"
systemctl status coffee-api.service --no-pager || true
exit 1
