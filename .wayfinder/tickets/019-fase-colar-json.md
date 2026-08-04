# Fase 3 — colar JSON de exemplo

- map: ../map.md
- label: wayfinder:task
- status: open
- assignee: —
- blocked-by: 018

## Question

008: um clique lendo `NSPasteboard`, sem `TextEditor`. JSON inválido = aviso
inline persistente com os primeiros ~80 caracteres lidos + "Colar de novo" /
"Descartar". Exemplo é **só local** (`@State`, some ao fechar): o relay nunca
sabe, então `lastPayloadAt`/`payloadCount` seguem significando POST de verdade.
Faixa persistente marca a árvore como exemplo; payload real vence e troca
sozinho. Botão no estado vazio do editor e no passo Primeiro envio.
