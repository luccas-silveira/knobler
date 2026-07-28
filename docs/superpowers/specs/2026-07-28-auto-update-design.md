# Aviso e instalação de atualizações — design

Data: 2026-07-28
Status: aprovado (revisado pós-pesquisa)

## Objetivo

O usuário descobre sozinho que existe versão nova do Knobler e atualiza sem sair
do app. Hoje "atualizar" significa lembrar de rodar `brew upgrade --cask knobler`
na mão — o app não sabe que é velho, e ninguém checa o GitHub por esporte.

Escopo: **avisar** + **instalar com um clique**, reusando o Homebrew que já é o
canal de distribuição. Não é um framework de auto-update.

## Contexto (o que já existe)

- Distribuição: tap pessoal `luccas-silveira/homebrew-knobler` + GitHub Releases,
  artefato `.zip` assinado com o cert local `Knobler Local Signing`
  (`tools/release.sh`). Sem Developer ID, sem notarização.
- O cask **não** tem `uninstall quit:` — o `brew upgrade` não mata o app rodando.
  Isso é o que torna viável rodar o brew de dentro do próprio app.
- O `postflight` do cask roda `xattr -dr` e `--download-model` (best-effort; com o
  modelo já em cache é instantâneo).
- `CFBundleShortVersionString` = `$(MARKETING_VERSION)`, escrito só pelo
  `release.sh`. É a versão instalada, confiável.
- `docs/IDEIAS.md:157` já registrava a ideia; este spec a resolve.

## Achados da pesquisa (2026-07-28)

Medidos na máquina do autor, não presumidos:

- **API do GitHub confirmada:** `tag_name`, `body`, `html_url` e `assets[]` com
  `browser_download_url` vêm no release real. Limite de 60 req/h por IP sem auth.
  O `body` é **Markdown** (`### Fixed`, `**negrito**`) — o card precisa de um strip
  antes de renderizar.
- **Asset único, 7 MB** (`Knobler-0.8.4.zip`). Download direto é barato; não
  justifica barra de progresso granular.
- **O app não é sandboxed** (só `com.apple.security.get-task-allow`) — `Process`
  roda sem restrição.
- **`/Applications` é `root:admin` com `drwxrwxr-x`** — um usuário admin substitui
  o bundle sem autorização elevada. Usuário não-admin falha, e isso vira mensagem
  de erro, não prompt de senha.
- **A máquina do autor NÃO tem o app instalado via brew:**
  `brew list --cask knobler` falha (sem Caskroom) e `codesign -dv` mostra
  `TeamIdentifier=7UNDW72N73` (Apple Development), ou seja: cópia manual de um build
  do Xcode. Um updater exclusivamente via brew não serviria a quem o pediu — daí o
  caminho duplo abaixo. (De quebra, esse `TeamIdentifier` é o cenário que o README
  já documenta como causa do ditado quebrado.)

## Decisões

**Homebrew como executor, não Sparkle.** O canal de distribuição já é o brew; ele
já resolve download, checksum, quarantine e o modelo de ditado. Sparkle exigiria
appcast hospedado, chaves EdDSA e um segundo caminho de instalação divergente do
cask — infra desproporcional pro alcance (um punhado de Macs conhecidos).

**GitHub Releases API como fonte da verdade da versão**, não o cask. A API
devolve `tag_name`, `body` (as notas que o `release.sh` extrai do CHANGELOG) e
`html_url` numa chamada sem autenticação. Ler o cask exigiria rede + parse de
Ruby pra obter menos informação.

**Aviso uma vez por versão.** O card expande sozinho na primeira detecção; um
`[Depois]` grava a versão em `skippedVersion` e ela não volta a interromper. A
linha nos Ajustes continua lá pra quem mudar de ideia.

**Dois instaladores, escolhidos em runtime.** Se `brew list --cask knobler` responder,
usa o brew — mantém o Caskroom em sincronia, senão o próximo `brew upgrade` fica
perdido. Se não responder (instalação por zip, que é o caso da máquina do autor),
baixa o asset do release e substitui o bundle. Um clique funciona nos dois mundos;
o custo é ~40 linhas de download+extração.

### Fora de escopo (deliberado)

Instalação silenciosa em background, delta updates, appcast, canal beta,
rollback. Nada disso serve ao alcance atual.

## Componentes

### 1. `Knobler/Updater.swift` (novo, ~130 linhas)

Único arquivo novo. Sem dependência nova.

```swift
struct Release {
    let version: String
    let notes: String       // markdown do CHANGELOG, strippado antes de exibir
    let url: URL            // html_url — página do release
    let asset: URL?         // assets[0].browser_download_url — o .zip
}

enum UpdateState: Equatable {
    case available(Release)
    case installing
    case failed(String)     // última linha útil do stderr do brew
}

final class Updater: ObservableObject {
    @Published private(set) var state: UpdateState?
    func check(force: Bool = false)   // force = botão "Verificar agora"
    func install()
    func skipCurrent()                // [Depois]
}
```

- **Checagem:** `GET https://api.github.com/repos/luccas-silveira/knobler/releases/latest`
  via `URLSession`, sem auth (limite de 60 req/h por IP; usamos ~1/dia). Decodifica
  `tag_name`/`body`/`html_url` com `Codable`. Falha de rede é silenciosa — não
  existe update ruim o bastante pra justificar um alerta de erro de rede.
- **Agendamento:** 30s após o launch (não competir com o boot do app) e a cada 24h
  via `Timer`. `lastCheck` e `skippedVersion` em `UserDefaults`, junto com a flag
  `checkForUpdates` (default `true`).
- **Comparação de versão:** função pura `isNewer(_ a: String, than b: String) -> Bool`,
  comparando `major.minor.patch` por componente numérico — `0.10.0 > 0.9.0` tem que
  dar verdadeiro. Tolera prefixo `v` na tag. É a única lógica não-trivial do
  arquivo e a única coberta por teste.

O `Updater` não conhece a UI. `NotchViewModel` e `SettingsView` observam o mesmo
`state`, então os dois pontos de entrada nunca discordam.

### 2. Card no notch

- `@Published var update: UpdateState?` no `NotchViewModel` + `case update` no
  `Mode`, seguindo o padrão de `.pomodoro`/`.airpods`.
- **Prioridade abaixo de ditado e HUD**: um update nunca interrompe uma gravação
  em andamento. Se o modo ativo é `.dictation` ou `.hud`, o card espera.
- `UpdateCardView` em `NotchView.swift`: título `Knobler 0.9.0 disponível`, corpo
  com as primeiras linhas de `notes`, botões `[Atualizar]` `[Depois]`.
- Durante `.installing`: `● Atualizando…` sem botões. Em `.failed`: a mensagem +
  `[Ver release]`.

### 3. Ajustes › Geral

Bloco permanente na `SettingsView`:

- `Versão 0.8.4 — atualizado` **ou** `[Atualizar para 0.9.0]`
- Toggle `Verificar atualizações automaticamente` (default ligado)
- Botão `Verificar agora`

### 4. Instalação

Dois caminhos, escolhidos por uma sonda: `brew list --cask knobler` sai 0 → caminho
brew; qualquer outra coisa → caminho direto.

**4a. Caminho brew** (instalação pelo cask)

```sh
HOMEBREW_NO_AUTO_UPDATE=1
git -C "$(brew --repository luccas-silveira/knobler)" pull --ff-only -q
brew upgrade --cask knobler
```

O `git pull` cirúrgico no tap existe porque `brew update` completo leva ~30s
buscando taps irrelevantes. `HOMEBREW_NO_AUTO_UPDATE=1` impede que o brew faça
esse update completo por conta própria. O `brew` é procurado em
`/opt/homebrew/bin/brew` (Apple Silicon) e `/usr/local/bin/brew` (Intel).

**4b. Caminho direto** (instalação por zip — o caso da máquina do autor)

1. Baixa `release.asset` (7 MB) com `URLSession` pra um diretório temporário.
2. `ditto -x -k <zip> <tmp>` — extrai preservando os atributos do bundle.
3. Sanidade antes de trocar qualquer coisa: `codesign --verify --strict` no app
   extraído **e** `CFBundleShortVersionString` igual à versão esperada. Falhou →
   `.failed`, nada é substituído.
4. `FileManager.replaceItemAt` troca `/Applications/Knobler.app` pelo novo — a
   operação é atômica e guarda o antigo até concluir.
5. `xattr -dr com.apple.quarantine` no bundle novo, replicando o `postflight` do
   cask. (Zip baixado por `URLSession` num app não-sandboxed normalmente já vem
   sem quarantine; a linha é barata e remove a dúvida.)
6. Sem `--download-model`: quem já usa o app tem o Parakeet em cache, e o launch
   baixa como fallback de qualquer jeito.

Se `/Applications` não for gravável (usuário não-admin), o passo 4 falha com
mensagem explícita — o updater não escala privilégio nem abre prompt de senha.

**Comum aos dois:**

- **Relaunch:** ao sair com status 0, o app dispara um shell destacado —
  `/bin/sh -c 'while kill -0 <pid> 2>/dev/null; do sleep 0.3; done; sleep 1; open -a /Applications/Knobler.app'`
  — e chama `NSApp.terminate`. O processo antigo sobrevive à substituição do
  bundle (o inode continua vivo), então quem relança tem que ser externo.
- **Erro:** qualquer passo falhando → `.failed(<última linha útil do stderr>)`, e o
  card oferece `Ver release` como saída manual.

## Fluxo

```
launch +30s ─┐
Timer 24h  ──┼─→ check() ─→ tag > versão instalada?
"Verificar" ─┘                 │
                               ├── não → state = nil
                               └── sim → state = .available
                                          ├─→ card no notch (1x por versão)
                                          └─→ linha nos Ajustes (sempre)
                                                     │
                                              [Atualizar]
                                                     ↓
                                              .installing
                                                     │
                              brew list --cask knobler?
                                   ┌─────────┴─────────┐
                              sim: brew           não: baixa zip
                              upgrade             verifica assinatura
                                   │              replaceItemAt + xattr
                                   └─────────┬─────────┘
                                             ├── ok → relaunch + terminate
                                             └── erro → .failed
```

## Erros e casos de borda

| Caso | Comportamento |
|---|---|
| Sem rede na checagem | Silencioso. Tenta de novo no próximo ciclo. |
| Rate limit do GitHub (403) | Igual a falha de rede: silencioso. |
| App não instalado via brew | Caminho direto: baixa o zip e substitui o bundle. |
| Release sem asset `.zip` | Sem caminho direto: botão vira `Ver release`. |
| Assinatura do app baixado não confere | Aborta antes de tocar em `/Applications`. |
| `/Applications` não gravável | `.failed` com mensagem; sem prompt de senha. |
| `brew upgrade` falha | Card mostra o stderr + `Ver release`. |
| Usuário clica `[Depois]` | Versão vai pro `skippedVersion`; some do notch, fica nos Ajustes. |
| Update durante um ditado | Card espera o modo liberar. |

## Risco herdado (não introduzido aqui)

O update troca o binário. Se a release tiver sido publicada com o fallback ad-hoc
do `release.sh` (sem o cert `Knobler Local Signing`), o `cdhash` muda, o TCC revoga
a Acessibilidade e o ditado para em silêncio — o mesmo problema de `v0.8.4`. O
`release.sh` já avisa em voz alta nesse caminho. O updater não melhora nem piora
isso; o card leva uma linha dizendo que, se o ditado parar depois de atualizar,
a causa é essa.

Caso particular medido: o app hoje em `/Applications` na máquina do autor está
assinado com *Apple Development* (`TeamIdentifier=7UNDW72N73`), não com o cert
local. O **primeiro** update pelo caminho direto vai trocar a identidade para
`Knobler Local Signing` e derrubar a Acessibilidade uma vez — depois disso as
releases passam a casar entre si e o problema para de acontecer. Vale conceder a
permissão de novo após esse primeiro update e seguir a vida.

## Teste

`tools/updatercheck.swift`, no padrão de `tools/askcheck.swift` (não faz parte do
alvo, roda por `swiftc`):

```sh
xcrun swiftc -parse-as-library -swift-version 5 \
  Knobler/Updater.swift tools/updatercheck.swift -o /tmp/updatercheck && /tmp/updatercheck
```

Cobre `isNewer`: `0.10.0 > 0.9.0`, `1.0.0 > 0.99.99`, igual não é maior, prefixo
`v` tolerado, string malformada não crasha. Cobre também o strip de markdown
(`### Fixed` e `**negrito**` viram texto limpo) e o parse do JSON da API a partir
de um payload fixo.

O resto — brew, substituição do bundle, relaunch — não é testável offscreen nem
pelo `tools/snapshot.sh`. Valida-se publicando uma release de teste e atualizando
a partir da versão anterior, ou apontando o updater pra uma tag antiga pra forçar
o caminho "tem update".

## Verificação visual

O card entra no `tools/snapshot.sh` como cenário novo (`update-card.png`) —
`UpdateCardView` é SwiftUI puro, sem `NSView` real, então renderiza offscreen.
`Knobler/Updater.swift` precisa entrar na lista manual de arquivos do script.
