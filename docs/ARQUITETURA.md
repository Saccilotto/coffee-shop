# Arquitetura da PoC

Uma única aplicação (`coffee-api`) percorre o ciclo completo
**desenvolver → versionar → provisionar → implantar → operar**, tocando os
seis serviços designados. O espelhamento deliberado — a mesma base de código
implantada como PaaS (Beanstalk) e como IaaS (EC2 + CodeDeploy) — é o
argumento central da apresentação.

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

## Narrativa (fio condutor dos blocos)

1. **Desenvolver** — sem Cloud9 (indisponível para novos clientes desde
   jul/2024), o ambiente AWS de edição/execução rápida é o **CloudShell**.
   O desenvolvimento pesado acontece local (`make test`, `make run-local`).
2. **Versionar** — GitHub é a origem social; `scripts/mirror-codecommit.sh`
   espelha o repo no **CodeCommit**, que abre o fluxo oficial da demo.
3. **Provisionar** — quatro stacks **CloudFormation**, em ordem:
   `01-network` (VPC/subnet/SG), `02-compute` (EC2 + IAM + agente CodeDeploy
   via UserData), `03-cicd` (bucket de artefatos + application/deployment
   group do CodeDeploy) e `04-beanstalk` (application + environment).
   A stack 03 cria os recursos do próprio CI/CD — IaC provisionando a
   esteira, não só a infra.
4. **Implantar** — o mesmo commit vira:
   - *PaaS*: zip (`app/` + `Procfile` + `requirements.txt`) publicado como
     application version no **Beanstalk** (ELB + ASG + health gerenciados);
   - *IaaS*: bundle CodeDeploy (`appspec.yml` + `api/` + `deploy/`) com hooks
     e **rollback automático** quando o `ValidateService` falha.
5. **Operar** — **Systems Manager**: Session Manager (nenhuma porta 22 em
   nenhum SG), Parameter Store como configuração viva da API (TTL 30 s) e
   Run Command para reiniciar a frota por tag.

## Rede e computação (caminho IaaS)

| Item | Valor |
| --- | --- |
| Região | us-east-1 |
| VPC | 10.0.0.0/16 |
| Subnet pública | 10.0.1.0/24 (+ IGW + route table) |
| AMI | Ubuntu 22.04 LTS via SSM public parameter (não 24.04 — LIMITACOES.md) |
| Instância | t3.micro, gp3 20 GB, IP público dinâmico (sem EIP) |
| Security group | 80, 8000, 2222 abertos; **sem porta 22** |
| Acesso admin | Exclusivamente SSM Session Manager |

## Papéis IAM (criados pelas stacks, sem nada manual)

| Role | Stack | Uso |
| --- | --- | --- |
| InstanceRole + profile | 02-compute | SSM core, leitura do bucket de artefatos, leitura `/coffee-shop/*` |
| CodeDeployServiceRole | 03-cicd | `AWSCodeDeployRole` (orquestrar deployments) |
| ServiceRole (EB) | 04-beanstalk | Enhanced health + managed updates |
| InstanceRole (EB) + profile | 04-beanstalk | WebTier + SSM core + leitura `/coffee-shop/*` |

## Fluxo de configuração dinâmica

`api/app/config.py` resolve cada chave na ordem **SSM → env → default**, com
cache de 30 s. A mesma API, sem redeploy, muda de comportamento quando
`/coffee-shop/motd` ou `/coffee-shop/discount-pct` mudam — a ponte entre o
bloco de deploy e o bloco de operação.

## Decisões que valem slide

- **Mesmo workload, dois modelos de responsabilidade**: no Beanstalk a AWS
  opera ELB/ASG/health/plataforma; na EC2 nós operamos systemd, venv, hooks.
- **SG sem porta 22 + Session Manager**: elimina chave SSH administrativa e
  bastion; a porta 2222 (stretch TUI) é SSH *de aplicação*, contraste útil.
- **Estado por instância (SQLite)**: pedido criado no PaaS não existe no
  IaaS; redeploy zera pedidos. Vira demonstração de deploy imutável e do
  porquê de DynamoDB/RDS em produção (LIMITACOES.md).
- **Nada fora das stacks**: exceções documentadas são o repo CodeCommit e os
  parâmetros SSM, ambos via scripts idempotentes.
