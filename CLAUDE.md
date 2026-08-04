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

O build local assina com a identidade `Knobler Local Signing`
(`./tools/make-signing-cert.sh`, uma vez por máquina). Só compilar sem ela:
acrescente `CODE_SIGNING_ALLOWED=NO` (é o que a CI faz).

## Checks

Não há XCTest. Cada área tem um harness `tools/*check*.swift` (ou `.mjs`) que
compila só os arquivos que toca e roda asserções. `tools/check.sh` é a **lista
canônica** — é o que a CI executa.

```bash
./tools/check.sh                  # todos os gates herméticos
./tools/check.sh --com-ambiente   # + gate do Codex (exige a CLI)
```

Gate isolado: a linha de compilação está no cabeçalho de cada
`tools/*check*.swift`, por exemplo

```bash
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/NotchSectionOrder.swift tools/sectionordercheck.swift \
  -o /tmp/sectionordercheck && /tmp/sectionordercheck
```

Harness escrito como `main.swift` **não** aceita `-parse-as-library`. Check novo
= entrada nova em `tools/check.sh`, senão a CI não o vê. `jq` e `node` são
pré-requisitos (`brew install jq node`).

## Onde as coisas estão

| Preciso de | Está em |
|---|---|
| Como o app é composto, ownership de estado | `docs/architecture.md` |
| Contrato da API local (127.0.0.1:4477) | `docs/local-api.md` |
| Setup, checks, release | `docs/development.md` |
| Decisões de design | `docs/superpowers/specs/` |
| Estado da última sessão | `HANDOFF.md` |

`AppDelegate` (`Knobler/KnoblerApp.swift`) só compõe serviços e cria uma
`NotchWindow`/`NotchViewModel` por display — regra de domínio nova não mora lá.
Stores que precisam vencer uma vez só (`AskStore`, `NotificationHistory`,
`QuickNote`) são singletons injetados em todas as janelas: **não** crie um por
monitor.

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
regressão — não gaste tempo investigando o diff. O harness gera 55 PNGs no
total; os outros 51 são byte-idênticos entre rodadas.

⚠️ **Qualquer view que dependa de um `NSView` real (janela/WindowServer de
verdade) não renderiza via `ImageRenderer` offscreen** — vira o ícone de
"proibido" no lugar do conteúdo. Casos confirmados até agora:
`NavigationSplitView`/`HSplitView` (repro isolado), `TextField` (o rodapé do
`AskCardView` — por isso `ask-simple.png`/`ask-multiselect.png` cortam antes
da barra do campo de texto), `WKWebView` (a seção Link — o preview de site não tem PNG no harness),
e `NSWorkspace.icon(forFile:)`/`QLThumbnailGenerator`
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
(8 painéis de Ajustes) e `mapping-editor.png` **não** são gerados por
`tools/snapshot.sh` — são
mantidos à mão — junto com `nota-placeholder.png` (campo da nota rápida: é um
`TextEditor`, logo um `ScrollView`; a receita de captura está num comentário em
`docs/nota-rapida.md`). Pros painéis:
rode `Knobler.app/Contents/MacOS/Knobler --ajustes=<painel>`
(painéis: `geral notch desenho ditado pomodoro lembretes descanso webhooks
mensagens permissoes`), tire o screenshot da janela real e salve em
`docs/images/`
(as imagens usadas pelos docs de usuário ficam ali, não em `Snapshots/` —
`Snapshots/` é gitignored e serve só de QA visual local). `screencapture -l<windowID>`
captura a sombra própria do macOS (PNG com alpha) — corte pra
`802x554+55+37` antes de salvar (bordas reais da janela, sem halo).
⚠️ `-l` **reescala** a janela: num sheet o PNG sai com a janela-mãe em volta, e
coordenada de clique tirada dessa imagem erra o alvo. Pra automatizar clique +
captura use `screencapture -R x,y,w,h` com os bounds de
`CGWindowListCopyWindowInfo` e `sips -z` pra 1x. Clique sintético: SwiftUI só
responde com `CGWarpMouseCursorPosition` **mais** eventos `.mouseMoved` em
passos pequenos antes do down/up. Numa tela
Retina o PNG sai em @2x: o corte equivalente é
`sips -c 1108 1604 --cropOffset 74 110` seguido de `sips -z 554 802`.

`boas-vindas-1.png`/`-2.png` seguem a mesma vala (`NSWindow` real): rode
`Knobler --boas-vindas` — a flag mostra **todos** os passos e não grava a versão
vista, então tirar print não queima o onboarding da máquina. Rode de
`/Applications` ou de `~/Applications`: de `/tmp` o `installIssue` manda direto
pro painel Permissões e o wizard nem abre. Essas duas vão @2x mesmo
(`screencapture -o -l<id>` já sai 1600x1104, sem sombra e sem halo).

⚠️ **Recapturar `expanded-shelf.png` mexe na máquina do usuário — peça antes.**
É a única imagem dos docs que exige o card aberto com a prateleira em foco, e a
receita passa por fechar o Knobler que estiver rodando (senão são dois notches
na mesma tela), escrever `shelfItems` e `notchSectionOrder` via `defaults`,
subir a build Debug, e então **mover o cursor e clicar** — o hover só acorda com
`CGWarpMouseCursorPosition` em passos pequenos, e o clique no ícone da faixa
encolhe o card, então o ponteiro tem que subir logo depois ou o card recolhe
antes do `screencapture`. Confira o resultado por `GET /status`
(`notches[].focus == "shelf"`), não pelo palpite. Restaure `defaults` e relance
o app do usuário no fim. Um card transitório (Ask, notificação) pode tomar o
notch no meio e estragar a captura — capture algumas vezes e escolha.

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
