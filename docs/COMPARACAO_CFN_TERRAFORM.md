# CloudFormation × Terraform — a mesma infra, duas ferramentas

Material do bloco de IaC. As duas árvores descrevem **exatamente a
mesma infraestrutura** (rede + computação do caminho IaaS):

- `infra/cloudformation/01-network.yaml` + `02-compute.yaml` — usadas de verdade na PoC
- `infra/terraform/` — espelho recurso a recurso, para comparação (`terraform plan` opcional)

Regra de ouro da PoC: **nunca aplicar os dois ao mesmo tempo** — são recursos
duplicados e custo duplicado.

## Mapa recurso a recurso

| Recurso | CloudFormation | Terraform |
| --- | --- | --- |
| VPC 10.0.0.0/16 | `AWS::EC2::VPC` (`Vpc`) | `aws_vpc.main` |
| Internet Gateway | `AWS::EC2::InternetGateway` + `AWS::EC2::VPCGatewayAttachment` | `aws_internet_gateway.main` (attachment implícito no `vpc_id`) |
| Subnet pública 10.0.1.0/24 | `AWS::EC2::Subnet` | `aws_subnet.public` |
| Route table + rota default | `AWS::EC2::RouteTable` + `AWS::EC2::Route` + associação | `aws_route_table` + `aws_route` + `aws_route_table_association` |
| Security group 80/8000/2222 | `AWS::EC2::SecurityGroup` | `aws_security_group.app` |
| AMI Ubuntu 22.04 dinâmica | Parâmetro `AWS::SSM::Parameter::Value<AWS::EC2::Image::Id>` | `data "aws_ssm_parameter"` |
| Role + instance profile | `AWS::IAM::Role` + `AWS::IAM::InstanceProfile` | `aws_iam_role` + `aws_iam_role_policy_attachment` + `aws_iam_instance_profile` |
| EC2 t3.micro gp3 20GB | `AWS::EC2::Instance` (UserData `Fn::Base64`/`!Sub`) | `aws_instance.api` (heredoc `user_data`) |
| Tags padrão em tudo | `--tags` na stack (o serviço propaga) | `default_tags` no provider |
| Conta/região correntes | Pseudo-parâmetros `AWS::AccountId`, `AWS::Region` | `data.aws_caller_identity`, `data.aws_region` |
| Key pair opcional | `Conditions:` + `!If [..., !Ref 'AWS::NoValue']` | `var.key_name != "" ? var.key_name : null` |

## Lado a lado: o mesmo condicional

CloudFormation (`02-compute.yaml`):

```yaml
Conditions:
  HasKeyName: !Not [!Equals [!Ref KeyName, '']]
# ...
      KeyName: !If [HasKeyName, !Ref KeyName, !Ref 'AWS::NoValue']
```

Terraform (`compute.tf`):

```hcl
key_name = var.key_name != "" ? var.key_name : null
```

O condicional do CloudFormation é declarado numa seção própria e referenciado
por nome; no Terraform é uma expressão inline. É um bom resumo da diferença de
linguagem: **YAML + funções intrínsecas** (declarativo estrito, verboso, sem
expressões arbitrárias) contra **HCL** (linguagem de expressões completa, com
`for`, ternários e funções — mais poder, mais chance de "programar demais" a
infra).

## Análise

| Dimensão | CloudFormation | Terraform |
| --- | --- | --- |
| **Estado** | Gerenciado pela AWS dentro da stack; não existe artefato de estado para guardar/proteger | `terraform.tfstate` é responsabilidade sua: backend remoto (S3 + lock), segredos em claro no state, corrupção = dia ruim |
| **Drift** | Drift detection nativa por stack/recurso (console/CLI), mas passiva: você pede a verificação | Todo `terraform plan` é uma detecção de drift; o refresh compara o mundo real com o state a cada execução |
| **Rollback** | Automático: falha no meio da criação/update reverte a stack ao estado anterior (visto na prática na PoC) | Não há rollback: um apply que falha para no meio e o estado fica parcial; recuperar é corrigir e aplicar de novo |
| **Alcance** | Só AWS (100% dos recursos, inclusive os mais novos, muitas vezes no dia do lançamento) | Multi-provider: AWS + Cloudflare + GitHub + Datadog no mesmo grafo; recursos AWS novos dependem do provider acompanhar |
| **Linguagem** | YAML/JSON + funções intrínsecas (`!Sub`, `!Ref`, `Fn::If`); parâmetros tipados que resolvem SSM em deploy-time | HCL com expressões, `count`/`for_each`, módulos; data sources cobrem o papel dos parâmetros dinâmicos |
| **Reuso** | Nested stacks e StackSets (multi-conta/multi-região nativos, ligados a Organizations) | Módulos + registry público — ecossistema de reuso muito maior; multi-conta via workspaces/wrappers (Terragrunt) |
| **Permissões** | O serviço executa com a role da stack (service role): dá para dar menos poder ao humano | Quem roda o apply precisa das permissões de tudo que o plano toca (ou CI com role dedicada) |
| **Preview** | Change sets (opcionais, um passo extra) | `terraform plan` é o centro do fluxo de trabalho |
| **Custo da ferramenta** | Gratuito (paga-se só os recursos) | Gratuito (OSS); state remoto/HCP Terraform tem tier pago |

## Quando usar qual (posição para a apresentação)

- **Só AWS + times pequenos + integração com serviços AWS de deploy** (o caso
  desta PoC: CodeDeploy, Beanstalk, tags de stack): CloudFormation remove a
  classe inteira de problemas de state e dá rollback de graça.
- **Multi-cloud, ecossistema de módulos, plan como cultura de revisão**:
  Terraform. É também o que o mercado mais pede como skill de IaC.
- Os dois convivem bem: nesta PoC o CloudFormation provisiona, e o espelho
  Terraform existe para estudo (Terraform Associate 004) — state, drift e
  "quando usar ferramenta nativa vs agnóstica" são exatamente os tópicos do
  exame.

## Notas de portabilidade observadas ao escrever o espelho

1. O attachment do IGW é um recurso separado no CloudFormation
   (`VPCGatewayAttachment` + `DependsOn` na rota); no Terraform está implícito
   e a ordem sai do grafo de referências.
2. `managed_policy_arns` inline na role está **deprecado** no provider AWS —
   o espelho usa `aws_iam_role_policy_attachment` (a versão CloudFormation
   usa `ManagedPolicyArns` sem drama). Exemplo real de "o provider anda em
   ritmo próprio".
3. Tags: `default_tags` do provider ≈ `--tags` da stack, mas o CloudFormation
   propaga também para recursos que ele cria indiretamente (ex.: volumes do
   Beanstalk), enquanto no Terraform depende de cada recurso suportar tags.
4. A AMI "current" via SSM é resolvida **no deploy** nas duas ferramentas,
   mas no Terraform ela entra no state: quando o parâmetro público muda, o
   próximo `plan` propõe recriar a instância — drift deliberado que rende
   discussão em aula.
