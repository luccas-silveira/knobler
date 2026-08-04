# Fases de execução do piloto

- map: ../map.md
- label: wayfinder:grilling
- status: open
- assignee: —
- blocked-by: 007, 008, 010 (003, 004, 005 e 006 fechados)

## Question

Com tudo decidido, fatiar a implementação em fases que caibam numa sessão cada,
na ordem em que uma deixa pronta a peça que a próxima usa. Cada fase vira ticket
próprio (graduação da névoa), com gate em `tools/check.sh`, doc e entrada no
`CHANGELOG.md`.

Fatia provável, a confirmar:

1. A declaração da peça e o registro compilando, sem ninguém usando ainda
   (mesmo padrão da Fase 1 dos webhooks: existe, não aparece na tela).
2. O estado de instalado mais a migração de quem já usa.
3. A cobaia convertida — nascimento condicional e as superfícies saindo da lista.
4. A tela mínima de instalar/desinstalar.
5. Docs, imagens e release.

Decidir também: **o que roda no gate novo** (qual harness `tools/*check*.swift`
prova que peça desligada não nasce), e como testar isso sem XCTest e sem abrir
o app.
