# PM-04 — Projeto Final de DevOps e Infraestrutura

**Automação de infraestrutura com Terraform, Ansible e CI/CD — ToDo App (Feira de Profissões)**

## Integrantes

- _[nome completo — preencher]_
- _[nome completo — preencher]_
- _[nome completo — preencher]_

## Link do repositório

https://github.com/DanielAmaral1/pm04

## 1. Análise da demanda

O documento de demanda (`escopo.pdf`/`docs/escopo.md` do repositório
[todo-app](https://github.com/LaercioMLB/todo-app)) pede a implantação em
nuvem do ToDo App para a Feira de Profissões, com aplicação e banco em VMs
distintas e automação via pipelines. Relação requisito → recurso entregue:

| Requisito do escopo | Recurso entregue |
| --- | --- |
| **REQ-01 · Servidores** — no mínimo duas VMs, uma dedicada ao MongoDB | `terraform/ec2.tf`: `aws_instance.app` (VM1) e `aws_instance.db` (VM2); MongoDB roda exclusivamente na VM2. Recurso adicional: dois buckets S3 (state do Terraform e backups do Mongo), justificados em [`docs/custos.md`](custos.md). |
| **REQ-02 · Rede privada** — MongoDB só acessível pela API, nunca pela internet | `terraform/security_groups.tf`: `sg_db` libera a porta 27017 **somente** a partir do `sg_app` (referência de security group, não CIDR). Nenhuma regra pública na VM2. Verificado em [`evidencias/aceite.md`](../evidencias/aceite.md) (ACE-03). |
| **REQ-03 · Acessos** — administração restrita, credencial própria da app, segredos fora do código | SSH da VM1 liberado só durante o job (AWS CLI, fora do state do Terraform, revogado com `if: always()`); VM2 só acessível via `ProxyJump` pela VM1; usuário Mongo da aplicação (`todoapp`) separado do `root`; credenciais só em GitHub Secrets, com `no_log: true` nas tasks do Ansible que as manipulam. |
| **REQ-04 · Persistência** — armazenamento persistente, backup e restauração testada, atualizações não podem apagar tarefas | Volume nomeado `pm04_mongo_data` (sobrevive a recriação de container, testado — ver ACE-05); `ops.yml` com operações `backup` (mongodump → S3, retenção de 14 dias) e `restore` (testado em container isolado, sem tocar no banco principal). |
| **REQ-05 · Publicação** — URL HTTPS acessível de outro dispositivo, frontend e API no mesmo endereço | Caddy com HTTPS automático (Let's Encrypt) no domínio `<ip>.sslip.io`; Nginx serve o frontend e repassa `/todos` para a API no mesmo domínio público. |
| **REQ-06 · Disponibilidade** — reinício de serviços, healthchecks, diagnóstico documentado | `restart: unless-stopped` + `HEALTHCHECK` em todos os containers; `ops.yml` com `health`, `logs` e `restart`; falhas comuns documentadas em [`docs/manual-alunos.md`](manual-alunos.md). |

## 2. Arquitetura

```
Visitantes --HTTPS--> VM1 (app): Caddy -> Nginx (React) -> API (Express)
                                                                |
                                                   rede privada | :27017
                                                                v
                                                 VM2 (banco): MongoDB
```

- **VPC própria**, sem NAT Gateway (custo evitado; a VM2 usa IP público só
  para saída de `apt`/`docker`, justificado pelo custo de um NAT Gateway
  ser desproporcional ao uso pontual da feira).
- **Backend do Terraform em S3** com `use_lockfile` (lock nativo do S3,
  sem precisar de tabela DynamoDB) e `key` por ambiente
  (`pm04/<environment>/terraform.tfstate`).
- **Build das imagens no runner do GitHub**, não nas VMs — `t3.micro` não
  tem RAM/CPU para buildar um frontend React; as VMs só fazem `pull` das
  imagens já publicadas no GHCR.
- **MongoDB com cache limitado** (`--wiredTigerCacheSizeGB 0.25`) e
  **swap de 1,5GB** nas duas VMs, para caber nos 1GB de RAM de uma
  `t3.micro`.

Decisões de custo e dimensionamento estão detalhadas em
[`docs/custos.md`](custos.md).

## 3. Automação (pipelines)

| Pipeline | Função |
| --- | --- |
| `infra.yml` | Terraform (`fmt/validate/init/plan/apply`/`destroy`) + Ansible completo nas duas VMs. |
| `app.yml` | Build e push das imagens no GHCR (tag = SHA curto), deploy na VM1, rollback via tag anterior. |
| `ops.yml` | `health`, `restart`, `logs`, `backup`, `restore` (isolado) e `reset_demo` (com confirmação explícita). |

Parâmetros, testes dos três cenários do PM-04 (criação, atualização,
reexecução idempotente) e a lista de bugs reais encontrados ao validar
contra a AWS estão documentados no
[`README.md`](../README.md) do repositório.

## 4. Evidências

Ver [`evidencias/README.md`](../evidencias/README.md) (execuções dos
cenários 1–3 e das operações do `ops.yml`) e
[`evidencias/aceite.md`](../evidencias/aceite.md) (critérios ACE-01 a
ACE-10).

## 5. Encerramento

Procedimento de desativação, e o que continua gerando cobrança após o
`destroy` (buckets de state e de backups), em
[`docs/custos.md`](custos.md) e [`docs/manual-alunos.md`](manual-alunos.md).
