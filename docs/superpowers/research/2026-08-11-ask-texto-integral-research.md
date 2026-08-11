# Pesquisa — card de pergunta com texto integral

Spec: `docs/superpowers/specs/2026-08-11-ask-texto-integral-design.md`

Frente externa pulada: a spec não nomeia API, serviço ou dependência externa —
só troca modificadores de `lineLimit` em SwiftUI. Toda a incerteza é local ao
repo. Uma frente interna, um agente.

## Achados

### A1 — A altura do card Ask é estimada aritmeticamente, não medida pelo conteúdo
- Fonte: `Knobler/NotchView.swift:414-417` — `topInset + 46 + options.count*48 + 44`,
  `+34` se multiSelect, `max(…, topInset+200)` se há preview, e `min(height, 500)`.
- Fonte: `Knobler/NotchView.swift:254` — `.frame(width:height:)` aplica esse valor ao card.
- Contradiz a spec: **sim**. A spec diz "o card cresce em altura o quanto for preciso".
  Ele não cresce: a fórmula só conta `options.count` e ignora o comprimento do texto,
  então nem a pergunta inteira nem a descrição expandida movem a altura.
- Pergunta: a fórmula passa a medir o texto real, ou o card ganha altura por
  conteúdo (`fixedSize`/`sizeThatFits`) e a fórmula sai de cena?

### A2 — Conteúdo que passa da altura é clipado em silêncio, sem scroll e sem a janela crescer
- Fonte: `Knobler/NotchView.swift:245-246` — `.compositingGroup().mask(shape)` recorta pela `NotchShape`.
- Fonte: `Knobler/Ask.swift:158` — o único `ScrollView` do Ask é o painel de preview.
- Contradiz a spec: **sim**. A spec previu "sem rolagem e sem teto"; o efeito real de
  aplicar só as duas mudanças de `lineLimit` é texto sumindo sob a máscara.
- Pergunta: aceitar corte silencioso é pior que o `…` de hoje. O que entra no lugar?

### A3 — A janela do notch é fixa em 700×520 e não acompanha o conteúdo
- Fonte: `Knobler/KnoblerApp.swift:1197-1205` — `NSSize(width: 700, height: 520)`, `setFrame`.
- Contradiz a spec: **sim**. Mesmo removendo o `min(height, 500)` de A1, nada além de
  520pt aparece na tela. "Sem teto" exige redimensionar a `NSWindow`.
- Pergunta: a janela passa a ser redimensionada por card (e por display), ou o teto de
  520 vira o limite aceito e a spec cede nesse ponto?

### A4 — O hover já muda conteúdo hoje, mas nunca mudou altura
- Fonte: `Knobler/Ask.swift:36` — `previewText` escolhe o preview pela opção sob o cursor.
- Fonte: `Knobler/Ask.swift:20,145,150-152,202` — `hovered` é `@State private`, sem consumidor externo.
- Contradiz a spec: **parcial**. O estado existe e basta, como a spec diz; o que não
  existe é caminho do `hovered` até `currentSize` em `NotchView.swift:414`. Expandir
  in-place no hover significa **altura que muda com o cursor** — a janela/card teriam
  que reanimar a cada entrada e saída de opção.
- Pergunta: a altura acompanha o hover em tempo real (card pulsa sob o cursor) ou é
  dimensionada uma vez pelo pior caso?

### A5 — Os PNGs do harness já cortam por canvas fixo de 240pt e vão cortar mais
- Fonte: `tools/main.swift:564` — `.frame(width: 560, height: scenario.frameHeight)`;
  default `240` em `tools/main.swift:64`.
- Fonte: `tools/main.swift:316-343` — `ask-simple` e `ask-multiselect` usam o default,
  enquanto o `currentSize` do card já pede ~248/282.
- Precedente: `tools/main.swift:302`, `:394`, `:660` sobem `frameHeight` exatamente por isso.
- Contradiz a spec: **parcial**. A spec conta com esses PNGs para cobrir header e lista;
  eles cobrem, mas cortados. Corrigível subindo `frameHeight` nos dois cenários.
- Pergunta: sobe o `frameHeight` dos cenários Ask nesta mudança?

### A6 — `tools/askcheck.swift` não cobre layout; nenhum gate falharia
- Fonte: `tools/askcheck.swift:80-268` — valida só o reducer: FIFO, dedupe por ID,
  reset de página/seleção/texto, toggle, texto vencendo labels, no-op inválido,
  paginação, resolve.
- Contradiz a spec: **não**. Confirma o que a spec já dizia: nenhuma entrada nova em
  `tools/check.sh` é necessária, e a validação é visual.

### A7 — O card Ask é renderizado num único lugar
- Fonte: `Knobler/NotchView.swift:678-681` (`questionCard`), com `.frame(width: currentSize.width - 40)`.
- Contradiz a spec: **não**. Blast radius de uma view só; nenhum outro consumidor de `hovered`.

## Fila do grill

Ordenada por dependência.

1. A3 — o teto de 520pt da janela cede ou a spec cede? (trava A1, A2, A4)
2. A1 — a altura passa a medir o texto real, ou o card dimensiona por conteúdo? (trava A2, A4)
3. A2 — o que acontece quando o texto passa do que cabe: corte, rolagem ou janela maior?
4. A4 — a altura acompanha o hover em tempo real ou é fixada pelo pior caso?
5. A5 — sobe o `frameHeight` de `ask-simple`/`ask-multiselect` nesta mudança?
