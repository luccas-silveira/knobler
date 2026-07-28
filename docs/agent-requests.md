# Solicitações de agentes no notch

Perguntas e pedidos de permissão do Claude Code e do Codex aparecem como card
no notch, sem tirar a interação do terminal. Quem responder primeiro — notch ou
terminal — vence; o outro lado vira no-op.

## O que o notch faz e o que não faz

- Mostra dados: ferramenta, comando, diretório, motivo, diff, permissões.
- Devolve **uma decisão** pela API local autenticada.
- **Não** executa comando, **não** aplica diff, **não** grava permissão
  persistente e **não** lê a tela do terminal.
- Sem API, sem token, payload estranho ou tempo esgotado: nenhuma decisão sai
  do notch e o prompt nativo do agente continua valendo.

## Claude Code

Dois hooks, instalados por `tools/claude-hook/install.sh`:

| Hook | Card |
|---|---|
| `AskUserQuestion` | pergunta com opções (ver [`ask.md`](ask.md)) |
| `PermissionRequest` | permissão de ferramenta, com **Permitir**, **Permitir na sessão** e **Negar** |

**Permitir na sessão** só aparece quando o Claude sugeriu uma regra de allow, e
o hook reescreve o destino dessas regras para `session` — nada é gravado em
disco. Checagem: `bash tools/claude-hook/test.sh`.

## Codex

O Codex não tem hook de aprovação: os hooks instalados cobrem ciclo de vida e
ferramentas. As aprovações vivem no `app-server` experimental, que emite três
pedidos servidor → cliente:

- `item/commandExecution/requestApproval`
- `item/fileChange/requestApproval`
- `item/permissions/requestApproval`

`tools/codex-agent-bridge.mjs` sobe o `app-server` e fala JSON-RPC por linhas
com quem o chamou, repassando tudo menos esses três pedidos, que viram card.

```bash
tools/knobler codex check     # os três pedidos existem nesta versão do Codex?
tools/knobler codex bridge    # app-server com as aprovações espelhadas
```

`codex check` gera o schema da build instalada (`codex app-server
generate-json-schema --experimental`) e confere os três métodos. Se faltar
algum, a ponte imprime uma linha de diagnóstico e **não** intercepta nada.

### Mapa de decisões

| Ação no notch | Comando / alteração de arquivo | Permissões |
|---|---|---|
| Permitir | `accept` | perfil pedido, `scope: turn` |
| Permitir na sessão | `acceptForSession` | perfil pedido, `scope: session` |
| Negar | `decline` | perfil vazio, `scope: turn` |
| Cancelar | `cancel` (interrompe o turno) | perfil vazio, `scope: turn` |

As decisões oferecidas saem de `availableDecisions` quando o pedido traz o
campo. Emendas de execpolicy e de política de rede ficam de fora de propósito:
são regras persistentes, não uma aprovação pontual — decida essas no Codex.

Checagem: `node tools/codex-agent-bridge-check.mjs` roda a ponte contra uma API
falsa com pedidos gravados em `tools/fixtures/codex-approval-requests.jsonl`,
confere as respostas das quatro decisões nos três schemas, o fallback com a API
fora e que o comando da fixture nunca foi executado.

### Superfícies suportadas

Verificado em `codex-cli 0.145.0` por `node tools/codex-integration-check.mjs`:

| Superfície | Espelha no notch? | Como |
|---|---|---|
| Cliente app-server iniciado pela ponte | sim | `tools/knobler codex bridge` no lugar de `codex app-server --listen stdio://` |
| TUI (`codex`) já aberto | não | a sessão não é anexável; aprovação nativa no terminal |
| Desktop app e extensão de IDE | não | falam com o daemon do `app-server`, não com o stdio da ponte |

O daemon (`codex app-server daemon`, `codex remote-control`) exige a instalação
standalone do instalador oficial — num Codex de Homebrew ele nem sobe:

```
Error: managed standalone Codex install not found at ~/.codex/packages/standalone/current/codex
```

Enquanto for assim, app e IDE ficam com a aprovação nativa e o notch não
interfere. O gate reporta o estado a cada execução, então basta rodá-lo de novo
depois de trocar a instalação.

### O que o gate cobre

```bash
node tools/codex-integration-check.mjs
```

Versão da CLI, capacidade dos três pedidos, um `initialize` real atravessando a
ponte sem publicar card (nenhuma aprovação falsa), a troca de aprovação por
fixture e o estado do daemon. Ele **não** inicia turno: nada de token gasto e
nenhum comando do agente executado. O turno ao vivo é manual:

```bash
codex --ask-for-approval on-request --sandbox read-only "liste os arquivos daqui"
```

### Limitações

- O protocolo do `app-server` é experimental: revalide com `knobler codex
  check` e com o gate depois de atualizar o Codex.
- Uma sessão já aberta no TUI, no app ou na extensão de IDE **não** é anexada à
  ponte — só o que passa por `knobler codex bridge` é espelhado.
- Sem interceptação (capability ausente, API fora, timeout), o texto que aparece
  é uma linha em stderr começando com `codex bridge:` — o Codex segue normal.

## Segurança

- Transporte em `127.0.0.1`; `/agent-requests` exige `Authorization: Bearer`
  com o token efêmero de sessão (`0600`).
- Comandos, caminhos e diffs trafegam como texto e são exibidos como texto.
- Corpo limitado a 32 KiB; ação fora das oferecidas é rejeitada pelo app.
- Expiração e cancelamento nunca viram `allow`.

Contrato dos endpoints em [`local-api.md`](local-api.md).
