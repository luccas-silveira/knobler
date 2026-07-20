# Distribuição do Knobler via Homebrew tap — design

Data: 2026-07-20
Status: revisado pós-pesquisa (ver `2026-07-20-distribuicao-homebrew-research.md`)

## Objetivo

Dar a um punhado de amigos/colegas (público dev/power-user) um caminho limpo pra
instalar o Knobler numa máquina que **não** é a do autor, sem Developer ID pago e
sem susto do Gatekeeper. Alcance: informal, poucos Macs conhecidos. Sem auto-update
framework, sem notarização, sem Mac App Store.

## Contexto de dependências (levantado)

- **`.app`** — hoje assinado só com cert *Apple Development* (time pessoal). Pela
  pesquisa, essa assinatura é a **pior** opção pra distribuição: embute allowlist de
  dispositivos + expiração → não abre em Mac de terceiro. Será **re-assinado ad-hoc**.
- **Parakeet v3 (~600MB)** — baixado sozinho do HuggingFace no 1º ditado (FluidAudio
  `AsrModels.downloadAndLoad`). Nenhuma ação do usuário. **Já resolvido.**
- **Ollama + gemma3:4b (~3.3GB)** — só pra `formatTranscript`, que é **opt-in
  (default false)**. O app funciona 100% sem Ollama (o Parakeet já pontua).
  **Power-up, não dependência dura.**
- **Permissões** (Acessibilidade, Áudio do sistema, Automação, Calendário,
  Bluetooth, Mic) — pedidas peça-a-peça em runtime. Sem tela única de onboarding.

## Decisão de arquitetura

Distribuir via **Homebrew tap pessoal + GitHub Releases**, artefato `.zip` **assinado
ad-hoc** (não Apple Development, não notarizado). O Gatekeeper é resolvido por um bloco
**`postflight`** no cask que remove a quarantine após a instalação.

**Por que ad-hoc e não Apple Development** (achado central da pesquisa): a assinatura
*Apple Development* embute um provisioning profile com allowlist de dispositivos
(`ProvisionedDevices`) + expiração (~7 dias no time grátis) — o Mac não-registrado do
amigo não abre o app (AMFI rejeita no launch). Ad-hoc (`codesign -s -`) não tem allowlist
nem expiração, é válido pro AMFI no Apple Silicon → roda em qualquer Mac.

**Por que `postflight` e não `--no-quarantine`:** a flag CLI `--no-quarantine` foi
removida no Homebrew 5.1 (confirmado na máquina: é rejeitada). O `postflight` roda
`xattr -dr com.apple.quarantine` sozinho → o amigo roda `brew install --cask knobler`
sem flag nenhuma, e abre limpo.

**Por que Homebrew e não só zip:** o público tem `brew`; ganha `brew upgrade` de graça,
uninstall padrão (`zap`), e o `postflight` faz o trabalho do `xattr`. O mesmo artefato
serve quem não tem Homebrew (baixa o zip do Release + `xattr` na mão).

### Fora de escopo (deliberado)

- Developer ID / notarização / Sparkle / Mac App Store.
- Instalador de Ollama (forçaria 3.3GB num opt-in) → fica **documentado**.
- Onboarding unificado de permissões (feature de código, sessão futura).

## Componentes

### 1. Versionamento no build (mudança em `project.yml`)

O Info.plist gerado hoje tem `CFBundleShortVersionString` = "1.0" **hardcoded**.
Fazer o plist referenciar build settings (evita editar o plist pós-build):

- Em `targets.Knobler.info.properties`:
  - `CFBundleShortVersionString: "$(MARKETING_VERSION)"`
  - `CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"`
- Em `targets.Knobler.settings.base` (defaults pra build normal do Xcode não quebrar):
  - `MARKETING_VERSION: "0.0.0"`
  - `CURRENT_PROJECT_VERSION: "0"`

O `release.sh` injeta a versão via override de build setting. Requer `xcodegen generate`
uma vez após a mudança.

### 2. `tools/release.sh <versão>` (repo do app)

Um comando publica uma versão. Fluxo:

1. **Guards:** versão passada como arg (ex: `0.17`); `gh auth status` ok; `$KNOBLER_TAP_DIR`
   é repo git; avisa se a árvore estiver suja (não bloqueia).
2. **Build:**
   `xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release
   MARKETING_VERSION=$VER CURRENT_PROJECT_VERSION=$VER -derivedDataPath build/dd build`
3. **Localiza** `build/dd/Build/Products/Release/Knobler.app`.
4. **Re-assina ad-hoc** (remove o profile/assinatura Apple Development restrita a
   dispositivo):
   ```sh
   rm -f "$APP/Contents/embedded.provisionprofile"
   codesign --force --deep --sign - "$APP"   # ponytail: --deep re-sign; se framework aninhado (FluidAudio) reclamar, assinar de dentro pra fora
   codesign --verify --verbose "$APP"         # sanidade — aborta se falhar
   ```
5. **Empacota:** `ditto -c -k --keepParent "$APP" build/Knobler-$VER.zip`.
6. **sha256:** `shasum -a 256 build/Knobler-$VER.zip`.
7. **Release:** `gh release create v$VER build/Knobler-$VER.zip --title "Knobler v$VER"
   --notes "..."` (se a tag já existir, `gh release upload v$VER ... --clobber`).
8. **Auto-bump do tap:** em `$KNOBLER_TAP_DIR` (default `../homebrew-knobler`), `sed` troca
   `version` e `sha256` em `Casks/knobler.rb`, depois
   `git -C $TAP commit -am "knobler $VER" && git -C $TAP push`.
9. **Imprime** o comando de instalação pro amigo.

**Modo `--dry-run`** (self-check runnable): build + re-sign + `codesign --verify` + zip +
sha256 + valida a sintaxe do cask editado (`ruby -c`), mas **pula** `gh release` e o push.
É o jeito de rodar a lógica frágil (re-sign, sha, edição do cask) sem publicar nada.

Artefatos vão pra `build/` (já no `.gitignore`).

### 3. Repo do tap: `github.com/luccas-silveira/homebrew-knobler` (público)

`brew tap luccas-silveira/knobler` mapeia pro repo `homebrew-knobler`. Scaffold com
`brew tap-new luccas-silveira/homebrew-knobler`. Conteúdo:

- `Casks/knobler.rb` (o token `knobler` deve bater com o nome do arquivo):
  ```ruby
  cask "knobler" do
    version "0.17"
    sha256 "..."   # preenchido pelo release.sh

    url "https://github.com/luccas-silveira/knobler/releases/download/v#{version}/Knobler-#{version}.zip"
    name "Knobler"
    desc "Dynamic Island for the Mac notch"   # inglês: silencia nits do brew audit
    homepage "https://github.com/luccas-silveira/knobler"

    depends_on macos: ">= :sonoma"   # == macOS 14+; piso 14.2 fica no LSMinimumSystemVersion

    app "Knobler.app"

    # App é ad-hoc/não-notarizado e --no-quarantine foi removida no Homebrew 5.1;
    # remover a quarantine aqui, senão o Gatekeeper bloqueia o 1º launch.
    postflight do
      system_command "/usr/bin/xattr",
                     args: ["-dr", "com.apple.quarantine", "#{appdir}/Knobler.app"]
    end

    zap trash: [
      "~/Library/Preferences/com.zoi.knobler.plist",
    ]

    caveats <<~EOS
      O Knobler é assinado ad-hoc (sem Developer ID/notarização). O Homebrew remove a
      quarentena automaticamente. Se algum dia o macOS ainda bloquear (ex.: app
      re-baixado por fora do brew), rode:
        xattr -dr com.apple.quarantine "#{appdir}/Knobler.app"

      Conceda em Ajustes do Sistema → Privacidade e Segurança:
        • Acessibilidade (teclas de ditado + notificações no notch)
        • Gravação de Áudio do Sistema (visualizador)
      Automação (Spotify/Music), Calendário, Mic e Bluetooth são pedidos em runtime.

      Formatação de transcript com IA (opcional): brew install ollama && ollama pull gemma3:4b
    EOS
  end
  ```
  O `url` aponta pros Releases do repo **do app**; o cask mora no tap. Separação limpa.
- `README.md`: a linha de instalação + nota do ad-hoc.

### 4. Seção "Instalação" no `README.md` do app

```bash
brew tap luccas-silveira/knobler
brew install --cask knobler
```
Update: `brew upgrade --cask knobler` · Remover: `brew uninstall --cask knobler` (ou
`brew uninstall --zap --cask knobler` pra limpar prefs). Sem Homebrew: baixe o zip do
Release e rode `xattr -dr com.apple.quarantine /Applications/Knobler.app`.

## Fluxo de dados / vida de uma release

```
autor: ./tools/release.sh 0.17
  └─ build Release (versão injetada) → re-sign ad-hoc → zip → sha256
     └─ gh release create v0.17 (zip no Releases do repo do app)
        └─ sed version+sha256 no Casks/knobler.rb → commit → push no tap
amigo: brew tap … && brew install --cask knobler
  └─ brew baixa o zip do Release, instala em /Applications, postflight tira a quarantine
     └─ 1º launch: abre limpo; concede permissões; 1º ditado: Parakeet baixa ~600MB
```

## Tratamento de erro

- `release.sh` aborta se: sem arg de versão, `gh` não autenticado, build falhou,
  `.app` não encontrado, `codesign --verify` falhou, ou `$KNOBLER_TAP_DIR` não é repo git.
- Tag de release já existente → `--clobber` no upload (idempotente pra re-rodar).
- Cask com sha256 errado → o amigo veria erro de checksum no `brew install`; o
  `--dry-run` + `ruby -c` pegam erro de sintaxe antes de publicar.

## Teste / verificação

- **Self-check:** `./tools/release.sh 0.0.1-test --dry-run` builda, re-assina, verifica a
  assinatura, zipa, calcula sha, valida o cask — sem publicar. É o check que falha se a
  lógica de re-sign/sha/edição do cask quebrar.
- **E2E manual:** rodar o release real de uma versão baixa; depois num Mac limpo (ou com
  `brew uninstall` antes) rodar `brew tap … && brew install --cask knobler` e confirmar
  que o app abre **sem** prompt do Gatekeeper e **sem** crash no launch (valida o ad-hoc).

## Riscos / honestidades

- **Fragilidade residual do free:** ad-hoc + `postflight` abre limpo **via brew**. Se o
  amigo re-baixar/AirDropar o `.app` por fora do brew, ele re-quarantina → Gatekeeper
  bloqueia app não-notarizado → `xattr` manual (no `caveats`). Aceitável pra poucos amigos.
- `--deep` no codesign é desencorajado pela Apple (mas funcional); se o FluidAudio trouxer
  framework aninhado que reclame, assinar de dentro pra fora.
- Homebrew desencoraja casks não assinados no tap **oficial** (política de 01/set/2026) —
  **irrelevante pra tap pessoal**; só a remoção da flag no core afeta todos (já contornado
  pelo `postflight`).
- Caminho de upgrade se um dia virar "público": Developer ID + notarização (aí dá pra
  remover re-sign ad-hoc, `postflight` e a nota de quarantine) e, opcionalmente, submeter
  o cask ao `homebrew/cask` oficial.
