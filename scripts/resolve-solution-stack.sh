#!/usr/bin/env bash
# Resolve em tempo de deploy o SolutionStackName Python/AL2023 mais recente.
# A string exata ("64bit Amazon Linux 2023 v4.x.y running Python 3.x") muda a
# cada release da plataforma — por isso nunca e hardcodada nos templates.
set -euo pipefail
export AWS_DEFAULT_REGION=us-east-1

STACK=$(aws elasticbeanstalk list-available-solution-stacks \
  --query "SolutionStacks[?contains(@, 'Amazon Linux 2023') && contains(@, 'running Python')] | [0]" \
  --output text)

if [[ -z "$STACK" || "$STACK" == "None" ]]; then
  echo "ERRO: nenhuma solution stack Python/AL2023 encontrada" >&2
  exit 1
fi
echo "$STACK"
