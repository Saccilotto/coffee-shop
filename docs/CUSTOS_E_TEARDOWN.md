# Custos e disciplina de teardown

Conta **pessoal** (Paid Plan) — cada recurso esquecido é dinheiro real do
dono da conta. Regra inegociável: **toda sessão de trabalho/ensaio termina
com `./scripts/teardown.sh`** e conferindo a tabela final vazia.

## Custo por hora (us-east-1, on-demand, jul/2026 aproximado)

| Recurso | Origem | ~US$/hora | Observação |
| --- | --- | --- | --- |
| EC2 t3.micro (IaaS) | stack 02 | 0,0104 | o caminho CodeDeploy |
| EBS gp3 20 GB | stack 02 | 0,0004 | ~0,32/mês se esquecido |
| **ALB do Beanstalk** | stack 04 | **0,0225 + LCU (~0,008)** | **maior ofensor; cobra por hora mesmo sem tráfego** |
| EC2 t3.micro ×1–2 (PaaS) | stack 04 | 0,0104–0,0208 | ASG min 1 max 2 |
| S3 artefatos | stack 03 | ~0 | centavos/mês; versionado (teardown purga versões) |
| SSM (Session/Params/Run Command) | scripts | 0 | tier standard é gratuito |
| CloudFormation / CodeDeploy (EC2) | — | 0 | serviços sem cobrança própria |
| CodeCommit | script | 0 | free tier: 5 usuários ativos |
| CloudShell | console | 0 | inclui 1 GB de storage por região |

## Cenários

| Cenário | Conta aproximada |
| --- | --- |
| Ensaio de 3 h com TUDO de pé (EC2 + EB com ALB + 2×t3.micro) | ~US$ 0,20 |
| Só o caminho IaaS por 3 h (sem stack 04) | ~US$ 0,04 |
| **Esquecer tudo ligado por 24 h** | **~US$ 1,60** |
| Esquecer tudo ligado por um mês | ~US$ 48 |

Conclusões práticas:

1. A stack **04-beanstalk só sobe em janela de ensaio/demo** (`make deploy-eb`)
   e cai no teardown — é o ALB que faz a conta andar.
2. Sem EIP, sem NAT Gateway, sem RDS: decisões de projeto, não acidentes.
   (EIP desassociado cobra; NAT ~US$ 0,045/h; nenhum é necessário na demo.)
3. t3.micro (e não medium): a coffee-api é leve de propósito.

## O teardown

```bash
./scripts/teardown.sh        # pede confirmacao ("sim")
./scripts/teardown.sh --yes  # sem prompt (para o final do ensaio)
```

Ordem executada (reversa da criação):

1. `coffee-shop-04-beanstalk` (environment + ALB + ASG somem juntos)
2. Purge do bucket de artefatos — **todas as versões** e delete markers
   (bucket versionado não esvazia com `aws s3 rm` simples)
3. `coffee-shop-03-cicd`
4. `coffee-shop-02-compute`
5. `coffee-shop-01-network`
6. Parâmetros `/coffee-shop/*` do SSM
7. Lista stacks remanescentes com prefixo `coffee-shop` — **deve sair vazia**

O que o teardown **não** apaga (decisão consciente):

- Repo **CodeCommit** (histórico da demo; custo zero no free tier).
  Para remover: `aws codecommit delete-repository --repository-name coffee-shop`
- Logs no CloudWatch criados pelo Beanstalk (retenção default; custo ~0.
  Para zerar: console → CloudWatch → Log groups → prefixo `/aws/elasticbeanstalk`)

## Checklist pós-sessão (30 segundos)

```bash
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE \
  --query "StackSummaries[?starts_with(StackName,'coffee-shop')].StackName"
aws ec2 describe-instances --filters Name=tag:Project,Values=coffee-shop \
  Name=instance-state-name,Values=running --query 'Reservations[].Instances[].InstanceId'
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
```

As três listas vazias = conta limpa, pode dormir tranquilo.
