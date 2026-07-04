#!/usr/bin/env bash
# Monta o bundle CodeDeploy (appspec.yml na raiz + api/ + deploy/), sobe para
# o bucket de artefatos e dispara o deployment no grupo coffee-shop-api-iaas.
#
#   ./scripts/package-codedeploy.sh                -> empacota + upload + deploy
#   ./scripts/package-codedeploy.sh --no-upload    -> so monta build/codedeploy/ e o zip
#   BUNDLE_DIR=<dir> ./scripts/package-codedeploy.sh --no-upload
#       (usado por demo-rollback.sh para empacotar uma revisao alterada)
set -euo pipefail

export AWS_DEFAULT_REGION=us-east-1
cd "$(dirname "$0")/.."

NO_UPLOAD=0
[[ "${1:-}" == "--no-upload" ]] && NO_UPLOAD=1

BUNDLE_DIR=${BUNDLE_DIR:-build/codedeploy}
REV=$(git rev-parse --short HEAD 2>/dev/null || date +%s)
LABEL=${BUNDLE_LABEL:-$REV}
ZIP=build/coffee-api-bundle-$LABEL.zip

echo "==> Montando bundle em $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/deploy"
cp deploy/appspec.yml "$BUNDLE_DIR/appspec.yml"
rsync -a --exclude '__pycache__' --exclude 'data' --exclude '.pytest_cache' \
  api "$BUNDLE_DIR/"
rsync -a deploy/scripts deploy/systemd deploy/env "$BUNDLE_DIR/deploy/"
chmod +x "$BUNDLE_DIR"/deploy/scripts/*.sh

mkdir -p build
rm -f "$ZIP"
(cd "$BUNDLE_DIR" && zip -qr "$OLDPWD/$ZIP" .)
echo "==> Bundle: $ZIP ($(du -h "$ZIP" | cut -f1))"

if ((NO_UPLOAD)); then
  echo "(--no-upload: parando aqui)"
  exit 0
fi

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
BUCKET="coffee-shop-artifacts-$ACCOUNT-$AWS_DEFAULT_REGION"
KEY="codedeploy/coffee-api-bundle-$LABEL.zip"

echo "==> Upload para s3://$BUCKET/$KEY"
aws s3 cp "$ZIP" "s3://$BUCKET/$KEY"

echo "==> Criando deployment (application coffee-shop, grupo coffee-shop-api-iaas)"
DEPLOYMENT_ID=$(aws deploy create-deployment \
  --application-name coffee-shop \
  --deployment-group-name coffee-shop-api-iaas \
  --s3-location "bucket=$BUCKET,key=$KEY,bundleType=zip" \
  --file-exists-behavior OVERWRITE \
  --description "coffee-api $LABEL" \
  --query deploymentId --output text)
echo "    deploymentId: $DEPLOYMENT_ID"

echo "==> Aguardando resultado..."
if aws deploy wait deployment-successful --deployment-id "$DEPLOYMENT_ID"; then
  echo "==> Deployment SUCCEEDED"
  IP=$(aws cloudformation describe-stacks --stack-name coffee-shop-02-compute \
    --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue" --output text)
  echo "    API: http://$IP:8000/health"
else
  STATUS=$(aws deploy get-deployment --deployment-id "$DEPLOYMENT_ID" \
    --query 'deploymentInfo.status' --output text)
  echo "==> Deployment terminou como: $STATUS"
  echo "    Detalhes: aws deploy get-deployment --deployment-id $DEPLOYMENT_ID"
  exit 1
fi
