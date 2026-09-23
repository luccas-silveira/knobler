# Pesquisa — bloquear teclado

Spec: `docs/superpowers/specs/2026-09-23-bloquear-teclado-design.md`

## Achados

### A1 — Com um campo de senha focado, o macOS entrega as teclas por fora de qualquer event tap
- Fonte: Apple, `EnableSecureEventInput` (Carbon, TN2150); comportamento conhecido de
  Karabiner/BetterTouchTool com "Secure Keyboard Entry".
- Contradiz a spec: parcial ("todo keyDown é descartado")
- Pergunta: se um campo de senha (ou o Terminal com entrada segura) estiver focado, a
  limpeza digita nele. Checar `IsSecureEventInputEnabled()` e recusar/avisar?

### A2 — O notch não tem hoje nenhum aviso de Acessibilidade faltando
- Fonte: `Knobler/KnoblerApp.swift:1401-1448` (só badge ⚠ e item no menu);
  `VolumeHUD.swift:171` só loga.
- Contradiz a spec: parcial ("notch avisa")
- Pergunta: aviso sem Acessibilidade vai pelo notch (card novo) ou pelo caminho que já
  existe (abrir Ajustes › Permissões)?

### A3 — Estado novo de notch obriga a cobrir 4 `switch` sobre o modo
- Fonte: `NotchPresentation.swift:5-41,144-169,236`; `NotchView.swift:~150-214,847,927`.
- Contradiz a spec: não. Template de card: `.update` (`NotchPresentation.swift:165`).

### A4 — Padrões a copiar
- Singleton: `QuickNote.swift:30-31` + `@ObservedObject` em `NotchView.swift:19`.
- Menu: seção "Ferramentas", `KnoblerApp.swift:1482-1494`, toggle com `.state` (:1486).
- API: `NotchAPIServer.swift:300-314` (`/mirror`) + wiring `KnoblerApp.swift:649`;
  doc em `docs/local-api.md:91-103`; lista de uso `NotchAPIServer.swift:410`.
- Tap: `VolumeHUD.swift:154-183` (refcon, timeout reativa).
- Snapshot: `tools/main.swift:274` (cenário), reset do singleton em :762.
- Contradiz a spec: não.

## Fila do grill

1. A1 — campo de senha focado
2. A2 — aviso sem Acessibilidade
