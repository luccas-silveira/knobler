# API local

![Live activity de deploy tocando junto com a música](images/closed-activity-music.png)

## Visão geral

O Knobler expõe um servidor HTTP opcional em `127.0.0.1:4477`. Ele aceita
notificações transitórias, live activities, controle do espelho e perguntas
interativas. O servidor escuta somente loopback. As rotas legadas, incluindo
`/ask`, permanecem sem autenticação por compatibilidade. Solicitações de
agentes usam um token efêmero de sessão, gravado com modo `0600` em
`~/Library/Application Support/Knobler/agent-request-token`.

Ligue em Ajustes → Notch → API local. Desligar a opção fecha o listener e
remove activities e perguntas pendentes.

## Ferramentas rápidas

```bash
# notificação
curl -X POST http://127.0.0.1:4477/notify \
  -H 'Content-Type: application/json' \
  -d '{"title":"Deploy finalizado","body":"em produção","app":"Terminal"}'

# live activity determinada; progress aceita 0–1 ou 0–100
curl -X POST http://127.0.0.1:4477/activity \
  -d '{"id":"deploy","title":"Deploy","detail":"rsync","progress":40}'

# encerrar activity
curl -X POST http://127.0.0.1:4477/activity \
  -d '{"id":"deploy","done":true}'
```

CLI incluído:

```bash
tools/knobler notify "Título" ["corpo"] ["app"]
tools/knobler activity <id> <0-100|-> "Título" ["detalhe"]
tools/knobler done <id>
tools/knobler ask "Pergunta?" "Opção A" "Opção B"
tools/knobler agent-request publish '{"id":"perm-1","agent":"claude","kind":"permission","title":"Permissão","summary":"Ler README","source":"terminal","actions":[{"action":"allow"},{"action":"deny"}]}'
tools/knobler agent-request wait perm-1
tools/knobler codex check     # o app-server instalado expõe as aprovações?
tools/knobler codex bridge    # app-server com as aprovações espelhadas no NOB
```

## Referência dos endpoints

### `POST /notify`

Publica um card transitório. `title` é obrigatório e não pode ser vazio.

```json
{
  "title": "Deploy finalizado",
  "body": "em produção",
  "app": "Terminal",
  "supacodeWorktree": "/projetos/app",
  "supacodeTab": "deploy"
}
```

`supacodeWorktree` e `supacodeTab` são opcionais e permitem focar uma sessão
do Supacode quando o card for clicado. Sucesso retorna `{"ok":true}`; JSON
inválido ou sem título retorna `400`.

### `POST /activity`

Cria ou atualiza uma activity por `id`. Se `id` for omitido, usa `default`.

```json
{
  "id": "deploy",
  "title": "Deploy",
  "detail": "rsync",
  "progress": 0.4
}
```

`progress` é opcional e pode estar em `0…1` ou `0…100`; valores são limitados
ao intervalo válido. Para atividade indeterminada, omita o campo ou use `null`.
Para remover:

```json
{"id":"deploy","done":true}
```

Uma activity expira após 30 minutos sem atualização. A activity mais
recentemente atualizada é a exibida.

### `POST /mirror`

Liga o espelho no notch do monitor sob o ponteiro ou desliga o espelho em todos
os monitores.

```json
{"on":true}
{"on":false}
```

Sem corpo, `on` assume `true`.

### `POST /ask`

Cria uma pergunta interativa. O formato é compatível com `AskUserQuestion`:

```json
{
  "id": "ask-123",
  "source": "knobler",
  "questions": [
    {
      "question": "Continuar?",
      "header": "Deploy",
      "multiSelect": false,
      "options": [
        {"label":"Sim","description":"Continuar o deploy"},
        {"label":"Não","description":"Parar agora"}
      ]
    }
  ]
}
```

`id` e `questions` não vazios são obrigatórios. Cada pergunta precisa de pelo
menos uma opção com `label`. `source` é opcional e aparece como contexto no
card. O resultado é mostrado no notch e consultado pelo caller via polling.

### `GET /ask/<id>`

Retorna o estado da pergunta:

```json
{"answered":false}
```

Resposta concluída:

```json
{
  "answered": true,
  "answers": {
    "Continuar?": {"labels":["Sim"]}
  }
}
```

Resposta com texto livre usa `text`; esse texto vence os labels da mesma
pergunta. A resposta é consumida na primeira leitura bem-sucedida. Se o card
for cancelado:

```json
{"cancelled":true}
```

Pergunta desconhecida retorna `404`. Perguntas pendentes expiram após 15
minutos.

### `POST /ask/<id>/cancel`

Cancela uma pergunta pendente. A operação é idempotente e retorna
`{"ok":true}` mesmo quando a pergunta já terminou.

### Solicitações de agentes autenticadas

Todas as rotas em `/agent-requests` exigem `Authorization: Bearer <token>`.
O token muda a cada inicialização do app; use o CLI incluído em vez de copiá-lo
para histórico de shell.

`POST /agent-requests` publica uma solicitação. Campos obrigatórios: `id`
(ASCII seguro para URL), `agent` (`claude` ou `codex`), `kind` (`question` ou
`permission`), `title`, `summary`, `source` (`terminal`, `cli` ou `ide`) e
entre uma e oito `actions`. As ações são `allow`, `allowForSession`, `deny`,
`cancel`, ou `option`/`text` com `value`.

```json
{
  "id": "permission-42",
  "agent": "claude",
  "kind": "permission",
  "title": "Ler arquivo",
  "summary": "README.md",
  "source": "terminal",
  "actions": [{"action":"allow"}, {"action":"deny"}]
}
```

`GET /agent-requests/<id>` retorna `{"state":"pending"}` enquanto aguarda.
Depois retorna uma única vez o estado final e `result`; a segunda leitura é
`404`. `POST /agent-requests/<id>/resolve` recebe uma ação no mesmo formato e
aceita apenas uma ação oferecida. `POST /agent-requests/<id>/dismiss` cancela.
Resoluções repetidas são no-op: a primeira ação válida vence.

### Claude `PermissionRequest`

O hook do Claude envia `tool_name`, `tool_input`, `permission_suggestions` e
`session_id` ao endpoint como dados, sem executar o conteúdo recebido. `allow`
autoriza apenas a operação atual. `allowForSession` só está disponível quando
Claude forneceu uma sugestão de allow; o hook muda o destino dessas regras para
`session`, portanto não escreve configurações persistentes. Em falha ou timeout
da API, ele sai com sucesso e sem JSON para manter o prompt nativo do Claude.

### Aprovações do Codex

A ponte `tools/codex-agent-bridge.mjs` traduz os pedidos de aprovação do
`app-server` do Codex para o mesmo endpoint: `allow`/`allowForSession` viram
`accept`/`acceptForSession`, `deny` vira `decline` e `cancel` interrompe o
turno. Emendas de execpolicy e de política de rede não viram botão, porque são
regras persistentes. Sem token, sem API ou sem decisão dentro do prazo, a ponte
não responde e o Codex mostra a aprovação nativa. Detalhes em
[`agent-requests.md`](agent-requests.md).

### `GET /status`

Retorna diagnóstico do app. O schema é deliberadamente extensível; campos
atuais incluem `notches`, `player`, `visualizerTapped`, `dictation`, `ask`,
`micInUse` e `lanMessaging`. Cada entrada de `notches` traz também `focus`: o
identificador da seção que o card aberto está mostrando (`musica`, `atividade`,
`pomodoro`, `shelf`, `espelho`, `mensagens`, `historico`, `nota`, `link`), ou string
vazia quando não há seção em foco.

```bash
curl -sS http://127.0.0.1:4477/status | jq .
```

Use esse endpoint para diagnóstico local, não como contrato de persistência.

## Erros e limites

- `200` com `{"ok":true}` para comandos aceitos.
- `400` para JSON inválido ou campos obrigatórios ausentes.
- `404` para endpoint desconhecido ou Ask inexistente.
- O listener recebe até 64 KiB por requisição.
- Corpos de `/agent-requests` são limitados a 32 KiB e retornam `413` acima
  desse limite; JSON ou campos inválidos retornam `400`, e token ausente ou
  incorreto retorna `401`.
- A API não é exposta na LAN e não deve ser colocada atrás de um proxy sem
  autenticação e controle de origem.

Para problemas, veja [`troubleshooting.md`](troubleshooting.md). Para o fluxo
Ask e o ownership do estado, veja [`architecture.md`](architecture.md).
