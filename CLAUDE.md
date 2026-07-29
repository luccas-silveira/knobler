# Knobler — instruções do projeto

App macOS nativo (AppKit + SwiftUI) que transforma o notch num Dynamic Island:
mídia do Spotify, ditado, Pomodoro, notificações e uma API HTTP local. Roda como
agente (`LSUIElement`). O deployment target é **macOS 14.2**; a máquina de
desenvolvimento roda macOS 26 Tahoe, então o `glassEffect` / Liquid Glass é uma
opção — mas **não** está em uso hoje (zero ocorrências no código). Usar exige
guarda `if #available(macOS 26, *)` com fallback pro target.

## Build & run

Projeto **gerado por XcodeGen** a partir de `project.yml`. O `.xcodeproj` é um
artefato.

```bash
xcodegen generate                                   # só após mudar project.yml ou adicionar/remover arquivos
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

⚠️ **Nunca edite `Knobler.xcodeproj` à mão** — a mudança some no próximo
`xcodegen generate`. Alvos, dependências e settings vivem em `project.yml`.

## Versionamento

**SemVer 2.0.0**, uma versão canônica só (a tag `vX.Y.Z`). Regras completas em
`VERSIONING.md`. Pré-1.0: **MINOR** = feature, **PATCH** = fix, **MAJOR** travado
em 0. **Não** existe mais "vN de sessão" — HANDOFF/MEMORY citam a versão de
release. **Nunca** edite `MARKETING_VERSION` à mão nem crie tag manual: o
`tools/release.sh` é o único escritor. Escreva as mudanças em `## [Unreleased]` do
`CHANGELOG.md` conforme desenvolve; publique com `./tools/release.sh <patch|minor|major>`.

## Loop de snapshot (feedback visual)

`tools/snapshot.sh` compila a `NotchView` isolada com `swiftc` e renderiza cada
estado em `Snapshots/*.png` — é o jeito de "ver" a UI sem abrir o app.

```bash
./tools/snapshot.sh          # regenera Snapshots/*.png; leia os PNGs pra validar
```

⚠️ A lista de arquivos em `tools/snapshot.sh` é **manual**. Ao adicionar um
`.swift` novo em `Knobler/` que a `NotchView` use, adicione-o lá também.

⚠️ **Quatro PNGs não são determinísticos** e mudam de hash a cada rodada mesmo
sem mudança nenhuma de código: `closed-music`, `closed-music-external`,
`foco-atividade-indeterminada` e `update-installing` (visualizador animado,
barra de progresso). Neles o snapshot é inspeção visual, não detector de
regressão — não gaste tempo investigando o diff. O harness gera 53 PNGs no
total; os outros 49 são byte-idênticos entre rodadas.

⚠️ **Qualquer view que dependa de um `NSView` real (janela/WindowServer de
verdade) não renderiza via `ImageRenderer` offscreen** — vira o ícone de
"proibido" no lugar do conteúdo. Casos confirmados até agora:
`NavigationSplitView`/`HSplitView` (repro isolado), `TextField` (o rodapé do
`AskCardView` — por isso `ask-simple.png`/`ask-multiselect.png` cortam antes
da barra do campo de texto), e `NSWorkspace.icon(forFile:)`/`QLThumbnailGenerator`
(`ShelfThumbnailDragView` — por isso a imagem da prateleira nos docs
(`docs/images/expanded-shelf.png`) é capturada no app rodando de verdade: o
`foco-shelf.png` do harness sai com o ícone de "proibido" no lugar das
miniaturas), e `ScrollView`
(`NSScrollView` por baixo) — sintoma diferente dos outros: não vira o ícone
de "proibido", o conteúdo simplesmente não aparece (área inteira preta),
mesmo com `LazyVStack` trocado por `VStack` simples. Confirmado na
`HistoryListView` (seção de histórico) e na **thread** da `MessagesView` (a
conversa aberta) — por isso a seção de histórico não entra populada no harness,
só vazia (`foco-historico-vazio.png`, que não usa `ScrollView`), e não há
cenário de conversa aberta. A **lista de peers** da `MessagesView` não usa
`ScrollView` e renderiza normalmente: `messages-online.png` é gerado pelo
harness e vale como detector de regressão. A seção `espelho`
também fica de fora: precisa de câmera real. Ao adicionar
cenário novo ao harness, desconfie de qualquer subview que envolva um
desses. Por isso `settings-*.png`
(7 painéis de Ajustes) e `mapping-editor.png` **não** são gerados por
`tools/snapshot.sh` — são
mantidos à mão — junto com `nota-placeholder.png` (campo da nota rápida: é um
`TextEditor`, logo um `ScrollView`; a receita de captura está num comentário em
`docs/nota-rapida.md`). Pros painéis:
rode `Knobler.app/Contents/MacOS/Knobler --ajustes=<painel>`
(painéis: `geral notch ditado pomodoro lembretes descanso webhooks
mensagens`), tire o screenshot da janela real e salve em `docs/images/`
(as imagens usadas pelos docs de usuário ficam ali, não em `Snapshots/` —
`Snapshots/` é gitignored e serve só de QA visual local). `screencapture -l<windowID>`
captura a sombra própria do macOS (PNG com alpha) — corte pra
`802x554+55+37` antes de salvar (bordas reais da janela, sem halo).

## MCP servers (ativos após reiniciar a sessão)

Registrados em `.mcp.json` (escopo de projeto):

- **XcodeBuildMCP** — build/test/simulador com saída de compilador em JSON
  estruturado. Use as ferramentas dele para o loop escrever→compilar→ler
  erro→corrigir em vez de invocar `xcodebuild` cru.
- **xcode** (`xcrun mcpbridge`, MCP oficial da Apple) — `DocumentationSearch`
  (docs Apple + WWDC) e `ExecuteSnippet` (REPL Swift). **Verifique símbolos de
  API da Apple aqui antes de escrever**, em vez de confiar na memória ou no
  WebSearch — evita alucinar API depreciada.

## Convenções

- Comentários e strings de UI em **pt-BR** (ver `project.yml` e o código).
- Marque simplificações deliberadas com `// ponytail:`.
