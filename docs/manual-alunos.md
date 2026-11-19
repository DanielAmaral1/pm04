# Manual de operação — alunos

Guia para operar o ambiente do ToDo App sem precisar entender Terraform ou
Ansible por dentro. Tudo roda pela aba **Actions** do repositório
(https://github.com/DanielAmaral1/pm04/actions) — nunca direto no servidor.

Em cada workflow: botão **Run workflow**, escolher a branch `main`, preencher
os campos pedidos e clicar em **Run workflow**. O resultado aparece no job
summary da execução (aba Actions → clicar na execução → "Summary").

## Iniciar o ambiente

**Workflow:** `infra.yml`
**Parâmetros principais:** `environment=dev`, `action=apply`,
`instance_type`/`db_instance_type` (ex.: `t3.micro`), `docker_image`
(deixar o padrão `ghcr.io/danielamaral1/pm04`), `docker_tag` (pedir para
quem fez o último `app.yml build_and_deploy` qual é a tag atual, ou ver em
[`evidencias/README.md`](../evidencias/README.md)), `update_os`,
`extra_packages`.
**Resultado esperado:** os dois jobs (`terraform` e `configure`) terminam
verdes; o job summary mostra o plan do Terraform e o PLAY RECAP do Ansible
sem `failed`. A URL fica acessível em `https://<ip-com-hifens>.sslip.io`
(o IP aparece nos outputs do Terraform, no job summary).
**Falhas comuns:**
- Se `docker_tag` não existir no GHCR, o Ansible falha no deploy da
  aplicação — rode `app.yml` primeiro para publicar a imagem.
- Se já existe ambiente criado e nada mudou, `action=apply` não deveria dar
  erro (é idempotente) — se der erro de permissão SSH, avise quem
  administra a conta AWS (pode ser chave SSH desatualizada).

## Verificar saúde

**Workflow:** `ops.yml`
**Parâmetros:** `environment=dev`, `operation=health`.
**Resultado esperado:** job summary lista os containers das duas VMs
(devem aparecer `pm04-api`, `pm04-nginx`, `pm04-caddy` na VM1 e
`mongo-pm04` na VM2, todos "Up") e o código HTTP do endpoint público
(esperado: `200`).
**Falhas comuns:** código diferente de 200 pode ser certificado HTTPS
ainda sendo emitido (aguardar 1-2 minutos depois de um `infra.yml apply`)
ou algum container caído — ver a operação `logs` a seguir.

## Atualizar a versão da aplicação

**Workflow:** `app.yml`
**Parâmetros:** `environment=dev`, `action=build_and_deploy`.
**Resultado esperado:** job `build` builda e publica duas imagens novas no
GHCR (tag = SHA curto do commit atual do `main`); job `deploy` implanta
essa tag na VM1 e confirma o healthcheck. O job summary mostra qual tag
foi implantada — guardar esse valor, é a referência para um rollback
futuro.
**Falhas comuns:** se o build falhar na validação (`node --check` ou
`npm run build`), o deploy nem começa — corrigir o código antes de tentar
de novo.

## Rollback

**Workflow:** `app.yml`
**Parâmetros:** `environment=dev`, `action=deploy_only`, `docker_tag=<tag
anterior que funcionava>` (ver histórico de tags em
[`evidencias/README.md`](../evidencias/README.md) ou nos job summaries de
execuções anteriores do `app.yml`).
**Resultado esperado:** a aplicação volta a responder com a versão
anterior, sem rebuildar nada — é só um redeploy mais rápido.
**Falhas comuns:** `docker_tag` com erro de digitação faz o pull falhar
(`manifest unknown`) — copiar a tag exatamente como aparece no job summary
da execução antiga.

## Logs

**Workflow:** `ops.yml`
**Parâmetros:** `environment=dev`, `operation=logs`.
**Resultado esperado:** job summary com as últimas 100 linhas de cada
container (`pm04-api`, `pm04-nginx`, `pm04-caddy`, `mongo-pm04`) — útil
para entender por que um `health` deu código diferente de 200, ou por que
uma tarefa não salvou.
**Falhas comuns:** nenhuma específica; se a VM estiver fora do ar, o
step falha ao conectar via SSH (ver se o ambiente não foi destruído sem
querer).

## Reiniciar serviços

**Workflow:** `ops.yml`
**Parâmetros:** `environment=dev`, `operation=restart`.
**Resultado esperado:** `docker compose restart` nas duas VMs; job
summary mostra cada container saindo de `Restarting` para `Started`.
**Quando usar:** container travado, API parando de responder sem motivo
aparente aparecendo nos logs.

## Backup e restore

**Backup — Workflow:** `ops.yml`, **Parâmetros:** `environment=dev`,
`operation=backup`.
**Resultado esperado:** job summary mostra o caminho `s3://.../dev/pm04-
backup-<timestamp>.gz` onde o backup foi salvo. Backups somem
automaticamente depois de 14 dias (política do bucket).

**Restore — Workflow:** `ops.yml`, **Parâmetros:** `environment=dev`,
`operation=restore`, `restore_backup_key` (opcional — deixar vazio usa o
backup mais recente).
**Resultado esperado:** job summary mostra quantos documentos foram
restaurados **num container isolado e temporário**, que é destruído ao
final. **O banco principal não é alterado** — restore é só para testar
que o backup funciona, não repõe dados na aplicação em produção.
**Falhas comuns:** "Nenhum backup encontrado" significa que a pasta
`<environment>/` do bucket está vazia — rodar `backup` primeiro.

## Preparar a lista para a demonstração

**Workflow:** `ops.yml`
**Parâmetros:** `environment=dev`, `operation=reset_demo`,
`confirm_reset=RESET` (**tem que ser exatamente essa palavra**, em
maiúsculas — é de propósito, para não apagar a lista por engano).
**Resultado esperado:** a lista de tarefas é apagada e volta a ter só os
3 itens de demonstração padrão. Confirmar abrindo
`https://3-223-65-159.sslip.io` depois.
**Quando usar:** sempre antes de uma nova apresentação, para não mostrar
tarefas deixadas por um visitante anterior.
**Falhas comuns:** esquecer o `confirm_reset=RESET` faz o workflow parar
de propósito, sem apagar nada — é o comportamento esperado, não um erro.

## Encerrar o ambiente

**Workflow:** `infra.yml`
**Parâmetros:** `environment=dev`, `action=destroy` (os demais parâmetros
não importam para destroy, mas o formulário exige valores — pode repetir
os últimos usados).
**Resultado esperado:** o job `terraform` mostra o plan de destruição e
aplica — VMs, EIP, SGs, VPC e subnet são removidos. O job `configure` não
roda (destroy não precisa de Ansible).
**Importante:** isso **não remove** o bucket de state nem o de backups
(ver [`docs/custos.md`](custos.md), seção "O que continua gerando
cobrança") — de propósito, para nunca apagar dados por engano numa
pipeline automática.
**Falhas comuns:** se alguém rodar `apply` de novo depois de um `destroy`,
o ambiente é recriado do zero (novo IP público) — os dados do Mongo
**não voltam** (o volume também foi destruído junto com a VM2). Se quiser
preservar dados entre um destroy e um apply seguinte, rodar `backup` antes
de destruir.
