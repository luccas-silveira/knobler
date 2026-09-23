# Pesquisa — Quick Actions + seção Cor

Spec: `docs/superpowers/specs/2026-09-23-quick-actions-design.md`

Frente externa pulada: nenhuma API externa nova; `NSColorSampler` já em uso.

## Achados

### A1 — Seção oculta nunca recebe foco
- Fonte: `Knobler/NotchViewModel.swift:408` (`guard secoes.contains`), `:401` (recálculo devolve foco à 1ª seção), `:617` (`focoPendente` eterno)
- Contradiz a spec: sim
- Pergunta: abrir seção oculta pelo atalho exige um foco "fora da faixa" que sobreviva ao recálculo — como sair dele (swipe, fechar card)?

### A2 — Swipe não funciona com foco fora da faixa
- Fonte: `Knobler/NotchViewModel.swift:430` (`focarVizinho` usa `firstIndex`)
- Contradiz a spec: parcial
- Pergunta: estando numa seção oculta, o swipe volta pro Quick Actions ou não faz nada?

### A3 — Foco memorizado gravaria seção oculta
- Fonte: `Knobler/NotchViewModel.swift:362`
- Contradiz a spec: parcial
- Pergunta: reabrir o card deve voltar à seção oculta ou ao Quick Actions?

### A4 — Seção sem conteúdo some da barra
- Fonte: `Knobler/NotchViewModel.swift:287-310`, `NotchSectionOrder.swift:117-119`
- Contradiz a spec: não (resolve com `hasContent: true` fixo, como `.anotacao`)

### A5 — Conta-gotas também é usado pela Anotação
- Fonte: `Knobler/AnnotationDeckView.swift:134`, `Knobler/ColorPicker.swift:24`
- Contradiz a spec: parcial
- Pergunta: cor escolhida pra caneta da anotação entra no histórico?

### A6 — Reuso disponível
- `titulo`/`simbolo` (`NotchSectionOrder.swift:19,39`), `sanear` (`:154`), molde de persistência em `AppSettings.swift:175-206,337-342`, `desinstaladas()` (`Plugin.swift:581`), `focar`/`pedirFoco` (`NotchViewModel.swift:407,604`), swatch do `DeckItem` (`AnnotationDeckView.swift:125-143`).

### A7 — Blast radius
- Switches: `NotchSectionOrder.swift:20,40`, `NotchPresentation.swift:234-262` (altura), `NotchView.swift:868-891`; `padrao` (`:72`) e `sectionordercheck.swift:205,213`; cenários em `tools/main.swift`; arquivos novos em `tools/notchview-fontes.txt`; `docs/architecture.md:141-170` precisa registrar foco em seção oculta.

## Fila do grill

1. A1 — como entra/sai de seção oculta (trava A2, A3)
2. A2 — swipe numa seção oculta
3. A3 — foco memorizado
4. A5 — histórico inclui a Anotação?
