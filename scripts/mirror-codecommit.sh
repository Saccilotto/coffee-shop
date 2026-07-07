#!/usr/bin/env bash
# Espelha este repositorio no AWS CodeCommit (repo "coffee-shop").
#
# GitHub continua sendo a origem social (origin); o CodeCommit e a origem
# "oficial" do fluxo na demo (remote "codecommit"). O CodeCommit voltou a GA
# em nov/2025 - se a conta nao conseguir criar repositorio, o fallback da
# apresentacao e manter GitHub e contar a historia da depreciacao/reversao
# (docs/LIMITACOES.md).
#
# Idempotente: cria o repo so se nao existir, reconfigura o remote e faz push.
set -euo pipefail
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null)}"
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

REPO=coffee-shop
cd "$(dirname "$0")/.."

if aws codecommit get-repository --repository-name "$REPO" >/dev/null 2>&1; then
  echo "==> Repo CodeCommit '$REPO' ja existe"
else
  echo "==> Criando repo CodeCommit '$REPO'"
  aws codecommit create-repository --repository-name "$REPO" \
    --repository-description "Espelho do GitHub Saccilotto/coffee-shop (Trabalho 2 AWS DevOps, Grupo 8)" \
    --tags Project=coffee-shop,Team=grupo8,Env=demo >/dev/null
fi

# git-remote-codecommit (pip) evita gerenciar credenciais HTTPS na mao;
# sem ele, cai para HTTPS + credential helper do AWS CLI.
if git ls-remote "codecommit::$AWS_DEFAULT_REGION://$REPO" >/dev/null 2>&1 || \
   python3 -c 'import git_remote_codecommit' 2>/dev/null; then
  URL="codecommit::$AWS_DEFAULT_REGION://$REPO"
else
  URL="https://git-codecommit.$AWS_DEFAULT_REGION.amazonaws.com/v1/repos/$REPO"
  git config credential."$URL".helper '!aws codecommit credential-helper $@'
  git config credential."$URL".UseHttpPath true
  echo "==> git-remote-codecommit nao instalado; usando HTTPS + credential helper"
  echo "    (opcional: pip install git-remote-codecommit)"
fi

if git remote get-url codecommit >/dev/null 2>&1; then
  git remote set-url codecommit "$URL"
else
  git remote add codecommit "$URL"
fi
echo "==> Remote codecommit -> $URL"

echo "==> Push de main e tags"
git push codecommit main --tags

echo "==> Historia visivel na console:"
echo "    https://$AWS_DEFAULT_REGION.console.aws.amazon.com/codesuite/codecommit/repositories/$REPO/commits"
