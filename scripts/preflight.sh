#!/usr/bin/env bash
# Preflight READ-ONLY: valida se a credencial atual consegue subir a PoC numa
# conta nova (usuario IAM). Nao cria, nao altera e nao apaga nada. Rode antes
# de `make deploy-infra` para nao descobrir falta de permissao no meio do deploy.
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

FAIL=0; WARN=0
ok()   { printf '  \033[32mOK\033[0m    %s\n' "$1"; }
warn() { printf '  \033[33mAVISO\033[0m %s\n' "$1"; WARN=$((WARN+1)); }
bad()  { printf '  \033[31mFALHA\033[0m %s\n' "$1"; FAIL=$((FAIL+1)); }

check() { # <descricao> <comando de leitura...>
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$desc"; else bad "$desc"; fi
}

echo "== Identidade e regiao =="
if ID=$(aws sts get-caller-identity --output json 2>/dev/null); then
  ARN=$(echo "$ID" | jq -r .Arn)
  ACC=$(echo "$ID" | jq -r .Account)
  ok "credenciais validas"
  echo "        principal: $ARN"
  echo "        conta $ACC | regiao $AWS_DEFAULT_REGION"
  echo "$ARN" | grep -q ':root' && warn "principal e ROOT; prefira um usuario IAM"
else
  bad "aws sts get-caller-identity — credenciais nao configuradas"
  echo "        Configure com: aws configure   (ou export AWS_PROFILE=<perfil>)"
  exit 1
fi

echo "== Servicos alcancaveis (somente leitura) =="
check "CloudFormation"    aws cloudformation list-stacks --max-items 1
check "EC2"               aws ec2 describe-vpcs --max-items 1
check "S3"                aws s3api list-buckets
check "IAM (list-roles)"  aws iam list-roles --max-items 1
check "SSM"               aws ssm describe-parameters --max-items 1
check "CodeDeploy"        aws deploy list-applications
check "CodeCommit"        aws codecommit list-repositories
check "Elastic Beanstalk" aws elasticbeanstalk describe-applications

echo "== Ferramentas locais =="
check "aws cli" aws --version
check "jq"      jq --version
check "zip"     zip --version
check "git"     git --version
if command -v git-remote-codecommit >/dev/null 2>&1 || python3 -c 'import git_remote_codecommit' 2>/dev/null; then
  ok "git-remote-codecommit (push CodeCommit assinado com as chaves IAM)"
else
  warn "git-remote-codecommit ausente; o mirror usa o credential helper da CLI (funciona) — opcional: pip install git-remote-codecommit"
fi

echo "== Permissoes de escrita de IAM (best-effort via simulate) =="
# So funciona se o proprio principal tiver iam:SimulatePrincipalPolicy e for um
# usuario/role IAM (nao um assumed-role de SSO). Se nao der, seguimos sem falhar.
if echo "$ARN" | grep -qE ':(user|role)/' && \
   SIM=$(aws iam simulate-principal-policy \
          --policy-source-arn "$ARN" \
          --action-names iam:CreateRole iam:PassRole iam:CreateServiceLinkedRole \
          --query 'EvaluationResults[].[EvalActionName,EvalDecision]' \
          --output text 2>/dev/null); then
  while read -r action decision; do
    [[ "$decision" == "allowed" ]] && ok "iam sim: $action" || bad "iam sim: $action = $decision"
  done <<< "$SIM"
else
  warn "sem iam:SimulatePrincipalPolicy; impossivel verificar CreateRole/PassRole sem tentar o deploy"
  echo "        (se o deploy-infra falhar com AccessDenied em iam:*, e isto)"
fi

echo
if ((FAIL)); then
  echo "Resultado: $FAIL falha(s), $WARN aviso(s). Resolva as falhas antes do deploy."
  exit 1
else
  echo "Resultado: 0 falhas, $WARN aviso(s). Pronto para: make deploy-infra"
fi
