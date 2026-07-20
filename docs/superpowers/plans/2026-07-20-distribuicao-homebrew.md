# Distribuição via Homebrew — Plano de Implementação

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Distribuir o Knobler pra um punhado de amigos via `brew install --cask knobler`, sem Developer ID pago e sem susto do Gatekeeper.

**Architecture:** Um `tools/release.sh` builda em Release, re-assina o `.app` **ad-hoc**, zipa, publica no GitHub Releases do repo do app e bumpa `Casks/knobler.rb` num tap público separado (`homebrew-knobler`). O cask remove a quarantine via `postflight`, então o amigo instala com um comando e abre limpo.

**Tech Stack:** bash, `xcodebuild`, `codesign` (ad-hoc), `ditto`, `gh` CLI, Homebrew Cask, XcodeGen.

## Global Constraints

- Deployment target: **macOS 14.2**. No cask, `depends_on macos: ">= :sonoma"` (== 14; o piso 14.2 vem do `LSMinimumSystemVersion`, gerado do deployment target — 14.2 minor não é expressável no DSL do brew).
- Artefato distribuído é **assinado ad-hoc** (`codesign -s -`), **nunca** com a identidade *Apple Development* (embute allowlist de dispositivo + expiração → não abre no Mac do amigo). O build local do Xcode pode seguir com o cert de dev; só o artefato do release é re-assinado.
- `--no-quarantine` **não existe mais** (removido no Homebrew 5.1). A quarantine é removida por `postflight` no cask.
- Repos: app em `github.com/luccas-silveira/knobler`; tap em `github.com/luccas-silveira/homebrew-knobler` (**público**). Cask token `knobler` → arquivo `Casks/knobler.rb`.
- Bundle id: `com.zoi.knobler`. Prefs em `~/Library/Preferences/com.zoi.knobler.plist`.
- Comentários e `caveats` em **pt-BR**; `desc` do cask em **inglês** (silencia nits do `brew audit`). Simplificações deliberadas marcadas com `// ponytail:` / `# ponytail:`.
- Fora de escopo: Developer ID, notarização, Sparkle, Mac App Store, instalador de Ollama, onboarding de permissões.

## Estrutura de arquivos

- `project.yml` (modificar) — versão fluindo via `$(MARKETING_VERSION)`.
- `Knobler/Info.plist` (regenerado por xcodegen — commitar junto).
- `tools/release.sh` (criar) — build → ad-hoc sign → zip → publish → bump.
- `../homebrew-knobler/Casks/knobler.rb` (criar, repo novo) — o cask.
- `../homebrew-knobler/README.md` (criar) — instruções.
- `README.md` (modificar) — seção "Instalação".

---

### Task 1: Versão fluindo via build setting (`project.yml`)

Hoje o `Info.plist` gerado tem `CFBundleShortVersionString` = "1.0" hardcoded. Editar o plist pós-build quebraria a assinatura; em vez disso, fazer o plist referenciar `$(MARKETING_VERSION)` e o `release.sh` injeta a versão no build.

**Files:**
- Modify: `project.yml:20-22` (bloco `info.properties`) e `project.yml:32-38` (bloco `settings.base`)
- Modify (regenerado): `Knobler/Info.plist`

**Interfaces:**
- Produces: build settings `MARKETING_VERSION` e `CURRENT_PROJECT_VERSION` sobrescrevíveis via `xcodebuild ... MARKETING_VERSION=X`, refletidos em `CFBundleShortVersionString`/`CFBundleVersion` do app buildado. O `release.sh` (Task 2) consome isso.

- [ ] **Step 1: Adicionar as chaves de versão no `info.properties`**

Em `project.yml`, dentro de `targets.Knobler.info.properties` (depois de `CFBundleDisplayName: Knobler`), adicionar:

```yaml
        CFBundleShortVersionString: "$(MARKETING_VERSION)"
        CFBundleVersion: "$(CURRENT_PROJECT_VERSION)"
```

- [ ] **Step 2: Adicionar os defaults no `settings.base`**

Em `project.yml`, dentro de `targets.Knobler.settings.base` (depois de `SWIFT_VERSION: "5.0"`), adicionar:

```yaml
        MARKETING_VERSION: "0.0.0"
        CURRENT_PROJECT_VERSION: "0"
```

- [ ] **Step 3: Regenerar o projeto**

Run: `xcodegen generate`
Expected: `Created project at .../Knobler.xcodeproj`

- [ ] **Step 4: Verificar que o plist gerado referencia o build var (o check)**

Run: `grep MARKETING_VERSION Knobler/Info.plist`
Expected: uma linha com `<string>$(MARKETING_VERSION)</string>` — confirma o wiring sem precisar de um build completo. Se não aparecer, o passo 1 não pegou.

- [ ] **Step 5: (opcional, lento ~2min) Confirmar a substituição num build real**

Run:
```bash
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release \
  MARKETING_VERSION=9.9.9 CURRENT_PROJECT_VERSION=9 -derivedDataPath build/dd -quiet build \
&& /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
     build/dd/Build/Products/Release/Knobler.app/Contents/Info.plist
```
Expected: imprime `9.9.9`.

- [ ] **Step 6: Commit**

```bash
git add project.yml Knobler/Info.plist
git commit -m "build(dist): versão via \$(MARKETING_VERSION) pro release.sh injetar"
```

---

### Task 2: `release.sh` — empacotamento local (build + ad-hoc + zip + sha)

O núcleo do script, até o zip assinado. O modo `--dry-run` para aqui — é o self-check que exercita a lógica frágil (re-sign, sha) sem publicar. A publicação (gh + tap) vem na Task 4.

**Files:**
- Create: `tools/release.sh`

**Interfaces:**
- Consumes: `MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` (Task 1).
- Produces: `build/Knobler-<versão>.zip` (raiz = `Knobler.app/`, ad-hoc assinado) e a string `sha256`. Variáveis internas `REPO_ROOT`, `TAP_DIR` (`$KNOBLER_TAP_DIR`, default `$REPO_ROOT/../homebrew-knobler`), `CASK`, `VER`, `DRY`, `APP`, `ZIP`, `SHA` são reusadas pela Task 4.

- [ ] **Step 1: Criar `tools/release.sh` com o núcleo + `--dry-run`**

```bash
#!/usr/bin/env bash
# Empacota o Knobler pra distribuição: build Release, re-assina ad-hoc, zipa,
# publica no GitHub Releases e bumpa o cask no tap homebrew-knobler.
# Uso: ./tools/release.sh <versão> [--dry-run]
#   --dry-run: builda + assina + zipa + calcula sha, mas NÃO publica nada.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="${KNOBLER_TAP_DIR:-$REPO_ROOT/../homebrew-knobler}"
CASK="$TAP_DIR/Casks/knobler.rb"

VER=""
DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -*) echo "flag desconhecida: $arg" >&2; exit 2 ;;
    *) VER="$arg" ;;
  esac
done
[ -n "$VER" ] || { echo "uso: $0 <versão> [--dry-run]" >&2; exit 2; }

cd "$REPO_ROOT"

echo "==> build Release ($VER)"
xcodebuild -project Knobler.xcodeproj -scheme Knobler -configuration Release \
  MARKETING_VERSION="$VER" CURRENT_PROJECT_VERSION="$VER" \
  -derivedDataPath build/dd -quiet build

APP="build/dd/Build/Products/Release/Knobler.app"
[ -d "$APP" ] || { echo "app não encontrado: $APP" >&2; exit 1; }

echo "==> re-assinando ad-hoc (removendo profile Apple Development)"
# ponytail: --deep re-sign resolve nested (FluidAudio); se um framework aninhado
# reclamar, assinar de dentro pra fora antes do bundle externo.
rm -f "$APP/Contents/embedded.provisionprofile"
codesign --force --deep --sign - "$APP"
codesign --verify --strict --verbose=2 "$APP"

ZIP="build/Knobler-$VER.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "==> $ZIP"
echo "    sha256 $SHA"

if [ "$DRY" -eq 1 ]; then
  if [ -f "$CASK" ]; then ruby -c "$CASK"; fi
  echo "== dry-run: nada publicado =="
  exit 0
fi

# --- publicação: preenchido na Task 4 ---
echo "publicação ainda não implementada (rode com --dry-run)" >&2
exit 1
```

- [ ] **Step 2: Tornar executável**

Run: `chmod +x tools/release.sh`
Expected: sem saída.

- [ ] **Step 3: Rodar o self-check `--dry-run` (o teste — ~2min)**

Run: `./tools/release.sh 0.0.1-test --dry-run`
Expected: termina com `== dry-run: nada publicado ==`, cria `build/Knobler-0.0.1-test.zip`, e o `codesign --verify` não aborta (sem "invalid" / "not signed"). Se o verify falhar, o re-sign ad-hoc está errado.

- [ ] **Step 4: Confirmar que o zip tem `Knobler.app/` na raiz e é ad-hoc**

Run:
```bash
unzip -l build/Knobler-0.0.1-test.zip | grep -m1 'Knobler.app/' \
&& codesign -dv build/dd/Build/Products/Release/Knobler.app 2>&1 | grep -i 'Signature=adhoc'
```
Expected: uma linha `Knobler.app/` e `Signature=adhoc` (confirma que não é mais Apple Development).

- [ ] **Step 5: Commit**

```bash
git add tools/release.sh
git commit -m "feat(dist): release.sh — build + re-sign ad-hoc + zip (--dry-run)"
```

---

### Task 3: Repo do tap + `Casks/knobler.rb`

Criar o repo público `homebrew-knobler` ao lado do repo do app, com o cask (placeholder de versão/sha que a Task 4 bumpa) e um README. Exigência do Homebrew: repo `homebrew-<nome>` público → `brew tap luccas-silveira/knobler`.

**Files:**
- Create: `../homebrew-knobler/Casks/knobler.rb`
- Create: `../homebrew-knobler/README.md`

**Interfaces:**
- Consumes: nada.
- Produces: `Casks/knobler.rb` com linhas `  version "..."` e `  sha256 "..."` (indent 2 espaços, no início da linha) que o `sed` da Task 4 substitui; `$CASK` aponta pra cá.

- [ ] **Step 1: Criar o repo público e clonar ao lado do app**

Run:
```bash
gh repo create luccas-silveira/homebrew-knobler --public \
  --description "Homebrew tap do Knobler" --clone
mv homebrew-knobler ../homebrew-knobler 2>/dev/null || true
mkdir -p ../homebrew-knobler/Casks
```
Expected: repo criado no GitHub e clonado. (Se o `gh repo create --clone` clonar no diretório atual, o `mv` o coloca ao lado do repo do app; ajuste se seu layout diferir — o importante é `$KNOBLER_TAP_DIR` apontar pra ele.)

- [ ] **Step 2: Escrever `../homebrew-knobler/Casks/knobler.rb`**

```ruby
cask "knobler" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/luccas-silveira/knobler/releases/download/v#{version}/Knobler-#{version}.zip"
  name "Knobler"
  desc "Dynamic Island for the Mac notch"
  homepage "https://github.com/luccas-silveira/knobler"

  depends_on macos: ">= :sonoma"

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

- [ ] **Step 3: Escrever `../homebrew-knobler/README.md`**

```markdown
# homebrew-knobler

Tap do [Knobler](https://github.com/luccas-silveira/knobler) — Dynamic Island pro notch do Mac.

```bash
brew tap luccas-silveira/knobler
brew install --cask knobler
```

App assinado ad-hoc (sem Developer ID). O Homebrew remove a quarentena
automaticamente no install. Update: `brew upgrade --cask knobler`.
```

- [ ] **Step 4: Validar sintaxe do cask (o check)**

Run: `ruby -c ../homebrew-knobler/Casks/knobler.rb && brew style --cask ../homebrew-knobler/Casks/knobler.rb || true`
Expected: `Syntax OK`. O `brew style` pode emitir nits (não bloqueiam tap pessoal); o `|| true` impede que parem o passo.

- [ ] **Step 5: Confirmar que o tap funciona do lado do amigo**

Run:
```bash
git -C ../homebrew-knobler add -A && git -C ../homebrew-knobler commit -m "cask inicial (placeholder)" && git -C ../homebrew-knobler push
brew tap luccas-silveira/knobler
brew info --cask knobler
```
Expected: `brew info` mostra o cask `knobler` (versão 0.0.0 por enquanto). Confirma que o tap público resolve.

---

### Task 4: `release.sh` — publicação (gh release + auto-bump do tap)

Trocar o stub de publicação da Task 2 pelo fluxo real: cria/atualiza o GitHub Release com o zip, faz `sed` da versão+sha no cask e dá push no tap. Testado fazendo o **primeiro release real** de ponta a ponta.

**Files:**
- Modify: `tools/release.sh` (substituir o bloco `--- publicação ---`)

**Interfaces:**
- Consumes: `VER`, `ZIP`, `SHA`, `TAP_DIR`, `CASK`, `REPO_ROOT` (Task 2); `Casks/knobler.rb` (Task 3).
- Produces: GitHub Release `v<versão>` com o zip; commit de bump no tap.

- [ ] **Step 1: Adicionar os guards de publicação (logo após o parse de args, antes do `cd`)**

Inserir depois da linha `[ -n "$VER" ] || { ...; }` e antes de `cd "$REPO_ROOT"`:

```bash
if [ "$DRY" -eq 0 ]; then
  command -v gh >/dev/null || { echo "gh não instalado" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh não autenticado (gh auth login)" >&2; exit 1; }
  git -C "$TAP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "tap não encontrado em $TAP_DIR. Ajuste KNOBLER_TAP_DIR." >&2; exit 1; }
  [ -z "$(git -C "$REPO_ROOT" status --porcelain)" ] \
    || echo "⚠️  árvore suja — o release aponta pro commit remoto atual."
fi
```

- [ ] **Step 2: Substituir o stub pelo bloco de publicação**

Trocar estas 3 linhas:

```bash
# --- publicação: preenchido na Task 4 ---
echo "publicação ainda não implementada (rode com --dry-run)" >&2
exit 1
```

por:

```bash
echo "==> publicando release v$VER"
if gh release view "v$VER" >/dev/null 2>&1; then
  gh release upload "v$VER" "$ZIP" --clobber
else
  gh release create "v$VER" "$ZIP" --title "Knobler v$VER" --notes "Knobler v$VER"
fi

echo "==> bumpando o cask"
# ponytail: sed do BSD/macOS exige o argumento vazio após -i
sed -i '' -E "s/^  version \".*\"/  version \"$VER\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
ruby -c "$CASK"
git -C "$TAP_DIR" add Casks/knobler.rb
git -C "$TAP_DIR" commit -m "knobler $VER"
git -C "$TAP_DIR" push

echo ""
echo "✅ publicado. Instale com:"
echo "   brew tap luccas-silveira/knobler"
echo "   brew install --cask knobler"
```

- [ ] **Step 3: Garantir o app repo pushado (o release aponta pro remoto)**

Run: `git push`
Expected: remoto em dia (senão o tag do release aponta pra um commit antigo).

- [ ] **Step 4: Primeiro release real (o teste E2E)**

Run: `./tools/release.sh 0.17`
Expected: termina com `✅ publicado`; sem erro no `gh` nem no `git push` do tap.

- [ ] **Step 5: Verificar o release e o bump**

Run:
```bash
gh release view v0.17 | head -5
grep -E '^  (version|sha256)' ../homebrew-knobler/Casks/knobler.rb
```
Expected: o release `v0.17` existe com o asset `Knobler-0.17.zip`; o cask mostra `version "0.17"` e um `sha256` de 64 hex (não mais zeros).

- [ ] **Step 6: Instalar de verdade pelo brew (valida ad-hoc + postflight)**

Run:
```bash
brew update
brew install --cask knobler
xattr -p com.apple.quarantine /Applications/Knobler.app 2>&1 | head -1
open -a Knobler
```
Expected: instala sem erro; o `xattr -p` diz `No such xattr` (o `postflight` removeu a quarantine); o app **abre sem prompt do Gatekeeper e sem crash no launch**. Se abrir, o ad-hoc está validado na própria máquina.
Cleanup opcional: `brew uninstall --cask knobler`.

- [ ] **Step 7: Commit**

```bash
git add tools/release.sh
git commit -m "feat(dist): release.sh publica no GitHub Releases + auto-bump do cask"
```

---

### Task 5: Seção "Instalação" no `README.md` do app

Documentar o caminho do amigo e o fallback sem Homebrew.

**Files:**
- Modify: `README.md` (inserir seção "Instalação" antes da seção `## Build`)

**Interfaces:**
- Consumes: o tap/cask das Tasks 3-4.
- Produces: nada (doc).

- [ ] **Step 1: Inserir a seção antes de `## Build`**

```markdown
## Instalação

```bash
brew tap luccas-silveira/knobler
brew install --cask knobler
```

App assinado ad-hoc (sem Developer ID). O Homebrew tira a quarentena no install,
então abre limpo. Update: `brew upgrade --cask knobler` · Remover:
`brew uninstall --zap --cask knobler`.

Sem Homebrew: baixe o zip do [Releases](https://github.com/luccas-silveira/knobler/releases)
e rode `xattr -dr com.apple.quarantine /Applications/Knobler.app` uma vez.

Permissões pedidas em runtime: Acessibilidade, Gravação de Áudio do Sistema,
Automação (Spotify/Music), Calendário, Mic, Bluetooth.

```

- [ ] **Step 2: Conferir a renderização**

Run: `grep -A3 '## Instalação' README.md`
Expected: mostra o bloco de instalação.

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: seção Instalação (brew tap + cask)"
```

---

## Verificação final (E2E que só um Mac limpo confirma)

Nenhuma automação cobre isto — anotar como passo manual pós-plano: pedir a **um
amigo num Mac que não é o seu** (idealmente sem conta de dev, macOS 15/26) pra rodar
`brew tap luccas-silveira/knobler && brew install --cask knobler` e confirmar que o
app **abre** (sem crash no launch). Isso valida que o ad-hoc removeu de fato a
restrição de dispositivo da assinatura Apple Development — o risco central da pesquisa.

## Self-review (cobertura da spec)

- Versão via `$(MARKETING_VERSION)` → Task 1. ✓
- Ad-hoc re-sign + `codesign --verify` → Task 2 (steps 1,3,4). ✓
- zip `ditto` raiz=app → Task 2 (step 4). ✓
- `gh release` idempotente (`--clobber`) → Task 4 (step 2). ✓
- Tap público `homebrew-knobler` + cask (postflight, zap, depends_on, desc inglês, caveats pt-BR) → Task 3. ✓
- Auto-bump (sed version+sha, `-i ''` do BSD) → Task 4 (step 2). ✓
- Instrução do amigo **sem** `--no-quarantine` → Tasks 3 (README do tap), 5 (README do app). ✓
- Ollama/Parakeet/permissões documentados, fora do código → cask caveats (Task 3) + README (Task 5). ✓
- Fragilidade residual do free (re-quarantine fora do brew) → coberta pelo `caveats` e pela Verificação final.
