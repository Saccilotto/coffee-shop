# GUIDE — botar a coffee-shop no ar (conta com usuário IAM)

Runbook do operador: do zero a tudo funcionando numa **conta AWS acessada por
usuário IAM** (não-root), com o fluxo de comandos para o ensaio e a
apresentação. Para a coreografia por integrante (quem fala o quê, em quanto
tempo), veja [docs/ROTEIRO_DEMO.md](docs/ROTEIRO_DEMO.md); aqui é a operação.

> **Resumo:** o repositório é *account-agnostic* — nenhum account ID, nome de
> role ou bucket está hardcoded (tudo sai de `sts get-caller-identity` e de
> pseudo-parâmetros). Então **o fluxo com usuário IAM é idêntico ao de root**.
> O que muda é só o que está fora do repo: as permissões do usuário IAM.

## 1. O que muda entre root e usuário IAM

Root tem permissão implícita para tudo; um usuário IAM precisa de permissão
explícita. Esta PoC exige, além das ações de cada serviço, três coisas que
costumam faltar num IAM restrito:

| Necessidade | Por quê | Ação IAM |
| --- | --- | --- |
| Criar IAM roles/instance profiles | O CloudFormation cria as 4 roles da PoC usando **a sua** credencial | `iam:CreateRole`, `iam:PutRolePolicy`, `iam:AttachRolePolicy`, `iam:CreateInstanceProfile`, `iam:AddRoleToInstanceProfile` (+ os `Delete*`/`Get*` para o teardown) |
| **Passar** roles para os serviços | EC2 recebe o instance profile; CodeDeploy e Beanstalk recebem service roles | `iam:PassRole` |
| Service-linked role do Beanstalk | O ambiente EB precisa da SLR `AWSServiceRoleForElasticBeanstalk` na primeira vez | `iam:CreateServiceLinkedRole` |

Mais o acesso de leitura/escrita dos serviços: `cloudformation:*`, `ec2:*`,
`s3:*`, `ssm:*`, `codedeploy:*`, `codecommit:*`, `elasticbeanstalk:*`,
`autoscaling:*`, `elasticloadbalancing:*`, `cloudwatch:*`, `logs:*`, `sts:*`.

**Recomendação prática (conta de trabalho/descartável):** anexe
`AdministratorAccess` ao usuário IAM (ou ao grupo dele). Como a PoC cria IAM
roles arbitrárias, qualquer política "de menos" acaba precisando de `iam:*`
mesmo — admin é o caminho honesto e sem surpresa no meio do deploy.

> **Não é Learner Lab.** O Learner Lab usa credenciais temporárias e a `LabRole`
> fixa, e **não deixa criar IAM roles** — os templates desta PoC (que criam
> roles) não sobem lá sem reescrita. Este guia assume um **usuário IAM em conta
> AWS normal**, que é o caso da conta `Projeto-Computacao` já configurada.

## 2. Preparar a máquina (uma vez)

```bash
# 1. Credenciais do usuário IAM (access key + secret da aba "Security
#    credentials" do usuário no console IAM). Região: us-east-2 nesta conta
#    (veja "Região" abaixo); us-east-1 é o default do projeto.
aws configure                      # perfil default
#   ou, para manter separado de outras contas:
aws configure --profile grupo8 && export AWS_PROFILE=grupo8

# 2. Provar que a credencial é IAM (deve mostrar user/... e NÃO :root)
aws sts get-caller-identity

# 3. (Opcional, recomendado) push para CodeCommit assinado com as chaves IAM,
#    sem gerar git credentials separadas:
pip install git-remote-codecommit

# 4. Dependências locais da API (venv + libs)
make venv
```

`AWS_PROFILE` é respeitado tanto pela CLI quanto pelo boto3 da API, então todos
os `make deploy-*` e scripts usam o perfil que estiver ativo.

> **MFA / SSO:** se o usuário exige MFA para chamadas de API, gere uma sessão
> temporária (`aws sts get-session-token …`) e exporte as três variáveis, ou
> use um perfil SSO. O restante do fluxo não muda.

### Região (us-east-1 é o default; esta conta usa us-east-2)

O projeto **não é mais preso a us-east-1**. A região é resolvida assim, em
ordem de prioridade:

1. variável de ambiente `AWS_DEFAULT_REGION` (se exportada, vence tudo);
2. região do perfil da CLI (`aws configure get region`);
3. `us-east-1` como último fallback.

Os templates CloudFormation já eram region-agnostic (`${AWS::Region}`, AMI e
solution stack resolvidas por região); a EC2 descobre a própria região via IMDS
para ler os parâmetros SSM; o provider do Terraform usa `var.aws_region`. Ou
seja: **basta a região do perfil estar certa** e tudo segue junto.

```bash
# Conta nova: deixar o perfil em us-east-2 (uma vez) — nada mais a fazer:
aws configure set region us-east-2
make preflight                     # deve imprimir "regiao us-east-2"

# Alternativa pontual, sem mexer no perfil (vence o perfil):
export AWS_DEFAULT_REGION=us-east-2
```

Regras de bolso ao trocar de região:

- **Deploy e teardown na MESMA região.** O `teardown.sh` opera na região ativa;
  se você subiu em us-east-2, rode o teardown com o perfil/variável em us-east-2,
  senão ele não encontra as stacks.
- Os links de console impressos (CodeCommit, etc.) já seguem `$AWS_DEFAULT_REGION`.
- Terraform em outra região: `terraform apply -var aws_region=us-east-2` (ou
  deixe o default us-east-1 para o `plan` de comparação do bloco do André).

## 3. Preflight (antes de gastar tempo/dinheiro)

```bash
make preflight
```

Checagem **read-only** (não cria nada): identidade, região, alcance de cada
serviço e — via `iam:simulate-principal-policy` — se o usuário pode
`CreateRole`/`PassRole`/`CreateServiceLinkedRole`. Só siga para o deploy com
**0 falhas**. Na conta `Projeto-Computacao` isso já foi validado: 0 falhas
(único aviso: `git-remote-codecommit` opcional).

## 4. Subir tudo (o "botar no ar")

Cada `make deploy-*` cria recursos **pagos**. A ordem importa (stacks têm
dependências); os scripts esperam cada stack ficar pronta antes da próxima.

```bash
make deploy-infra      # stacks 01-network, 02-compute, 03-cicd  (~4-5 min)
make seed-params       # /coffee-shop/{store-name,motd,discount-pct} no SSM
make deploy-api-iaas   # bundle CodeDeploy -> EC2  (caminho IaaS) — deve dar SUCCEEDED
make deploy-eb         # stack 04-beanstalk (ALB $$) -> aguarda ambiente Green (~8-10 min)
./scripts/seed-parameters.sh --with-api-url   # grava /coffee-shop/api-url (URL do ALB)
./scripts/mirror-codecommit.sh                # cria o repo no CodeCommit e faz push
```

Capture os endereços para os testes (o deploy também os imprime no final):

```bash
export AWS_DEFAULT_REGION=us-east-1
IP=$(aws cloudformation describe-stacks --stack-name coffee-shop-02-compute \
  --query "Stacks[0].Outputs[?OutputKey=='PublicIp'].OutputValue" --output text)
EB_URL=$(aws cloudformation describe-stacks --stack-name coffee-shop-04-beanstalk \
  --query "Stacks[0].Outputs[?OutputKey=='EndpointUrl'].OutputValue" --output text)
echo "IaaS: http://$IP:8000   |   PaaS: $EB_URL"
```

## 5. Fluxo de teste (smoke test, copiar e colar)

```bash
# --- IaaS (EC2 via CodeDeploy) ---
curl -s http://$IP:8000/health | jq          # platform: "iaas"
curl -s http://$IP:8000/menu   | jq '{motd, discount_pct, itens: (.items|length)}'

ORDER=$(curl -s -X POST http://$IP:8000/orders -H 'Content-Type: application/json' \
  -d '{"items":[{"slug":"espresso","quantity":2},{"slug":"cold-brew","quantity":1}]}')
echo "$ORDER" | jq '{id, status, total_cents}'
ID=$(echo "$ORDER" | jq -r .id)
sleep 11;  curl -s http://$IP:8000/orders/$ID | jq .status   # received -> brewing
sleep 20;  curl -s http://$IP:8000/orders/$ID | jq .status   # -> ready

# --- PaaS (Beanstalk, mesma API atrás do ALB) ---
curl -s $EB_URL/health | jq                  # platform: "paas"

# --- Systems Manager: config viva (muda o parâmetro, a API reflete em <=30s) ---
aws ssm put-parameter --name /coffee-shop/motd \
  --value "PROMOCAO DA DEMO: cold brew em dobro!" --overwrite --type String
aws ssm put-parameter --name /coffee-shop/discount-pct --value "20" --overwrite --type String
sleep 32; curl -s http://$IP:8000/menu | jq '{motd, discount_pct}'
make seed-params        # restaura os valores originais

# --- CodeDeploy: rollback automático (revisão quebrada -> Failed -> rollback) ---
make demo-rollback
```

## 6. Fluxo de apresentação (ordem dos blocos)

O ensaio geral usa o mesmo material, mas com a narrativa por integrante e os
tempos de cada bloco — siga [docs/ROTEIRO_DEMO.md](docs/ROTEIRO_DEMO.md). Ordem:

1. **André** — CloudFormation + comparação Terraform (`infra/`, `make preflight`,
   `terraform -chdir=infra/terraform plan`).
2. **Davi** — CodeCommit (história na console) + CodeDeploy (`make deploy-api-iaas`
   e o clímax `make demo-rollback`).
3. **Willian** — Elastic Beanstalk (ambiente Green, deploy de nova versão).
4. **Aloysio** — Systems Manager (Session Manager sem porta 22, Parameter Store
   ao vivo, Run Command na frota) + CloudShell.

Dica de operação: rode a seção 4 **~40 min antes** de apresentar, para o
ambiente Beanstalk já estar Green. Grave um vídeo de backup por bloco na
véspera (plano B da tabela do roteiro).

## 7. Teardown (fim de toda sessão)

```bash
make teardown          # pede confirmação ("sim")
./scripts/teardown.sh --yes   # sem prompt

# checklist de conta limpa (as três listas devem sair vazias):
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'coffee-shop')].StackName" --output text
aws ec2 describe-instances --filters Name=tag:Project,Values=coffee-shop \
  Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId' --output text
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output text
```

O teardown **não** apaga o repositório CodeCommit (custo zero, guarda a história
da demo). Para removê-lo: `aws codecommit delete-repository --repository-name coffee-shop`.
Custos detalhados em [docs/CUSTOS_E_TEARDOWN.md](docs/CUSTOS_E_TEARDOWN.md)
(uma sessão de ensaio de ~3 h ≈ US$ 0,20; o ofensor é o ALB do Beanstalk).

## 8. Troubleshooting específico de usuário IAM

| Erro | Causa | Correção |
| --- | --- | --- |
| `AccessDenied ... iam:CreateRole` no `deploy-infra` | Usuário IAM sem permissão de criar roles | Anexar `AdministratorAccess` (ou o bloco `iam:*` da seção 1) ao usuário/grupo |
| `is not authorized to perform: iam:PassRole` | Falta `iam:PassRole` | Incluir `iam:PassRole` na política (Resource `*` para a PoC) |
| Ambiente Beanstalk falha citando service-linked role | Falta a SLR na primeira vez | `aws iam create-service-linked-role --aws-service-name elasticbeanstalk.amazonaws.com` (idempotente; erra "has been taken" se já existe — ok) |
| `git push codecommit` pede usuário/senha ou dá 403 | Sem git credentials do CodeCommit | `pip install git-remote-codecommit` (assina com as chaves IAM) **ou** gerar "HTTPS Git credentials for CodeCommit" na aba Security credentials do usuário |
| `make preflight` reprova um serviço | Política do usuário não cobre aquele serviço | Ver a linha FALHA; ampliar a política. (Se reprovar só EB por `--max-items`, atualize o repo — isso já foi corrigido) |
| CLI aponta para a conta errada | Perfil/variáveis de ambiente de outra conta ativos | `aws sts get-caller-identity` para conferir; ajustar `AWS_PROFILE` ou `aws configure` |
