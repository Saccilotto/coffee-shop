# Roteiro da demo (30–40 min)

Cada bloco é autossuficiente: quem apresenta segue apenas a sua seção, com
comandos copiáveis. Rode tudo a partir da raiz do repo, com AWS CLI v2
configurado em `us-east-1`.

## Antes do dia (véspera)

- [ ] Ensaio completo de ponta a ponta (uma sessão de ~2h; custo em CUSTOS_E_TEARDOWN.md)
- [ ] Gravar **um vídeo de backup por bloco** durante o ensaio (plano B para wifi/console)
- [ ] `./scripts/teardown.sh` ao final do ensaio — conferir a tabela final vazia

## No dia, ~40 min antes (quem abre: responsável pelo bloco 1)

```bash
make deploy-infra              # stacks 01, 02, 03 (~5 min)
make seed-params               # parametros /coffee-shop/*
make deploy-api-iaas           # primeiro deployment CodeDeploy (Succeeded)
make deploy-eb                 # environment Beanstalk (~8-10 min ate Green)
./scripts/seed-parameters.sh --with-api-url
./scripts/mirror-codecommit.sh # repo CodeCommit atualizado
```

Anote o IP da EC2 e a URL do Beanstalk (saem no final de `make deploy-infra`
e `make deploy-eb`); os blocos abaixo usam `$IP` e `$EB_URL`.

```bash
IP=$(aws cloudformation describe-stacks --stack-name coffee-shop-02-compute \
  --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue" --output text)
EB_URL=$(aws cloudformation describe-stacks --stack-name coffee-shop-04-beanstalk \
  --query "Stacks[0].Outputs[?OutputKey=='EndpointUrl'].OutputValue" --output text)
```

---

## Abertura (3 min)

Problema → arquitetura (diagrama de ARQUITETURA.md) → promessa: "o mesmo
commit vai virar uma API rodando por dois caminhos, e vamos quebrar um
deploy de propósito".

## Bloco 1 — CloudFormation + comparação Terraform (8 min)

1. Mostrar `infra/cloudformation/` no editor: 4 stacks, ordem numérica,
   nada criado fora delas.
2. Console → CloudFormation → stack `coffee-shop-02-compute` → abas
   *Resources* (IAM criada de verdade, sem LabRole) e *Outputs* (IP).
3. Provar o rollback de stack (conceito): descrever o que acontece se o
   UserData falhar — a stack volta sozinha (contraste com Terraform).
4. Slide central: tabela de `docs/COMPARACAO_CFN_TERRAFORM.md` +
   código lado a lado (`infra/terraform/`).

```bash
head -40 infra/cloudformation/02-compute.yaml
terraform -chdir=infra/terraform plan
# o plan lista a MESMA infra que as stacks ja criaram — NAO aplicar
# (recursos duplicados); o objetivo e mostrar o preview e o state
```

> Fala-chave: "state file é o artefato que o CloudFormation faz você não ter".

## Bloco 2 — CodeCommit + CodeDeploy (9 min)

1. **CodeCommit**: mostrar a história na console (link no final de
   `./scripts/mirror-codecommit.sh`). Contexto: depreciado jul/2024,
   GA de novo nov/2025.

   ```bash
   git log --oneline -5
   git push codecommit main   # ja atualizado; roda so para mostrar o fluxo
   ```

2. **Deploy bom**: opcionalmente fazer uma mudança visível antes (ex.:
   editar a descrição de um item em `api/app/seed.json` e commitar) —

   ```bash
   make deploy-api-iaas
   curl -s http://$IP:8000/health | jq   # platform: "iaas"
   ```

   Enquanto roda: console → CodeDeploy → deployment → eventos por hook
   (ApplicationStop → AfterInstall → ApplicationStart → ValidateService).

3. **Rollback automático** (o clímax do bloco):

   ```bash
   ./scripts/demo-rollback.sh
   ```

   Narrar enquanto acontece: revisão idêntica exceto
   `COFFEE_FORCE_UNHEALTHY=1` → `/health` responde 503 → ValidateService
   esgota as tentativas → deployment **Failed** → o deployment group
   redeploya a revisão anterior sozinho → o script termina com o `/health`
   de volta a 200. Mostrar na console os DOIS deployments (o Failed e o
   rollback Succeeded).

## Bloco 3 — Elastic Beanstalk (7 min)

1. Console → Elastic Beanstalk → environment `coffee-shop-paas` **Green**:
   mostrar o que veio "de graça" — ALB, ASG (1–2), enhanced health, versões.

   ```bash
   curl -s $EB_URL/health | jq    # platform: "paas" — mesma API do bloco 2
   curl -s $EB_URL/menu | jq '.items[0]'
   ```

2. Deploy de nova versão ao vivo (o equivalente PaaS do bloco 2):

   ```bash
   # bump visivel: editar api/app/__init__.py -> __version__ = "1.1.0"; commit
   make deploy-eb                 # publica novo zip + atualiza a stack
   watch -n 5 "curl -s $EB_URL/health | jq .version"   # 1.0.0 -> 1.1.0
   ```

   Na console: *Application versions* guarda o histórico; *Swap/rollback*
   é um clique.
3. Talking points: PaaS vs IaaS com o MESMO código (slide-resumo);
   plataforma Python AL2023 é WSGI → `Procfile` com UvicornWorker.

## Bloco 4 — Systems Manager + CloudShell (8 min)

1. **Session Manager** (navegador): console → Systems Manager → Session
   Manager → *Start session* na `coffee-shop-api-iaas`. Provar o SG sem 22:

   ```bash
   # dentro da sessao:
   systemctl status coffee-api --no-pager
   curl -s localhost:8000/health
   ```

2. **Parameter Store como config viva** (no terminal local ou CloudShell):

   ```bash
   curl -s http://$IP:8000/menu | jq '{motd, discount_pct}'
   aws ssm put-parameter --name /coffee-shop/motd \
     --value "PROMOCAO DA DEMO: cold brew em dobro!" --overwrite --type String
   aws ssm put-parameter --name /coffee-shop/discount-pct \
     --value "20" --overwrite --type String
   sleep 30
   curl -s http://$IP:8000/menu | jq '{motd, discount_pct, espresso: .items[0].price_cents}'
   ```

   Narrar: cache TTL de 30 s no `config.py`; sem redeploy, sem restart.
3. **Run Command na frota por tag**:

   ```bash
   aws ssm send-command --document-name AWS-RunShellScript \
     --targets Key=tag:Project,Values=coffee-shop \
     --parameters 'commands=["systemctl restart coffee-api","systemctl is-active coffee-api"]' \
     --comment "restart da frota coffee-shop"
   # pegar o CommandId impresso e:
   aws ssm list-command-invocations --command-id <CommandId> --details \
     --query 'CommandInvocations[].{i:InstanceId,s:Status}'
   ```

4. **CloudShell**: abrir pelo ícone da console, `aws sts get-caller-identity`,
   mencionar que é o substituto prático do Cloud9 (slide de LIMITACOES.md).
   Patch Manager: citar como slide, sem demo.

## Fechamento (3 min)

- Limitações honestas (LIMITACOES.md): SQLite por instância, Cloud9,
  Ubuntu 24.04 × agente CodeDeploy.
- Evolução: DynamoDB/RDS, TLS, pipeline CodePipeline completo.
- **Na frente da plateia**: `make teardown` — disciplina de custo como
  parte da engenharia.

---

## Se algo der errado

| Sintoma | Plano B |
| --- | --- |
| Console/wifi caiu | Vídeo de backup do bloco (gravado na véspera) |
| Deployment travado | `aws deploy stop-deployment --deployment-id <id>` e narrar pelo vídeo |
| EB não fica Green a tempo | Bloco 3 usa só a console + vídeo do deploy de versão |
| CodeCommit indisponível na conta | Mostrar GitHub e contar a linha do tempo da depreciação/GA (LIMITACOES.md) |
| IP mudou (stop/start da EC2) | Reexportar `IP=$(aws cloudformation ...)` do topo deste roteiro |
