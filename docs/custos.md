# Estimativa de custos — PM-04 / ToDo App

## Premissas

| Premissa | Valor |
| --- | --- |
| Provedor / região | AWS, `us-east-1` (N. Virginia) |
| Data dos preços | Novembro/2026 (preços on-demand publicados pela AWS; sujeitos a mudança) |
| Moeda | USD (cobrança da AWS é em dólar) |
| Configuração de referência | 2× `t3.micro`, 20GB `gp3` cada, 2 endereços IPv4 públicos (EIP da VM1 + IP público da VM2) |
| Data/duração da feira | **Não informada pela organização.** Hipótese adotada: 1 dia de exposição, 8 horas de uso real da aplicação, mais ~20 horas de testes/ensaio distribuídas na semana anterior. Confirmar com a organização antes de fixar a janela operacional real (conforme o próprio documento de demanda já alertava). |
| Créditos disponíveis | ~US$ 74 (conta de testes/Free plan da disciplina) |

Fontes de preço (sempre checar a página oficial antes de decisões de orçamento, preços mudam):
- EC2 on-demand: https://aws.amazon.com/ec2/pricing/on-demand/
- EBS: https://aws.amazon.com/ebs/pricing/
- IPv4 pública (cobrada desde 01/02/2024, qualquer endereço IPv4 público, incluindo Elastic IP associado): https://aws.amazon.com/vpc/pricing/
- S3: https://aws.amazon.com/s3/pricing/

## Custo mensal de referência (se o ambiente ficasse ligado o mês todo)

| Item | Preço unitário | Quantidade | Custo/mês |
| --- | --- | --- | --- |
| EC2 `t3.micro` (Linux, on-demand) | US$ 0,0104/h | 2 × 730h | US$ 15,18 |
| EBS `gp3` 20GB | US$ 0,08/GB-mês | 2 × 20GB | US$ 3,20 |
| IPv4 pública (EIP da VM1 + IP público da VM2) | US$ 0,005/h **por IP** | 2 × 730h | US$ 7,30 |
| S3 — armazenamento do state + backups | US$ 0,023/GB-mês | <1GB | < US$ 0,05 |
| Transferência de saída (internet) | 100GB/mês grátis (always-free), depois ~US$ 0,09/GB | tráfego esperado da demo: bem abaixo de 100GB | US$ 0,00 |
| **Total mensal (24/7)** | | | **≈ US$ 25,75** |

> `instance_type`/`db_instance_type` são parâmetros da pipeline — trocar para
> `t3.small` (testado no cenário 2) dobra o custo de EC2 proporcionalmente
> (US$ 0,0208/h), mantendo os demais itens iguais.

## Custo do período da feira (hipótese: ~28h de uso real)

Diferente do armazenamento (EBS e S3, cobrados enquanto o recurso existe,
independente de estar "ligado"), o custo de EC2 e dos IPs públicos só é
proporcional ao tempo em que as instâncias estão **rodando** — e a equipe
controla isso rodando `infra.yml action=destroy` fora das janelas de uso.

| Item | Cálculo | Custo |
| --- | --- | --- |
| EC2 (2× `t3.micro`, 28h) | 2 × 28h × US$ 0,0104 | US$ 0,58 |
| IPv4 pública (2 IPs, 28h) | 2 × 28h × US$ 0,005 | US$ 0,28 |
| EBS (2× 20GB, ~3 dias de ambiente existindo) | 2 × 20GB × US$ 0,08 ÷ 730h × 72h | US$ 0,32 |
| S3 (backups do período) | desprezível | < US$ 0,05 |
| **Total do período da feira** | | **≈ US$ 1,23** |

Bem dentro dos ~US$ 74 de créditos disponíveis — inclusive com folga
grande para erros operacionais (ex.: esquecer o ambiente ligado por 1–2
dias custaria ~US$ 0,60–1,20/dia extra, não US$ 25/dia, porque é exatamente
o cálculo de EC2+IP acima por hora).

## Créditos vs. custo recorrente

- Os ~US$ 74 de créditos são um saldo **da conta**, não um desconto por
  recurso — aparecem como abatimento na fatura, não mudam os preços acima.
- Qualquer valor acima listado é o que a AWS cobraria **sem** os créditos;
  com eles, o custo efetivo do período da feira é zero até o saldo se
  esgotar.

## O que continua gerando cobrança após o `destroy`

`infra.yml action=destroy` remove VPC, subnet, SGs, as duas VMs (e os EBS
volumes associados, já que usam o comportamento padrão
`delete_on_termination=true`) e os Elastic IPs. **Não remove:**

- **Bucket do state** (`pm04-tfstate-daniel-2026`) — precisa continuar
  existindo entre execuções (é o próprio backend do Terraform). Custo:
  poucos centavos de centavo por mês (arquivos de state são pequenos).
- **Bucket de backups** (`pm04-mongo-backups-dev-<conta>`) — tem lifecycle
  de 14 dias, então backups antigos somem automaticamente, mas o bucket em
  si continua existindo e sendo cobrado pelo que tiver dentro até lá.
- **Imagens no GHCR** (GitHub Container Registry) — gratuito para
  repositórios públicos/dentro do limite do plano do GitHub, não é cobrado
  pela AWS.

Para zerar completamente a cobrança da AWS depois do evento, esses dois
buckets S3 precisam ser removidos manualmente (não é automatizado de
propósito, para não arriscar apagar o state ou um backup por engano numa
pipeline).
