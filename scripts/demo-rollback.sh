#!/usr/bin/env bash
# Demo de rollback automatico do CodeDeploy (bloco do Davi):
#   1. empacota uma revisao IDENTICA a atual, exceto COFFEE_FORCE_UNHEALTHY=1
#      no env file -> /health passa a responder 503;
#   2. o hook ValidateService falha apos ~60s de tentativas;
#   3. o deployment fica Failed e o deployment group redeploya sozinho a
#      revisao anterior (AutoRollbackConfiguration);
#   4. o script mostra o rollback acontecendo e o /health voltando a 200.
set -euo pipefail

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"
cd "$(dirname "$0")/.."

BUNDLE_DIR=build/codedeploy-broken
export BUNDLE_DIR BUNDLE_LABEL=broken-$(date +%H%M%S)

echo "==> Montando revisao QUEBRADA (COFFEE_FORCE_UNHEALTHY=1)"
./scripts/package-codedeploy.sh --no-upload
echo "COFFEE_FORCE_UNHEALTHY=1" >> "$BUNDLE_DIR/deploy/env/coffee-api.env"
ZIP=build/coffee-api-bundle-$BUNDLE_LABEL.zip
rm -f "$ZIP"
(cd "$BUNDLE_DIR" && zip -qr "$OLDPWD/$ZIP" .)

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="coffee-shop-artifacts-$ACCOUNT-$AWS_DEFAULT_REGION"
KEY="codedeploy/coffee-api-bundle-$BUNDLE_LABEL.zip"
aws s3 cp "$ZIP" "s3://$BUCKET/$KEY"

echo "==> Disparando deployment da revisao quebrada"
DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name coffee-shop \
  --deployment-group-name coffee-shop-api-iaas \
  --s3-location "bucket=$BUCKET,key=$KEY,bundleType=zip" \
  --file-exists-behavior OVERWRITE \
  --description "demo rollback: revisao quebrada de proposito" \
  --query deploymentId --output text)
echo "    deploymentId: $DEPLOYMENT_ID"
echo "    Acompanhe na console: CodeDeploy > Deployments > $DEPLOYMENT_ID"

echo "==> Aguardando o ValidateService falhar (~1-2 min)..."
if aws deploy wait deployment-successful --deployment-id "$DEPLOYMENT_ID" 2>/dev/null; then
  echo "ERRO: o deployment quebrado foi aceito - a demo nao deveria chegar aqui."
  exit 1
fi
echo "==> Deployment FALHOU como esperado. Info do rollback:"
aws deploy get-deployment --deployment-id "$DEPLOYMENT_ID" \
  --query 'deploymentInfo.{status:status, erro:errorInformation.message, rollback:rollbackInfo}' \
  --output json

echo "==> Aguardando o deployment de rollback concluir..."
ROLLBACK_ID=$(aws deploy get-deployment --deployment-id "$DEPLOYMENT_ID" \
  --query 'deploymentInfo.rollbackInfo.rollbackDeploymentId' --output text)
if [[ -n "$ROLLBACK_ID" && "$ROLLBACK_ID" != "None" ]]; then
  aws deploy wait deployment-successful --deployment-id "$ROLLBACK_ID"
  echo "    rollback $ROLLBACK_ID: SUCCEEDED"
fi

IP=$(aws cloudformation describe-stacks --stack-name coffee-shop-02-compute \
  --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue" --output text)
echo "==> Prova final - /health de volta ao ar:"
curl -s "http://$IP:8000/health" && echo
