# 004 — Aplicar o conserto e travar o gate

Map: [O knob cortado ao meio](../map-corte-do-knob.md)
Type: `fix`
Status: aberto
Assignee: —
Blocked by: 003

## Pergunta

O conserto escolhido está aplicado e existe um gate hermético que falha se o defeito
voltar?

Duas registrações manuais que sessões anteriores já esqueceram neste repositório, e que
fazem o trabalho sumir da CI sem dar erro:

- Check novo exige linha nova em `tools/check.sh`. Sem ela a CI não enxerga o gate.
- Arquivo `.swift` novo que a `NotchView` use exige entrada manual na lista de
  `tools/snapshot.sh`.

Harness escrito como `main.swift` não aceita `-parse-as-library`.

O gate precisa falhar com o código de antes do conserto. Um check que passa nos dois
estados não está checando nada — rode-o contra o `git stash` do conserto antes de fechar
este ticket.

Fechar só depois de `./tools/check.sh` inteiro verde, com a saída citada na
`## Resolução`.
