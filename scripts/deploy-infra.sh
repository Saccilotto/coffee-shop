#!/usr/bin/env bash
# Cria/atualiza as stacks CloudFormation do coffee-shop, na ordem.
#
#   ./scripts/deploy-infra.sh                  -> 01-network, 02-compute, 03-cicd
#   ./scripts/deploy-infra.sh --with-beanstalk -> as tres acima + 04-beanstalk
#
# ATENCAO: cria recursos PAGOS (EC2; com --with-beanstalk tambem ALB + ASG).
# Finalize toda sessao com ./scripts/teardown.sh.
set -euo pipefail

export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")/.."

CFN_DIR=infra/cloudformation
PARAMS_FILE=$CFN_DIR/parameters/demo.json
TAGS=(Project=coffee-shop Team=grupo8 Env=demo)
STACK_PREFIX=coffee-shop

WITH_BEANSTALK=0
[[ "${1:-}" == "--with-beanstalk" ]] && WITH_BEANSTALK=1

# Le os parametros de uma stack em demo.json como lista Key=Value
params_for() {
  jq -r --arg s "$1" '.[$s] // {} | to_entries[] | "\(.key)=\(.value)"' "$PARAMS_FILE"
}

deploy_stack() {
  local name=$1 template=$2; shift 2
  local overrides=("$@")
  echo "==> Stack $STACK_PREFIX-$name"
  local args=(
    cloudformation deploy
    --stack-name "$STACK_PREFIX-$name"
    --template-file "$CFN_DIR/$name.yaml"
    --tags "${TAGS[@]}"
    --capabilities CAPABILITY_IAM
    --no-fail-on-empty-changeset
  )
  mapfile -t file_params < <(params_for "$name")
  local all_params=("${file_params[@]}" "${overrides[@]}")
  # Remove entradas vazias (ex.: KeyName="")
  local clean=()
  for p in "${all_params[@]}"; do
    [[ "$p" == *=  || -z "$p" ]] && continue
    clean+=("$p")
  done
  ((${#clean[@]})) && args+=(--parameter-overrides "${clean[@]}")
  aws "${args[@]}"
}

deploy_stack 01-network
deploy_stack 02-compute
deploy_stack 03-cicd

if ((WITH_BEANSTALK)); then
  echo "==> Preparando 04-beanstalk (ALB cobra por hora - lembre do teardown)"
  SOLUTION_STACK=$(./scripts/resolve-solution-stack.sh)
  echo "    SolutionStackName: $SOLUTION_STACK"

  BUCKET="coffee-shop-artifacts-$(aws sts get-caller-identity --query Account --output text)-$AWS_DEFAULT_REGION"
  VERSION_LABEL="v-$(date +%Y%m%d%H%M%S)"
  EB_KEY="beanstalk/coffee-api-$VERSION_LABEL.zip"

  echo "==> Publicando bundle da app ($EB_KEY)"
  rm -rf build/eb && mkdir -p build/eb
  (cd api && zip -qr ../build/eb/coffee-api.zip app Procfile requirements.txt -x 'app/__pycache__/*')
  aws s3 cp build/eb/coffee-api.zip "s3://$BUCKET/$EB_KEY"

  deploy_stack 04-beanstalk \
    "SolutionStackName=$SOLUTION_STACK" \
    "ArtifactBucket=$BUCKET" \
    "ArtifactKey=$EB_KEY" \
    "VersionLabel=$VERSION_LABEL"

  aws cloudformation describe-stacks --stack-name "$STACK_PREFIX-04-beanstalk" \
    --query 'Stacks[0].Outputs' --output table
fi

echo
echo "==> Outputs da 02-compute:"
aws cloudformation describe-stacks --stack-name "$STACK_PREFIX-02-compute" \
  --query 'Stacks[0].Outputs' --output table
echo "Pronto. Proximos passos: make seed-params && make deploy-api-iaas"
