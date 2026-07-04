# coffee-shop ☕

PoC do **Trabalho 2 — AWS DevOps (Grupo 8)**: uma API de pedidos de café
(FastAPI + SQLite) implantada por **dois caminhos** — Elastic Beanstalk (PaaS) e
EC2 via CodeDeploy (IaaS) — com toda a infraestrutura provisionada por
CloudFormation e operação via Systems Manager. Estética inspirada no
[terminal.shop](https://www.terminal.shop).

## Os seis serviços designados

```text
  CloudShell (Cloud9 indisponivel)   (1. desenvolver)
          |
          v
  CodeCommit  <-- espelho do GitHub  (2. versionar codigo + templates)
          |
          v
  CloudFormation                     (3. provisionar: VPC, SG, EC2, IAM, CodeDeploy app, EB app)
          |
   +------+---------+
   v                v
 Elastic          CodeDeploy         (4. deploy da coffee-api por dois caminhos)
 Beanstalk           |
 (PaaS: API          v
  gerenciada,      EC2 (IaaS: API self-managed
  ELB, ASG)             + coffee-tui stretch)
    \                |
     +------> Systems Manager        (5. operar: Session Manager, Parameter Store, Run Command)
                     |
                     v
               CloudWatch            (apoio, nao designado: logs/metricas de tudo)
```

| Serviço | Papel na PoC | Onde no repo |
| --- | --- | --- |
| CloudFormation | Provisiona toda a infra e os próprios recursos de CI/CD | `infra/cloudformation/` |
| CodeCommit | Repo espelho do GitHub; origem "oficial" do fluxo na demo | `scripts/mirror-codecommit.sh` |
| CodeDeploy | Deploy versionado na EC2, com hooks e rollback automático | `deploy/` + stack `03-cicd.yaml` |
| Systems Manager | Session Manager, Parameter Store, Run Command | `scripts/seed-parameters.sh` + `docs/` |
| Elastic Beanstalk | A mesma API como PaaS: ELB, auto scaling, versões | stack `04-beanstalk.yaml` + `api/Procfile` |
| Cloud9 | Indisponível para novos clientes desde jul/2024 → CloudShell | `docs/LIMITACOES.md` |

## Quickstart local (sem AWS)

```bash
make test        # pytest da API em modo local
make run-local   # API em http://localhost:8000 (docs em /docs)

curl -s localhost:8000/menu | jq
curl -s -X POST localhost:8000/orders \
  -H 'Content-Type: application/json' \
  -d '{"items": [{"slug": "espresso", "quantity": 2}]}' | jq
```

## A API

| Método | Rota | Função |
| --- | --- | --- |
| GET | `/health` | Health check (ELB do Beanstalk + hook ValidateService do CodeDeploy) |
| GET | `/menu` | Cardápio com preços (desconto vem do SSM `/coffee-shop/discount-pct`) |
| GET | `/inventory` | Estoque atual por item |
| POST | `/orders` | Cria pedido e decrementa estoque |
| GET | `/orders/{id}` | Status do pedido: `received` → `brewing` → `ready` (avança por tempo) |

Configuração dinâmica via **SSM Parameter Store** (`/coffee-shop/store-name`,
`/coffee-shop/motd`, `/coffee-shop/discount-pct`) com fallback para variáveis de
ambiente e defaults locais — cache de 30 s (`api/app/config.py`).

## Fluxo de deploy na AWS

> **Pré-requisitos:** AWS CLI v2 configurado (conta pessoal, `us-east-1`),
> permissões de administrador. **Todos os alvos `deploy-*` criam recursos
> pagos.** Termine toda sessão com `make teardown`.

```bash
make deploy-infra      # stacks 01-network, 02-compute, 03-cicd
make seed-params       # parametros /coffee-shop/* no SSM
make deploy-api-iaas   # bundle CodeDeploy -> EC2  (caminho IaaS)
make deploy-eb         # stack 04-beanstalk        (caminho PaaS, ALB $$)
make demo-rollback     # demo: revisao quebrada -> rollback automatico
make teardown          # destroi tudo, em ordem reversa
```

## Documentação

- [docs/ARQUITETURA.md](docs/ARQUITETURA.md) — diagrama e narrativa dev→commit→provision→deploy→operate
- [docs/ROTEIRO_DEMO.md](docs/ROTEIRO_DEMO.md) — passo a passo por integrante, com comandos e tempos
- [docs/COMPARACAO_CFN_TERRAFORM.md](docs/COMPARACAO_CFN_TERRAFORM.md) — CloudFormation × Terraform, recurso a recurso
- [docs/CUSTOS_E_TEARDOWN.md](docs/CUSTOS_E_TEARDOWN.md) — custo/hora de cada peça e disciplina de teardown
- [docs/LIMITACOES.md](docs/LIMITACOES.md) — Cloud9, CodeCommit, agente CodeDeploy × Ubuntu 24.04, SQLite

Tags padrão de todos os recursos: `Project=coffee-shop`, `Team=grupo8`, `Env=demo`.
