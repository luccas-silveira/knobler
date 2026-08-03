# Wayfinder: Anotação de tela completa

## Destination

Chegar a uma especificação implementável para um modo de anotação sobre a tela inteira do Knobler, inspirado no DemoPro: desenho livre, setas, formas, texto, laser/destaque, borracha, desfazer, limpar, cores, opacidade, atalhos e suporte a múltiplos monitores.

## Notes

- App nativo macOS 14.2, AppKit + SwiftUI, com uma janela por monitor.
- Atalho principal decidido: **Control direito**, sem Command.
- Paridade de interação com DemoPro: **Pressionar e Segurar** por padrão; modo **Alternar** configurável.
- Consultar `docs/architecture.md`, `CLAUDE.md` e a implementação do `DescansoController` antes de propor novas janelas ou ownership.
- Wayfinding decide arquitetura e comportamento; a implementação começa somente depois que o caminho virar uma spec clara.

## Decisions so far

- Escopo confirmado: overlay de anotação na tela inteira, com o notch como painel de controle/status.
- Modelo de ativação confirmado: Control direito; comportamento deve seguir o DemoPro, com Pressionar e Segurar padrão e Alternar configurável.
- [Overlay de anotação por monitor e captura global](issues/01-overlay-architecture.md) — `AnnotationController` terá uma janela transparente por display, ativada por `CGEventTap`, sem modo quiosque e sem alterar a activation policy.
- [Ativação e atalhos](issues/02-activation-and-hotkeys.md) — Control direito, Pressionar e Segurar padrão, Alternar configurável, Esc/undo/redo/limpar.
- [Canvas e ferramentas](issues/03-canvas-and-tools.md) — Canvas Codable com formas, desenho livre, texto, laser, holofote, borracha e histórico.
- [Multi-monitor e input](issues/04-multi-monitor-input.md) — estado e janela por display, coordenadas locais e reação à mudança de telas.
- [Ciclo de vida e persistência](issues/05-lifecycle-and-persistence.md) — JSON por monitor, backgrounds e auto-fade.
- [Ajustes e controles](issues/06-settings-and-controls.md) — menu da barra e Ajustes › Notch.
- [Validação e handoff](issues/07-validation-and-handoff.md) — 21 gates verdes; teste visual interativo ficou como validação manual.

## Not yet specified

- Como o overlay captura mouse/teclado sem bloquear a aplicação apresentada.
- Modelo de dados/renderização, seleção de objetos e undo/redo.
- Paridade exata de ferramentas, estilos, texto, laser e animações.
- Persistência, auto-fade e comportamento ao trocar de monitor ou sair do app.
- Como configurar atalhos e controlar a anotação pelo notch, menu e eventualmente Stream Deck.
- Estratégia de testes, snapshots e validação visual com janelas reais.

## Out of scope

- Captura, gravação ou transmissão da tela: o DemoPro apenas desenha como overlay.
- Editor de slides, OCR ou colaboração remota nesta iniciativa.
