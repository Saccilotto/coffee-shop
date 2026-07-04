#!/usr/bin/env bash
# Cria/atualiza os parametros /coffee-shop/* no SSM Parameter Store.
# Idempotente (--overwrite): pode rodar quantas vezes quiser. Estes
# parametros alimentam api/app/config.py (cache TTL 30s) - a demo do
# Aloysio muda /coffee-shop/motd e ve a API refletir sem restart.
#
#   ./scripts/seed-parameters.sh                 -> valores default
#   ./scripts/seed-parameters.sh --with-api-url  -> tambem grava /coffee-shop/api-url
#                                                   com a URL do environment Beanstalk
set -euo pipefail
export AWS_DEFAULT_REGION=us-east-1

put() {
  local name=$1 value=$2
  aws ssm put-parameter --name "$name" --value "$value" --type String \
    --overwrite >/dev/null
  echo "  $name = $value"
}

echo "==> Gravando parametros /coffee-shop/*"
put /coffee-shop/store-name   "coffee-shop do Grupo 8"
put /coffee-shop/motd         "Bem-vindo! Hoje tem coado do cerrado."
put /coffee-shop/discount-pct "0"

# Tags nao entram no put-parameter --overwrite; aplica em separado.
for p in store-name motd discount-pct; do
  aws ssm add-tags-to-resource --resource-type Parameter \
    --resource-id "/coffee-shop/$p" \
    --tags Key=Project,Value=coffee-shop Key=Team,Value=grupo8 Key=Env,Value=demo
done

if [[ "${1:-}" == "--with-api-url" ]]; then
  URL=$(aws cloudformation describe-stacks --stack-name coffee-shop-04-beanstalk \
    --query "Stacks[0].Outputs[?OutputKey=='EndpointUrl'].OutputValue" --output text)
  if [[ -n "$URL" && "$URL" != "None" ]]; then
    put /coffee-shop/api-url "$URL"
    aws ssm add-tags-to-resource --resource-type Parameter \
      --resource-id /coffee-shop/api-url \
      --tags Key=Project,Value=coffee-shop Key=Team,Value=grupo8 Key=Env,Value=demo
  else
    echo "AVISO: stack coffee-shop-04-beanstalk sem output EndpointUrl - api-url nao gravado" >&2
  fi
fi

echo "==> Estado atual:"
aws ssm get-parameters-by-path --path /coffee-shop --recursive \
  --query 'Parameters[].{Name:Name,Value:Value,Version:Version}' --output table
