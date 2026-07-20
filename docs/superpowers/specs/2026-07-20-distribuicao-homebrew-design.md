# Distribuição do Knobler via Homebrew tap — design

Data: 2026-07-20
Status: aprovado para planejamento

## Objetivo

Dar a um punhado de amigos/colegas (público dev/power-user) um caminho limpo pra
instalar o Knobler numa máquina que **não** é a do autor, sem Developer ID pago e
sem susto do Gatekeeper. Alcance: informal, poucos Macs conhecidos. Sem auto-update
framework, sem notarização, sem Mac App Store.

## Contexto de dependências (levantado)

- **`.app`** — hoje assinado só com cert *Apple Development* (time pessoal). Sem
  Developer ID + notarização, o Gatekeeper bloqueia em Macs de terceiros.
- **Parakeet v3 (~600MB)** — baixado sozinho do HuggingFace no 1º ditado (FluidAudio
  `AsrModels.downloadAndLoad`). Nenhuma ação do usuário. **Já resolvido.**
- **Ollama + gemma3:4b (~3.3GB)** — só pra `formatTranscript`, que é **opt-in
  (default false)**. O app funciona 100% sem Ollama (o Parakeet já pontua).
  **Power-up, não dependência dura.**
- **Permissões** (Acessibilidade, Áudio do sistema, Automação, Calendário,
  Bluetooth, Mic) — pedidas peça-a-peça em runtime. Sem tela única de onboarding.

## Decisão de arquitetura

Distribuir via **Homebrew tap pessoal + GitHub Releases**, artefato `.zip` não
assinado, instalado com `--no-quarantine` (bypassa o Gatekeeper na instalação).

Verificado no Homebrew 6.0.11: `--no-quarantine` **continua funcional**
(`cask/installer.rb:177`, `env_config.rb:907`), apenas saiu do `--help`. Cask **não
pode** auto-desligar quarantine (removido por segurança em 2021), então a flag é
digitada pelo amigo (ou `HOMEBREW_CASK_OPTS`).

Por que Homebrew e não só zip: o público tem `brew`; ganha `brew upgrade` de graça,
uninstall padrão, e o `--no-quarantine` faz o trabalho do `xattr` sozinho. O mesmo
artefato serve quem não tem Homebrew (baixa o zip do Release + `xattr` na mão).

### Fora de escopo (deliberado)

- Developer ID / notarização / Sparkle / Mac App Store.
- Instalador de Ollama (forçaria 3.3GB num opt-in) → fica **documentado**.
- Onboarding unificado de permissões (feature de código, sessão futura).

## Componentes

### 1. Versionamento no build (mudança em `project.yml`)

O Info.plist gerado hoje tem `CFBundleShortVersionString` = "1.0" **hardcoded**.
Editar o plist pós-build quebraria a assinatura. Em vez disso, fazer o plist
referenciar build settings:

- Em `targets.Knobler.info.properties`:
  - `CFBundleShortVersionString: "$(MARKETING_VERSION)"`
  - `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"`
- Em `targets.Knobler.settings.base` (defaults pra build normal do Xcode não quebrar):
  - `MARKETING_VERSION: "0.0.0"`
  - `CURRENT_PROJECT_VERSION: "0"`

Assim o `release.sh` injeta a versão via override de build setting — sem PlistBuddy,
sem re-assinatura. Requer `xcodegen generate` uma vez após a mudança.

### 2. `tools/release.sh <versão>` (repo do app)

Um comando publica uma versão. Fluxo:

1. **Guards:** versão passada como arg (ex: `0.17`); `gh auth status` ok; avisa se a
   árvore git estiver suja (não bloqueia).
2. **Build:**
   `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release
   MARKETING_VERSION=$VER CURRENT_PROJECT_VERSION=$VER -derivedDataPath build/dd build`
3. **Localiza** `build/dd/Build/Products/Release/Knobler.app`.
4. **Empacota:** `ditto -c -k --keepParent <app> build/Knobler-$VER.zip`.
5. **sha256:** `shasum -a 256 build/Knobler-$VER.zip`.
6. **Release:** `gh release create v$VER build/Knobler-$VER.zip --title "Knobler v$VER"
   --notes "..."` (se a tag já existir, `gh release upload v$VER --clobber`).
7. **Auto-bump do tap:** no repo do tap (path via `$KNOBLER_TAP_DIR`, default
   `../homebrew-knobler`), `sed` troca `version` e `sha256` em `Casks/knobler.rb`,
   depois `git -C $TAP commit -am "knobler $VER" && git -C $TAP push`.
8. **Imprime** os 2 comandos de instalação pro amigo.

**Modo `--dry-run`** (self-check runnable): builda + zipa + calcula sha256 + valida a
sintaxe do cask editado (`ruby -c`), mas **pula** `gh release` e o push do tap. É o
jeito de rodar a lógica frágil (sha + edição do cask) sem publicar nada.

Artefatos vão pra `build/` (já no `.gitignore`).

### 3. Repo do tap: `github.com/luccas-silveira/homebrew-knobler`

Exigência do Homebrew: `brew tap luccas-silveira/knobler` mapeia pro repo
`homebrew-knobler`. Conteúdo:

- `Casks/knobler.rb`:
  ```ruby
  cask "knobler" do
    version "0.17"
    sha256 "..."
    url "https://github.com/luccas-silveira/knobler/releases/download/v#{version}/Knobler-#{version}.zip"
    name "Knobler"
    desc "Dynamic Island para o notch do Mac"
    homepage "https://github.com/luccas-silveira/knobler"
    depends_on macos: ">= :sonoma"
    app "Knobler.app"
    caveats <<~EOS
      Instale com --no-quarantine pra pular o Gatekeeper (app não assinado):
        brew install --cask --no-quarantine knobler

      Conceda em Ajustes do Sistema → Privacidade e Segurança:
        • Acessibilidade (teclas de ditado + notificações no notch)
        • Gravação de Áudio do Sistema (visualizador)
      Automação (Spotify/Music), Calendário, Mic e Bluetooth são pedidos em runtime.

      Formatação de transcript com IA (opcional): brew install ollama && ollama pull gemma3:4b
    EOS
  end
  ```
  O `url` aponta pros Releases do repo **do app** (onde o zip mora); o cask mora no
  tap. Separação limpa.
- `README.md`: as 2 linhas de instalação + nota do `--no-quarantine`.

### 4. Seção "Instalação" no `README.md` do app

```bash
brew tap luccas-silveira/knobler
brew install --cask --no-quarantine knobler
```
Update: `brew upgrade --cask knobler` · Remover: `brew uninstall --cask knobler`.
Sem Homebrew: baixe o zip do Release e rode
`xattr -dr com.apple.quarantine /Applications/Knobler.app`.

## Fluxo de dados / vida de uma release

```
autor: ./tools/release.sh 0.17
  └─ build Release (versão injetada) → zip → sha256
     └─ gh release create v0.17 (zip no Releases do repo do app)
        └─ sed version+sha256 no Casks/knobler.rb → commit → push no tap
amigo: brew tap … && brew install --cask --no-quarantine knobler
  └─ brew baixa o zip do Release, instala em /Applications sem quarantine
     └─ 1º launch: concede permissões; 1º ditado: Parakeet baixa ~600MB
```

## Tratamento de erro

- `release.sh` aborta se: sem arg de versão, `gh` não autenticado, build falhou,
  `.app` não encontrado no caminho esperado, ou `$KNOBLER_TAP_DIR` não é um repo git.
- Tag de release já existente → `--clobber` no upload (idempotente pra re-rodar).
- Cask com sha256 errado → o amigo veria erro de checksum no `brew install`; o
  `--dry-run` + `ruby -c` pegam erro de sintaxe antes de publicar.

## Teste / verificação

- **Self-check:** `./tools/release.sh 0.0.1-test --dry-run` builda, zipa, calcula
  sha, valida o cask — sem publicar. É o check que falha se a lógica de
  sha/edição do cask quebrar.
- **E2E manual:** rodar o release real de uma versão baixa, depois num Mac limpo (ou
  com `brew uninstall` antes) rodar os 2 comandos e confirmar que o app abre sem
  prompt do Gatekeeper.

## Riscos / honestidades

- `--no-quarantine` é escolha por-instalação do amigo; se esquecer, o app
  quarantinado é bloqueado (não assinado). O `caveats` lembra.
- Homebrew desencoraja `--no-quarantine`/casks não assinados no tap **oficial** —
  irrelevante pra tap **pessoal** entre amigos, sem gate de notabilidade.
- Se um dia o alcance virar "público", o caminho de upgrade é Developer ID +
  notarização (aí o `--no-quarantine` deixa de ser necessário) e, opcionalmente,
  submeter o cask ao `homebrew/cask` oficial.
