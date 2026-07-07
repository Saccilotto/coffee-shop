# coffee-shop — Trabalho 2 AWS DevOps (Grupo 8)
# Alvos locais nao tocam a AWS. Alvos deploy-* criam recursos pagos: rode
# conscientemente e finalize toda sessao com `make teardown`.

AWS_DEFAULT_REGION ?= us-east-1
export AWS_DEFAULT_REGION

VENV    := .venv
PYTHON  := $(VENV)/bin/python
PIP     := $(VENV)/bin/pip
PYTEST  := $(VENV)/bin/pytest
UVICORN := $(VENV)/bin/uvicorn

.DEFAULT_GOAL := help

.PHONY: help venv test run-local lint package preflight deploy-infra deploy-api-iaas \
        deploy-eb seed-params demo-rollback mirror-codecommit teardown clean

help: ## Lista os alvos disponiveis
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

venv: ## Cria o virtualenv e instala dependencias (runtime + dev)
	python3 -m venv $(VENV)
	$(PIP) install --upgrade pip -q
	$(PIP) install -r api/requirements.txt -r api/requirements-dev.txt -q

test: venv ## Roda a suite pytest em modo local (sem AWS)
	cd api && COFFEE_CONFIG_MODE=local ../$(PYTEST) -v

run-local: venv ## Sobe a API em http://localhost:8000 (modo local, sem AWS)
	cd api && COFFEE_CONFIG_MODE=local ../$(UVICORN) app.main:app --reload --port 8000

lint: venv ## cfn-lint nos templates + compileall no Python
	$(PYTHON) -m compileall -q api/app
	$(VENV)/bin/cfn-lint infra/cloudformation/*.yaml

package: ## Monta o bundle CodeDeploy em build/ (sem upload)
	./scripts/package-codedeploy.sh --no-upload

preflight: ## Checagens read-only da conta antes do deploy (identidade, servicos, IAM)
	./scripts/preflight.sh

deploy-infra: ## [PAGO] Cria/atualiza stacks CloudFormation 01-03 (rede, EC2, CI/CD)
	./scripts/deploy-infra.sh

deploy-api-iaas: ## [PAGO] Empacota e dispara deployment CodeDeploy na EC2
	./scripts/package-codedeploy.sh

deploy-eb: ## [PAGO] Cria/atualiza a stack 04 (Elastic Beanstalk + ALB)
	./scripts/deploy-infra.sh --with-beanstalk

seed-params: ## Cria/atualiza parametros /coffee-shop/* no SSM Parameter Store
	./scripts/seed-parameters.sh

demo-rollback: ## [PAGO] Publica revisao quebrada -> ValidateService falha -> rollback
	./scripts/demo-rollback.sh

mirror-codecommit: ## Cria o repo CodeCommit e faz push espelhado
	./scripts/mirror-codecommit.sh

teardown: ## Destroi TODAS as stacks e artefatos AWS (rode ao fim de cada sessao)
	./scripts/teardown.sh

clean: ## Remove venv, caches e artefatos de build locais
	rm -rf $(VENV) build dist api/data api/.pytest_cache
	find . -type d -name __pycache__ -exec rm -rf {} +
