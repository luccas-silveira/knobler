# Knobler — instruções do projeto

App macOS nativo (AppKit + SwiftUI) que transforma o notch num Dynamic Island:
mídia do Spotify, ditado, Pomodoro, notificações e uma API HTTP local. Roda como
agente (`LSUIElement`). Rodando em **macOS 26 Tahoe** → o `glassEffect` / Liquid
Glass nativo está disponível (guardado por `if #available(macOS 26, *)`).

## Build & run

Projeto **gerado por XcodeGen** a partir de `project.yml`. O `.xcodeproj` é um
artefato.

```bash
xcodegen generate                                   # só após mudar project.yml ou adicionar/remover arquivos
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Debug build
```

⚠️ **Nunca edite `Knobler.xcodeproj` à mão** — a mudança some no próximo
`xcodegen generate`. Alvos, dependências e settings vivem em `project.yml`.

## Loop de snapshot (feedback visual)

`tools/snapshot.sh` compila a `NotchView` isolada com `swiftc` e renderiza cada
estado em `Snapshots/*.png` — é o jeito de "ver" a UI sem abrir o app.

```bash
./tools/snapshot.sh          # regenera Snapshots/*.png; leia os PNGs pra validar
```

⚠️ A lista de arquivos em `tools/snapshot.sh` é **manual**. Ao adicionar um
`.swift` novo em `Knobler/` que a `NotchView` use, adicione-o lá também.

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
