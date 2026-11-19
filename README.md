# PM-04 — ToDo App na nuvem (Terraform + Ansible + CI/CD)

Infraestrutura automatizada (Terraform) e configuração/manutenção (Ansible),
acionadas por pipelines de CI/CD (GitHub Actions), para publicar o
[ToDo App](https://github.com/LaercioMLB/todo-app) da Feira de Profissões em
HTTPS, com banco isolado em rede privada.

**URL pública (ambiente `dev`):** https://3-223-65-159.sslip.io
**Evidências de execução:** [`evidencias/`](evidencias/)

## Arquitetura

```
Visitantes ──HTTPS──▶ VM1 (app): Caddy ──▶ Nginx (React) ──▶ API (Express)
                                                                  │
                                                     rede privada │ :27017
                                                                  ▼
                                                   VM2 (banco): MongoDB
```

- **VPC própria**, 1 subnet pública, sem NAT Gateway.
- **VM1 (app)** — Elastic IP, SG libera 80/443 para a internet; 22 só
  temporariamente, aberto/revogado pela própria pipeline via AWS CLI (fora
  do state do Terraform, para não gerar drift). Caddy obtém certificado
  Let's Encrypt automaticamente para o domínio `<ip-com-hifens>.sslip.io`.
- **VM2 (banco)** — IP público só para saída (apt/docker); SG libera 27017
  e 22 **somente** a partir do SG da VM1 (Ansible acessa via `ProxyJump`
  pela VM1). MongoDB com usuário próprio da aplicação, volume nomeado
  persistente, cache do WiredTiger limitado (`--wiredTigerCacheSizeGB 0.25`)
  e swap de 1.5GB nas duas VMs (t3.micro só tem 1GB de RAM).
- **Imagens Docker**: build e push para o GHCR acontecem no runner do
  GitHub (`app.yml`); as VMs só fazem `pull` — t3.micro não tem RAM/CPU
  para build.
- **Backend S3** do Terraform com `use_lockfile` (lock nativo do S3, sem
  DynamoDB) e `key = pm04/<environment>/terraform.tfstate`.
- **Backups** do MongoDB em bucket S3 dedicado, com expiração automática
  em 14 dias (lifecycle rule).

## Pipelines

| Workflow | Gatilho | Função |
| --- | --- | --- |
| `infra.yml` | `workflow_dispatch` | `terraform fmt/validate/init/plan/apply` (ou `destroy`) + Ansible completo nas duas VMs. |
| `app.yml` | `workflow_dispatch` | Valida, builda e publica as imagens no GHCR (tag = SHA curto do commit), implanta na VM1, rollback via `deploy_only` com uma tag anterior. |
| `ops.yml` | `workflow_dispatch` | `health`, `restart`, `logs`, `backup`, `restore` (em container isolado) e `reset_demo` (exige `confirm_reset=RESET`). |

### Parâmetros do `infra.yml`

| Parâmetro | Exemplo | Efeito |
| --- | --- | --- |
| `environment` | `dev` | Prefixo do state (`pm04/<environment>/terraform.tfstate`) e das tags. |
| `action` | `plan` / `apply` / `destroy` | Operação do Terraform. |
| `instance_name` / `instance_type` | `pm04-app` / `t3.micro` | Nome e tipo **da VM1** (app). |
| `db_instance_name` / `db_instance_type` | `pm04-db` / `t3.micro` | Nome e tipo **da VM2** (banco) — variável própria, independente da VM1. |
| `docker_image` | `ghcr.io/danielamaral1/pm04` | Base das imagens; o Ansible monta `<docker_image>-backend:<docker_tag>` e `<docker_image>-frontend:<docker_tag>`. |
| `docker_tag` | SHA curto gerado pelo `app.yml` | Versão das imagens a implantar na VM1. |
| `update_os` | `true` / `false` | Roda `apt upgrade` nas duas VMs. |
| `extra_packages` | `curl,git,unzip` | Pacotes adicionais instalados nas duas VMs. |

## Rodando

Tudo roda pela aba **Actions** do repositório (`workflow_dispatch`), nunca
manualmente fora da pipeline:

1. `app.yml` com `action=build_only` (ou `build_and_deploy`, se o ambiente já
   existir) para publicar as imagens no GHCR.
2. `infra.yml` com `action=apply` e o `docker_tag` gerado no passo anterior.
3. `ops.yml` para as rotinas operacionais (ver tabela acima).
4. `infra.yml` com `action=destroy` para encerrar o ambiente.

## Problemas encontrados e soluções

Bugs reais descobertos ao rodar a pipeline de ponta a ponta contra a AWS
(não só em revisão de código), na ordem em que apareceram:

1. **IAM sem permissão nenhuma.** As credenciais usadas pela pipeline
   (`AWS_ACCESS_KEY_ID`/`SECRET`, usuário IAM `eu`) só tinham a policy
   `IAMUserChangePassword` — qualquer chamada de Terraform/EC2/S3 falhava.
   Diagnosticado comparando a identidade local (`root`, funcionava) com a
   identidade real da pipeline (`arn:...:user/eu`, via
   `aws sts get-caller-identity` dentro do job). Corrigido concedendo
   `AmazonEC2FullAccess` e uma policy de S3 escopada a `arn:aws:s3:::pm04-*`.

2. **Caminho duplicado no job summary.** O step de publicar o `terraform
   plan` fazia `cat terraform/plan.txt`, mas o job já roda com
   `defaults.run.working-directory: terraform` — o caminho real virava
   `terraform/terraform/plan.txt` e o `cat` falhava.

3. **Falha de SSH mascarada por um `for` que nunca falha.** O step
   "aguardar SSH" fazia `for ...; do ssh ... && break; ...; done` sem
   verificar ao final se algum `break` realmente aconteceu — se todas as
   tentativas falhassem, o loop terminava normalmente e o step aparecia
   verde do mesmo jeito. Isso escondeu, por várias execuções, uma chave SSH
   incompatível (`SSH_PRIVATE_KEY`/`SSH_PUBLIC_KEY` não formavam um par).

4. **Chave SSH incompatível.** Confirmado com `Permission denied
   (publickey)` em toda tentativa. As duas VMs já tinham sido lançadas com
   a chave antiga — regenerar o par e atualizar os secrets não bastava,
   porque o `authorized_keys` é gravado no boot da instância a partir da
   chave que existia *naquele momento*; foi preciso recriar as VMs
   (`terraform apply -replace`) para a chave nova ser aplicada.

5. **`| tee` mascarando falha real do Ansible.** O shell padrão das
   actions é `bash -e`, **sem** `pipefail`. Com
   `ansible-playbook ... | tee log`, uma falha do `ansible-playbook` era
   escondida pelo exit code do `tee` (sempre 0) — o job aparecia verde
   mesmo com a execução abortada no meio. Corrigido com `set -o pipefail`
   antes de todo uso desse padrão.

6. **Faltava esperar a VM2 ficar pronta.** Só havia espera de SSH para a
   VM1; a primeira play (VM2) tentava conectar via `ProxyJump` antes do
   sshd da VM2 estar de pé e marcava a VM2 como `UNREACHABLE`, abortando o
   playbook antes mesmo de chegar na play da VM1 (app nunca subia).
   Corrigido com uma segunda espera, via o mesmo `ProxyJump`.

7. **`arch=False` no repositório do Docker.** A expressão Jinja2
   `ansible_architecture == 'x86_64' | ternary('amd64', 'arm64')` é
   avaliada como `ansible_architecture == ('x86_64' | ternary(...))`
   porque o filtro `|` tem precedência maior que `==` — o resultado era
   sempre `False`, gerando `deb [arch=False ...]` e quebrando o índice de
   pacotes (`docker-ce`: "No package matching"). Corrigido com parênteses
   explícitos.

8. **Healthcheck com `localhost` caindo em IPv6.** `wget`/`node` dentro
   dos containers alpine/node resolviam `localhost` para `::1` antes de
   `127.0.0.1`, mas os servidores só escutavam em IPv4 — as checagens
   internas falhavam com "Connection refused" mesmo com os serviços
   saudáveis. Trocado por `127.0.0.1` explícito nas `HEALTHCHECK` das
   Dockerfiles, no `docker-compose.yml.j2` e na checagem do Ansible.

9. **Caddy respondido com erro de TLS antes da hora.** A checagem "local"
   usava `http://localhost/todos`, mas só o Caddy publica a porta 80 no
   host (Nginx não publica porta nenhuma) — a chamada sempre caía no
   Caddy, que redireciona para HTTPS, disparando uma tentativa de TLS
   **antes** do certificado Let's Encrypt terminar de ser emitido
   (`TLSV1_ALERT_INTERNAL_ERROR`). Corrigido testando o Nginx direto via
   `docker exec pm04-nginx wget ... http://127.0.0.1/todos`, sem depender
   do Caddy/TLS; a checagem HTTPS pública ficou com mais tentativas para
   dar tempo à emissão do certificado.

10. **Script de init do Mongo nunca executava.** O mecanismo automático
    `/docker-entrypoint-initdb.d` do Mongo criava o usuário `root`
    corretamente, mas imprimia `ignoring /docker-entrypoint-initdb.d/*` e
    nunca rodava o `init-mongo.js` (mesmo com o arquivo já existindo no
    host, montado como volume) — resultado: o usuário `todoapp` nunca era
    criado e a API ficava em loop de "Authentication failed". Em vez de
    depender da janela de boot do container, a criação do usuário da app e
    o seed dos dados de demonstração passaram a ser tasks Ansible
    explícitas e idempotentes (`db.getUser` / `countDocuments` antes de
    criar/inserir).

11. **`docker_login` não é idempotente.** O módulo
    `community.docker.docker_login` sempre reporta `changed=true` ao
    autenticar, mesmo quando a credencial já é válida — e não dava para
    simplesmente "pular se já logado", porque o `GITHUB_TOKEN` usado é
    efêmero (só vale durante o job que o gerou): uma reexecução que
    pulasse o login reutilizaria um token expirado e o `pull` falhava com
    `denied`. Resolvido relogando sempre, mas com `changed_when: false`
    nessa task — renovar um token efêmero é esperado em toda execução, não
    é uma mudança de configuração real, e não deveria contaminar o
    `changed=0` exigido pelo cenário 3.

12. **`ops.yml` → `restart` com "Permission denied".** O `cd
    /opt/pm04/app` falhava porque o diretório é `0750` (dono `root`, criado
    pelo Ansible com `become: true`) e o usuário `ubuntu` não tem permissão
    de entrar nele — mesmo estando no grupo `docker` (que é o que permite
    `docker ps`/`exec`/`logs` funcionarem sem `sudo` nas outras operações).
    Corrigido com `sudo docker compose -f <caminho completo>`, sem precisar
    trocar de diretório.

## Evidências

Ver [`evidencias/README.md`](evidencias/README.md): link de cada execução
dos cenários 1, 2 e 3 do PM-04 e das operações do `ops.yml`, com o que cada
uma comprova.
