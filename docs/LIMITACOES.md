# Limitações e decisões registradas

Limitações conhecidas e assumidas da PoC — cada uma é também um talking
point da apresentação (a história recente da stack DevOps da AWS passa por
aqui).

## 1. Cloud9: indisponível para novos clientes

Fechado para novos clientes em **25/jul/2024**, sem reversão até hoje. Contas
que não tinham ambiente criado antes do corte não conseguem criar — caso
desta conta. Decisão: **não tentar criar ambiente**; a demo do "ambiente de
desenvolvimento na AWS" usa **CloudShell** (gratuito, 1 GB de storage por
região, AWS CLI pré-autenticado). Na apresentação, o par
"Cloud9 descontinuado × CodeCommit ressuscitado" conta a história recente da
suíte de ferramentas de dev da AWS.

## 2. CodeCommit: depreciado e revertido

Jul/2024: AWS fechou o CodeCommit para novos clientes (mesma leva do Cloud9).
**Nov/2025: voltou a GA** — caso raro de reversão pública. A PoC usa o
CodeCommit como origem "oficial" do fluxo da demo (`mirror-codecommit.sh`).
Fallback validado: se algo bloquear a criação do repo na conta, GitHub segue
como origem única e o bloco apresenta o CodeCommit conceitualmente com essa
linha do tempo.

## 3. Agente CodeDeploy × Ubuntu 24.04 (por que a EC2 é 22.04)

A documentação oficial do agente lista suporte em EC2 até **Ubuntu 22.04
LTS**; o 24.04 (Noble) não consta e há relatos de falha na instalação
("no manifest found for platform: ubuntu, version 24.04"). Por isso a stack
`02-compute` fixa **Ubuntu 22.04 (Jammy)** via SSM public parameter — um
downgrade deliberado em relação ao padrão 24.04 do Mineclifford. Alternativa
igualmente válida: Amazon Linux 2023 (UserData com `dnf`). **Verificar a
página de sistemas suportados do agente no dia da execução**; se o Noble
tiver entrado na lista, pode-se voltar. Exemplo real de "compatibilidade de
agente" limitando escolha de SO.

## 4. SQLite por instância (estado da aplicação)

`data/coffee.db` vive no disco de cada instância:

- pedidos criados no Beanstalk **não aparecem** na EC2 e vice-versa;
- com 2 instâncias no ASG, o ALB alterna e o mesmo pedido "some" dependendo
  de quem responde;
- **todo redeploy zera os pedidos** (no Beanstalk o DB está em `/tmp`; no
  CodeDeploy a revisão troca o diretório da app).

Aceitável e até útil na demo: é o efeito visível de deploy imutável + estado
efêmero. Slide de fechamento: produção usaria **DynamoDB** (serverless, sem
gestão) ou **RDS** — e é exatamente essa mudança que tornaria as duas
plataformas equivalentes para o usuário final.

## 5. Beanstalk na VPC default

O environment Beanstalk usa a VPC default da conta, não a VPC 10.0.0.0/16 da
stack 01 — menos parâmetros e menos modos de falha na demo. Em produção o
environment entraria em subnets privadas da VPC do projeto com o ALB nas
públicas.

## 6. Sem TLS e com IP dinâmico

A API responde HTTP puro na porta 8000 (IaaS) e HTTP no ALB (PaaS); a EC2
usa IP dinâmico (sem EIP, que custa quando parado). Para a demo isso é
suficiente; produção teria ACM + HTTPS no ALB e DNS (Route 53) na frente de
tudo.

## 7. Estado por tempo, não por worker

O status do pedido (`received → brewing → ready`) avança por tempo decorrido
calculado na leitura — não há fila nem worker. É honesto para uma demo de
infraestrutura (o assunto é a esteira, não o domínio), e a evolução natural
(SQS + worker) rende um slide de "próximos passos".
