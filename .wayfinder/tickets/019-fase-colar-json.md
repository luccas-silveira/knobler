# Fase 3 — colar JSON de exemplo

- map: ../map.md
- label: wayfinder:task
- status: closed
- assignee: sessão 2026-08-04 (019)
- blocked-by: 018

## Question

008: um clique lendo `NSPasteboard`, sem `TextEditor`. JSON inválido = aviso
inline persistente com os primeiros ~80 caracteres lidos + "Colar de novo" /
"Descartar". Exemplo é **só local** (`@State`, some ao fechar): o relay nunca
sabe, então `lastPayloadAt`/`payloadCount` seguem significando POST de verdade.
Faixa persistente marca a árvore como exemplo; payload real vence e troca
sozinho. Botão no estado vazio do editor e no passo Primeiro envio.

## Resolução — 2026-08-04

Lógica pura em `Knobler/WebhookExemplo.swift`: `ExemploColado.avaliar` (lê o
texto, exige objeto ou array — fragmento solto como `42` não vira árvore),
`ExemploColado.trecho` (colapsa espaço e corta em 80 + reticências, senão o HTML
indentado vira parágrafo no aviso) e `FonteDaArvore` com a faixa por estado mais
`comPayloadReal`, que é a precedência de 008 num lugar só. Gate
`tools/exemplocheck.swift` em `tools/check.sh` — 33 checks.

UI: `MappingEditorView` ganhou o botão no estado vazio, a faixa persistente com
"Descartar" (só o exemplo se descarta) e o aviso inline com "Colar de novo" /
"Descartar"; JSON inválido não toca na árvore anterior.
`WebhookAssistantView` ganhou o botão no passo Primeiro envio, e `podeContinuar`
passa a aceitar exemplo colado — o exemplo viaja pro passo Mapa pelo parâmetro
`exemplo:` do editor. Nada sobe pro relay.

Dois desvios de 008:
- O editor **não tinha polling** (só o botão "Recarregar"); ganhou o mesmo laço
  de 2s do assistente, senão "o real troca sozinho" não aconteceria com o
  editor aberto direto num perfil.
- Colar **não** dispara o auto-mapeamento ainda: 005 é a Fase 4 (020). O ponto
  de chamada está marcado com `// ponytail:` em `colarExemplo()`.

Build Debug ok, `./tools/check.sh` 33 ok, `./tools/snapshot.sh` ok. Não validado
clicando no app rodando (abrir `--ajustes=webhooks` sobe um segundo notch na
máquina do usuário).
