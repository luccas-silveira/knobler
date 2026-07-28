# Instruções para agentes

App macOS nativo (AppKit + SwiftUI) que transforma o notch num Dynamic Island.
Roda como agente de UI (`LSUIElement`).

As instruções completas estão em [`CLAUDE.md`](CLAUDE.md) — leia esse arquivo.
O que segue é o mínimo para não quebrar nada.

## Regras que não se negociam

- **Nunca edite `Knobler.xcodeproj`**: é gerado por XcodeGen a partir de
  `project.yml` e a edição some no próximo `xcodegen generate`.
- **Nunca edite `MARKETING_VERSION` nem crie tag na mão**: `tools/release.sh` é
  o único escritor de versão. Escreva a mudança em `## [Unreleased]` do
  `CHANGELOG.md`.
- Comentários e strings de UI em **pt-BR**.
- Simplificação deliberada leva um comentário `// ponytail:` explicando o teto.

## Fluxo

```bash
xcodegen generate     # só após mexer em project.yml ou adicionar/remover arquivo
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
./tools/check.sh      # todos os self-checks — é o que a CI roda
./tools/snapshot.sh   # renderiza a NotchView em Snapshots/*.png; olhe os PNGs
```

Mudou UI? Rode o snapshot e **olhe** as imagens. Views que dependem de `NSView`
real (`TextField`, `ProgressView`, `NSWorkspace.icon`) não renderizam offscreen —
viram o ícone de "proibido". Detalhes e a lista completa em `CLAUDE.md`.

## Onde as coisas estão

| Preciso de | Está em |
|---|---|
| Como o app é composto | `docs/architecture.md` |
| Contrato da API local | `docs/local-api.md` |
| Setup, checks, release | `docs/development.md` |
| Decisões de design | `docs/superpowers/specs/` |
| Estado da última sessão | `HANDOFF.md` |
