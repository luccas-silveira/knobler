# API local

![Live activity de deploy tocando junto com a música](images/closed-activity-music.png)

## O que faz

O diferencial do Knobler: um servidor HTTP em `127.0.0.1:4477` que qualquer
script/processo na mesma máquina pode chamar pra publicar no notch — uma
notificação temporária ou uma "live activity" persistente (anel de progresso)
que atualiza conforme o script avança e desaparece quando termina. Base do
countdown de calendário, do card de bateria e das perguntas do Claude Code
(`docs/ask.md`) — todos usam o mesmo mecanismo de atividade por baixo.

## Como usar

Notificação (card temporário):

```bash
curl -X POST localhost:4477/notify \
  -d '{"title":"Deploy finalizado","body":"em produção","app":"Terminal"}'
```

Live activity (anel de progresso, atualiza incrementalmente):

```bash
curl -X POST localhost:4477/activity \
  -d '{"id":"deploy","title":"Deploy","detail":"rsync","progress":0.4}'
curl -X POST localhost:4477/activity -d '{"id":"deploy","done":true}'
```

CLI incluído (`tools/knobler`, instalar no PATH):

```bash
knobler notify "Título" ["corpo"] ["app"]
knobler activity <id> <0-100|-> "Título" ["detalhe"]
knobler done <id>
knobler agent-request publish '{"id":"perm-1","agent":"claude","kind":"permission","title":"Permissão","summary":"Ler README","source":"terminal","actions":[{"action":"allow"},{"action":"deny"}]}'
knobler agent-request wait perm-1
```

`/notify` aceita `supacodeWorktree`/`supacodeTab` opcionais: clicar na
notificação foca aquela sessão do Supacode.

Ligar/desligar a API local: Ajustes → Notch.

## Solicitações de agentes

`POST /agent-requests` publica uma solicitação e
`GET /agent-requests/<id>` consulta seu estado. Resoluções usam
`POST /agent-requests/<id>/resolve` com uma ação oferecida; `dismiss` cancela.
O resultado final é consumido na primeira leitura e a primeira ação válida
vence.

Essas rotas exigem `Authorization: Bearer <token>`. O token é efêmero por
sessão, tem 32 bytes aleatórios codificados em base64, e fica em
`~/Library/Application Support/Knobler/agent-request-token` com modo `0600`.
Use o CLI em vez de imprimi-lo ou salvá-lo em histórico. Campos inválidos
retornam `400`, token ausente/incorreto `401` e corpos acima de 32 KiB `413`.

`/ask` continua sem autenticação por compatibilidade.

## Permissões

Nenhuma permissão especial — só escuta em `127.0.0.1`, não é exposta na rede.
