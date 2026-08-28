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
Feature nova escreve a novidade em `Knobler/Novidades/<versão>.html` junto da
entrada do CHANGELOG (o `release.sh minor`/`major` aborta sem ela) e acrescenta
a versão a `NovidadesCatalogo.versoes`.

## Loop de snapshot (feedback visual)

`tools/snapshot.sh` compila a `NotchView` isolada com `swiftc` e renderiza cada
estado em `Snapshots/*.png` — é o jeito de "ver" a UI sem abrir o app.

```bash
./tools/snapshot.sh          # regenera Snapshots/*.png; leia os PNGs pra validar
```

⚠️ A lista de arquivos que a `NotchView` arrasta vive em
`tools/notchview-fontes.txt` e é **manual**. Ao adicionar um `.swift` novo em
`Knobler/` que a `NotchView` use, acrescente-o lá — `tools/snapshot.sh` (poses) e
`tools/cortecheck.sh` (transições) leem essa mesma lista.

⚠️ **Recapturar `docs/images/expanded-shelf.png` mexe na máquina do usuário —
peça antes.**

Catálogo das views que não renderizam offscreen, PNGs não determinísticos e
receitas de captura das imagens de `docs/images/`: skill `snapshot-ui`
(`.claude/skills/snapshot-ui/SKILL.md`).

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
