# Evidências de execução — PM-04

Repositório: https://github.com/DanielAmaral1/pm04
URL pública da aplicação (ambiente `dev`): https://3-223-65-159.sslip.io

> As tags de imagem e os links de run citados aqui são do histórico atual do
> repositório. Depois da reescrita final do histórico (remoção das linhas de
> atribuição do Claude Code), os commits mudam de SHA e o `app.yml` foi
> executado de novo para gerar imagens com a tag do commit final — ver seção
> "Após a reescrita do histórico" no fim deste arquivo.

## Cenário 1 — Criação inicial

**Run:** https://github.com/DanielAmaral1/pm04/actions/runs/44208709706

O que prova: a partir do zero (VPC, subnet, SGs, VMs e EIP ainda não
existentes para essa aplicação), `infra.yml` com `action=apply` roda
`terraform init/plan/apply` e em seguida o Ansible completo
(`base_packages → os_updates → docker → mongodb → app → healthcheck`) nas
duas VMs, encerrando com o healthcheck HTTPS passando. Ao final:

- VM1 (app) e VM2 (banco) provisionadas, SGs com o isolamento do MongoDB.
- Containers Caddy + Nginx + API no ar, MongoDB com usuário próprio da
  aplicação e dados de demonstração.
- `https://3-223-65-159.sslip.io/todos` responde 200 com certificado
  Let's Encrypt válido (emitido automaticamente pelo Caddy).
- Mongo isolado: porta 27017 do IP público da VM2 não responde de fora da
  rede privada (testado com `timeout 5 bash -c "echo > /dev/tcp/<ip>/27017"`).

## Cenário 2 — Atualização do ambiente

**Run:** https://github.com/DanielAmaral1/pm04/actions/runs/44422755271

Parâmetros alterados nessa execução, em relação ao cenário 1:

| Parâmetro | Antes | Depois |
| --- | --- | --- |
| `instance_type` (VM1) | `t3.micro` | `t3.small` |
| `extra_packages` | _(vazio)_ | `htop,tree` |
| `update_os` | `false` | `true` |

O que prova:

- **Terraform fez update in-place, sem recriar a VM1** — o plan mostra
  `# aws_instance.app will be updated in-place` com
  `~ instance_type = "t3.micro" -> "t3.small"` e o resumo final é
  `Plan: 0 to add, 1 to change, 0 to destroy.`
- O **IP público e o domínio não mudaram** (`3.223.65.159` /
  `3-223-65-159.sslip.io`) — confirmado com `terraform output` e um `curl`
  HTTPS logo após o apply.
- **Mudança do Ansible visível**: PLAY RECAP com `changed=2` na VM2 e
  `changed=3` na VM1 (instalação dos pacotes extras + `apt upgrade` do
  `update_os=true`, mais a configuração renovada do app).

## Cenário 3 — Reexecução sem alterações

**Run (evidência final, idempotente):** https://github.com/DanielAmaral1/pm04/actions/runs/44425051980

Mesmos parâmetros do cenário 2, executados de novo sem nenhuma mudança.

O que prova:

- Terraform: `No changes. Your infrastructure matches the configuration.`
- Ansible PLAY RECAP: `changed=0` na VM2 **e** na VM1.

> Nota sobre o caminho até aqui: a primeira tentativa de reexecução
> ([run 44423436082](https://github.com/DanielAmaral1/pm04/actions/runs/44423436082))
> mostrou `changed=1` na VM1 por causa de um bug real do módulo
> `community.docker.docker_login` (ele sempre reporta `changed=true` ao
> autenticar, mesmo sem nada ter mudado). Corrigido fixando
> `changed_when: false` nessa task — o login no GHCR precisa ser refeito a
> cada execução porque o `GITHUB_TOKEN` usado é efêmero (válido só durante o
> job), mas isso não é uma mudança de configuração real. Detalhes na seção
> "Problemas encontrados e soluções" do README principal.

## Operações (`ops.yml`)

Execuções de validação de cada operação, todas no ambiente `dev`:

| Operação | Run | O que prova |
| --- | --- | --- |
| `health` | [44428538759](https://github.com/DanielAmaral1/pm04/actions/runs/44428538759) | Lista containers das duas VMs e testa o endpoint público HTTPS. |
| `backup` | [44428718519](https://github.com/DanielAmaral1/pm04/actions/runs/44428718519) | `mongodump` da VM2 enviado para `s3://pm04-mongo-backups-dev-.../dev/pm04-backup-20261119T002444Z.gz` (confirmado com `aws s3 ls`). |
| `restore` | [44428845526](https://github.com/DanielAmaral1/pm04/actions/runs/44428845526) | Baixa o backup do S3 e restaura em um container Mongo **isolado** (`mongo-pm04-restore-test`, volume próprio) na VM2 — restaurou 4 documentos, container e volume destruídos ao final, e o banco principal (`mongo-pm04`) continuou exigindo autenticação normalmente (não foi tocado). |
| `logs` | [44429097180](https://github.com/DanielAmaral1/pm04/actions/runs/44429097180) | Últimas 100 linhas de `pm04-api`, `pm04-nginx`, `pm04-caddy` (VM1) e `mongo-pm04` (VM2) no job summary. |
| `restart` | [44429400601](https://github.com/DanielAmaral1/pm04/actions/runs/44429400601) | `docker compose restart` nas duas VMs — log mostra os containers `Restarting` → `Started`. (Uma primeira tentativa, [44429211502](https://github.com/DanielAmaral1/pm04/actions/runs/44429211502), falhou com `Permission denied` ao tentar `cd` num diretório `0750` root; corrigido usando `sudo docker compose -f <path>`.) |
| `reset_demo` (sem confirmação) | [44429543674](https://github.com/DanielAmaral1/pm04/actions/runs/44429543674) | Operação destrutiva bloqueada: falha explicitamente se `confirm_reset` não for exatamente `RESET`. |
| `reset_demo` (confirmado) | [44439096440](https://github.com/DanielAmaral1/pm04/actions/runs/44439096440) | Lista apagada e reseedada com os 3 itens de demonstração — confirmado com `GET /todos` logo após. |

## Após a reescrita do histórico

_(preencher depois de `git push --force-with-lease` e da nova execução do
`app.yml`: novo SHA curto / tag de imagem usada, e se algum link de run acima
precisar ser atualizado — os runs já concluídos continuam acessíveis pelos
mesmos links mesmo após o rewrite, só a tag de imagem padrão do `docker_tag`
muda.)_
