#!/usr/bin/env bash
# Destroi TODA a infra AWS do coffee-shop, em ordem reversa:
# 04-beanstalk -> (esvazia bucket) -> 03-cicd -> 02-compute -> 01-network,
# e apaga os parametros /coffee-shop/* do SSM.
#
# Rode ao fim de TODA sessao de trabalho/ensaio. Recursos esquecidos de um
# dia para o outro custam dinheiro real (docs/CUSTOS_E_TEARDOWN.md).
set -euo pipefail

export AWS_DEFAULT_REGION=us-east-1
STACK_PREFIX=coffee-shop

if [[ "${1:-}" != "--yes" ]]; then
  read -r -p "Isso DESTROI todas as stacks $STACK_PREFIX-* em $AWS_DEFAULT_REGION. Continuar? [digite 'sim'] " ok
  [[ "$ok" == "sim" ]] || { echo "Abortado."; exit 1; }
fi

stack_exists() {
  aws cloudformation describe-stacks --stack-name "$1" >/dev/null 2>&1
}

delete_stack() {
  local name="$STACK_PREFIX-$1"
  if stack_exists "$name"; then
    echo "==> Deletando stack $name"
    aws cloudformation delete-stack --stack-name "$name"
    aws cloudformation wait stack-delete-complete --stack-name "$name"
    echo "    OK"
  else
    echo "==> Stack $name nao existe, pulando"
  fi
}

empty_bucket() {
  local bucket=$1
  aws s3api head-bucket --bucket "$bucket" 2>/dev/null || { echo "==> Bucket $bucket nao existe, pulando"; return 0; }
  echo "==> Esvaziando bucket $bucket (todas as versoes)"
  while : ; do
    local batch
    batch=$(aws s3api list-object-versions --bucket "$bucket" --max-keys 500 --output json |
      jq '{Objects: ([.Versions[]?, .DeleteMarkers[]?] | map({Key: .Key, VersionId: .VersionId})), Quiet: true}')
    [[ $(echo "$batch" | jq '.Objects | length') -eq 0 ]] && break
    aws s3api delete-objects --bucket "$bucket" --delete "$batch" >/dev/null
  done
  echo "    vazio"
}

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="coffee-shop-artifacts-$ACCOUNT-$AWS_DEFAULT_REGION"

delete_stack 04-beanstalk
empty_bucket "$BUCKET"
delete_stack 03-cicd
delete_stack 02-compute
delete_stack 01-network

echo "==> Removendo parametros /coffee-shop/* do SSM"
PARAMS=$(aws ssm get-parameters-by-path --path /coffee-shop --recursive \
  --query 'Parameters[].Name' --output text 2>/dev/null || true)
if [[ -n "${PARAMS// }" ]]; then
  # delete-parameters aceita ate 10 nomes por chamada
  echo "$PARAMS" | tr '\t' '\n' | xargs -n 10 aws ssm delete-parameters --names
  echo "    removidos: $PARAMS"
else
  echo "    nenhum parametro encontrado"
fi

echo
echo "==> Verificacao final (stacks remanescentes com prefixo $STACK_PREFIX):"
aws cloudformation list-stacks \
  --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE ROLLBACK_COMPLETE UPDATE_ROLLBACK_COMPLETE DELETE_FAILED \
  --query "StackSummaries[?starts_with(StackName, '$STACK_PREFIX')].{Name:StackName,Status:StackStatus}" \
  --output table
echo "Teardown concluido. Repo CodeCommit (se criado) NAO e apagado por este script:"
echo "  aws codecommit delete-repository --repository-name coffee-shop"
