# Perguntas do Claude Code no notch (v0.9) — Design

Data: 2026-07-17 · Status: aprovado em grill

## Objetivo

Quando o Claude Code chama `AskUserQuestion` (grills, brainstorms, plans), a
pergunta aparece como card interativo no notch do Knobler: opções como botões,
texto livre por teclado ou ditado, previews ASCII renderizados. A resposta
volta ao Claude sem tocar no terminal.

## Decisões (com o porquê)

| Decisão | Escolha | Porquê |
|---|---|---|
| Transporte | **Hook PreToolUse global** em `~/.claude/settings.json` interceptando `AskUserQuestion` | Cobre toda sessão/skill sem editar nenhum skill; determinístico; no-op em ms quando o Knobler não roda |
| Retorno da resposta | `permissionDecision: deny` com a resposta no `reason` | Único canal que devolve conteúdo ao modelo a partir de um PreToolUse hook |
| Fallback | Dismiss manual (✕/Esc) manda pro terminal na hora; timeout de segurança 10 min | Usuário decide onde responder; sem corrida contra relógio; sessão esquecida não trava |
| Texto livre | `TextField` real + ditado (⌥ direita) | Janela `nonactivatingPanel` pode virar key sem ativar o app — terminal continua ativo; motor Parakeet já existe |
| Previews ASCII | Layout split: opções à esquerda, preview da opção sob hover à direita, mono + scroll | Igual ao CLI; card só alarga quando há preview |
| Multi-pergunta / multi-select | Paginado (indicador 1/N, envio único no fim); multi-select = toggles + Confirmar | Cobre 100% das chamadas; nada cai no terminal por limitação |
| Prioridade no notch | **Topo absoluto** (pergunta > ditado > notificação > HUD) | É a única coisa bloqueando um processo do usuário; notificações enfileiram |
| Aviso de chegada | Animação de destaque + som curto discreto (uma vez) | Perceptível sem irritar; Claude esperando em silêncio custa minutos |
| Multi-monitor / concorrência | Fan-out a todos os monitores, primeira resposta vence; perguntas concorrentes em fila FIFO | Convenção existente das notificações |

## Fluxo

1. Claude chama `AskUserQuestion` → hook PreToolUse recebe `tool_input` no
   stdin, gera `id` único, faz `POST /ask` no Knobler (`127.0.0.1:4477`).
   - Knobler fora do ar → curl falha → hook sai sem output → pergunta segue
     no terminal como hoje.
2. Card desliza do notch (animação + som), modo `question`, em todos os
   monitores. Notch mostra a 1ª pergunta: título, botões de opção (label +
   description), campo "Outra resposta…" no rodapé.
3. Hook faz polling `GET /ask/<id>` a cada ~300ms (timeout total 10 min —
   `timeout: 600` na config do hook).
4. Usuário responde:
   - **Clique** numa opção (single-select) → responde e avança página/envia.
   - **Multi-select**: toggles + botão Confirmar.
   - **Texto livre**: clique no campo → janela vira key temporariamente →
     digita → Enter. Ou segura ⌥ direita e dita — transcrição cai no campo
     (nível de áudio renderiza dentro do card, não na pílula).
   - **Previews**: se alguma opção tem `preview`, card usa layout split;
     hover na opção troca o preview à direita.
   - Chamada com N perguntas: responder avança (1/N → 2/N…); última envia tudo.
5. `GET /ask/<id>` retorna `{answered:true, answers:{…}}` → hook devolve
   `permissionDecision: deny` com reason estruturado:
   `Usuário respondeu via Knobler: "<pergunta>" = "<label>". Prossiga com
   essas respostas; não repita a pergunta.` → Claude continua.
6. **Cancelamento**: ✕ no card ou Esc → `{cancelled:true}` → hook sai sem
   output → pergunta aparece no terminal. Timeout de 10 min → hook faz
   `POST /ask/<id>/cancel` (remove o card) e sai sem output.

## Componentes

- **`~/.claude/hooks/knobler-ask.sh`** (novo, fora do repo do Knobler; versionado
  em `tools/claude-hook/` e instalado por script) — lê stdin, POST /ask,
  polling, monta o JSON de decisão. Bash + curl + jq, sem dependências novas.
- **`NotchAPIServer.swift`** — três rotas novas, mesmo modelo request-response:
  - `POST /ask` `{id, questions:[{question, header, multiSelect, options:[{label, description, preview?}]}]}` → `{"ok":true}`; enfileira (FIFO) se já há pergunta ativa.
  - `GET /ask/<id>` → `{answered:false}` | `{answered:true, answers:{"<question>":{labels:[…], text?}}}` | `{cancelled:true}`. Respostas retidas em dicionário com TTL (15 min) e removidas após a 1ª leitura.
  - `POST /ask/<id>/cancel` → remove card/fila (chamado pelo hook no timeout).
- **`NotchViewModel`** — `case question` no enum `Mode` (topo da precedência),
  `@Published var activeQuestion`, fila FIFO própria, sem auto-dismiss.
- **`NotchView`** — branch `questionCard`: título + header chip, botões de
  opção, paginação (dots 1/N), toggles + Confirmar quando `multiSelect`,
  layout split com `preview` em mono (scroll), campo de texto no rodapé,
  ✕ no canto. Entrada nova em `currentSize` (altura por nº de opções; largura
  maior só com preview).
- **`NotchWindow`** — `canBecomeKey` condicional: `true` apenas enquanto o
  campo de texto do card está focado; reverte a `false` quando o card some
  (**crítico**: senão o notch passa a roubar teclado).
- **`Dictation.swift`** — quando há pergunta ativa, `.inserting` roteia a
  transcrição para o campo do card em vez de pasteboard+⌘V no app frontmost.
- **`KnoblerApp.swift`** — wiring `apiServer.onAsk` → fan-out aos view models;
  callback de resposta/cancelamento → armazena no server; som de chegada
  (`NSSound`); sincronização entre monitores (primeira resposta vence).
- **`GET /status`** — ganha `ask: {pending, queued}` p/ diagnóstico.
- **`tools/knobler`** — subcomando `ask` p/ teste manual via CLI (envia
  pergunta de exemplo e imprime a resposta).

## Permissões e dependências

- Nenhuma permissão nova (mic e Acessibilidade já concedidas pelo v0.8).
- Nenhuma dependência nova no app. Hook usa `jq` (já presente na máquina).
- Instalação do hook: script `tools/claude-hook/install.sh` adiciona o bloco
  em `~/.claude/settings.json` (idempotente, com `timeout: 600`).

## Tratamento de erro

- Knobler fora do ar / porta ocupada → hook sai limpo → terminal (comportamento atual).
- Hook morre no meio (kill, crash da sessão) → card órfão expira pelo TTL de
  15 min do servidor; ✕ manual também remove.
- Resposta enviada após o hook desistir → descartada pelo TTL; sem efeito.
- Payload `/ask` malformado → 400, hook sai sem output → terminal.

## Fora do escopo (v1)

Markdown/cores nos previews (texto mono puro), toggle global de pausa da
interceptação, respostas por hotkey numérica, histórico de perguntas, edição
da resposta após envio, suporte a outras ferramentas além de `AskUserQuestion`.

## Validação

- Snapshot harness: estados `pergunta simples`, `multi-select`, `com preview
  (split)`, `paginada 2/3`, `campo de texto focado`.
- Unit: parse do payload `/ask`, ciclo answered/cancelled/TTL no servidor.
- E2E real: sessão Claude Code com o hook instalado → `/grill-me` → responder
  botão, multi-select, texto digitado e texto ditado; conferir que o Claude
  recebe e não repete a pergunta; ✕ → pergunta cai no terminal.
- `curl` manual: `tools/knobler ask` de dois terminais → fila FIFO respeitada.
- Regressão: com Knobler fechado, `AskUserQuestion` funciona como hoje.
