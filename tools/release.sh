#!/usr/bin/env bash
# Publica uma release do Knobler seguindo o padrão de versionamento (VERSIONING.md):
# valida SemVer > última tag, consome ## [Unreleased] do CHANGELOG, bumpa o
# project.yml, commita, builda Release, re-assina ad-hoc, zipa, cria a tag anotada,
# publica no GitHub Releases (notas = seção do CHANGELOG) e bumpa o cask.
#
# Uso: ./tools/release.sh <versão|patch|minor|major> [--dry-run]
#   <versão>: X.Y.Z explícito, OU patch|minor|major pra auto-computar da última tag.
#   --dry-run: valida + builda + assina + zipa + calcula sha, mas NÃO escreve/publica nada.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="${KNOBLER_TAP_DIR:-$REPO_ROOT/../homebrew-knobler}"
CASK="$TAP_DIR/Casks/knobler.rb"
CHANGELOG="$REPO_ROOT/CHANGELOG.md"

INPUT=""
DRY=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY=1 ;;
    -*) echo "flag desconhecida: $arg" >&2; exit 2 ;;
    *) INPUT="$arg" ;;
  esac
done
[ -n "$INPUT" ] || { echo "uso: $0 <versão|patch|minor|major> [--dry-run]" >&2; exit 2; }

cd "$REPO_ROOT"

# --- resolução e validação da versão -----------------------------------------
# retorna 0 se $1 > $2 (ambos X.Y.Z); comparação por componente (bash 3.2-safe).
ver_gt() {
  local a1="${1%%.*}" b1="${2%%.*}" ar br
  ar="${1#*.}"; br="${2#*.}"
  local a2="${ar%%.*}" b2="${br%%.*}" a3="${ar#*.}" b3="${br#*.}"
  if [ "$a1" -ne "$b1" ]; then [ "$a1" -gt "$b1" ]; return; fi
  if [ "$a2" -ne "$b2" ]; then [ "$a2" -gt "$b2" ]; return; fi
  [ "$a3" -gt "$b3" ]
}

LAST_TAG="$(git tag --list 'v*' --sort=-v:refname | head -n1)"
LAST_VER="${LAST_TAG#v}"

case "$INPUT" in
  major|minor|patch)
    base="${LAST_VER:-0.0.0}"
    MA="${base%%.*}"; rest="${base#*.}"; MI="${rest%%.*}"; PA="${rest#*.}"
    case "$INPUT" in
      major) MA=$((MA + 1)); MI=0; PA=0 ;;
      minor) MI=$((MI + 1)); PA=0 ;;
      patch) PA=$((PA + 1)) ;;
    esac
    VER="$MA.$MI.$PA"
    ;;
  *) VER="$INPUT" ;;
esac

if ! [[ "$VER" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "versão inválida: '$VER' (esperado X.Y.Z ou patch|minor|major)" >&2; exit 2
fi
if [ -n "$LAST_VER" ] && ! ver_gt "$VER" "$LAST_VER"; then
  echo "versão $VER não é maior que a última tag v$LAST_VER" >&2; exit 2
fi

# --- notas do release: seção ## [Unreleased] do CHANGELOG --------------------
[ -f "$CHANGELOG" ] || { echo "CHANGELOG.md não encontrado" >&2; exit 1; }
NOTES="$(awk '/^## \[Unreleased\]/{g=1;next} /^## /{if(g)exit} g' "$CHANGELOG" \
  | awk 'NF{f=1} f{b[++n]=$0} END{while(n>0 && b[n]~/^[ \t]*$/)n--; for(i=1;i<=n;i++)print b[i]}')"
[ -n "$NOTES" ] || { echo "## [Unreleased] vazio no CHANGELOG — adicione entradas antes de lançar." >&2; exit 2; }

# --- guards (só quando vai publicar de verdade) ------------------------------
if [ "$DRY" -eq 0 ]; then
  command -v gh >/dev/null || { echo "gh não instalado" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh não autenticado (gh auth login)" >&2; exit 1; }
  git -C "$TAP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "tap não encontrado em $TAP_DIR. Ajuste KNOBLER_TAP_DIR." >&2; exit 1; }
  BRANCH="$(git rev-parse --abbrev-ref HEAD)"
  [ "$BRANCH" != "HEAD" ] || { echo "HEAD destacado — faça checkout de um branch (o release commita o bump)." >&2; exit 1; }
  git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 \
    || { echo "branch '$BRANCH' sem upstream — configure com 'git push -u origin $BRANCH'." >&2; exit 1; }
  # fontes limpas: só o release.sh deve tocar project.yml/CHANGELOG neste commit
  [ -z "$(git status --porcelain -- Knobler project.yml tools)" ] \
    || { echo "mudanças não-commitadas em fontes — commite ou stashe antes do release." >&2; exit 1; }
  if git rev-parse -q --verify "refs/tags/v$VER" >/dev/null; then
    echo "tag v$VER já existe." >&2; exit 1
  fi
fi

# --- bump + commit (project.yml + CHANGELOG) ---------------------------------
if [ "$DRY" -eq 0 ]; then
  echo "==> bump project.yml + CHANGELOG ($VER)"
  # ponytail: sed do BSD/macOS exige o argumento vazio após -i
  sed -i '' -E "s/^([[:space:]]*MARKETING_VERSION:).*/\1 \"$VER\"/" project.yml
  sed -i '' -E "s/^([[:space:]]*CURRENT_PROJECT_VERSION:).*/\1 \"$VER\"/" project.yml
  DATE="$(date +%F)"
  # renomeia ## [Unreleased] -> abre nova [Unreleased] vazia + heading da release
  awk -v ver="$VER" -v d="$DATE" \
    '{print} /^## \[Unreleased\]/ && !done {print ""; print "## [" ver "] - " d; done=1}' \
    "$CHANGELOG" > "$CHANGELOG.tmp" && mv "$CHANGELOG.tmp" "$CHANGELOG"
  git add project.yml CHANGELOG.md
  git commit -m "release: v$VER"
fi

# --- build Release -----------------------------------------------------------
echo "==> build Release ($VER)"
# MARKETING_VERSION na linha de comando tem precedência máxima (funciona mesmo
# com .xcodeproj stale gerado com outro valor).
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
  echo "-- versão: $VER (última tag: ${LAST_VER:-nenhuma}) --"
  echo "-- notas do release (de ## [Unreleased]): --"
  printf '%s\n' "$NOTES"
  exit 0
fi

# --- tag + publicação --------------------------------------------------------
echo "==> tag anotada v$VER + push"
git tag -a "v$VER" -m "Knobler v$VER"
git push
git push origin "v$VER"

NOTES_FILE="$(mktemp)"
printf '%s\n' "$NOTES" > "$NOTES_FILE"
echo "==> publicando release v$VER"
if gh release view "v$VER" >/dev/null 2>&1; then
  gh release upload "v$VER" "$ZIP" --clobber
else
  gh release create "v$VER" "$ZIP" --title "Knobler v$VER" --notes-file "$NOTES_FILE"
fi
rm -f "$NOTES_FILE"

echo "==> bumpando o cask"
# ponytail: sed do BSD/macOS exige o argumento vazio após -i
sed -i '' -E "s/^  version \".*\"/  version \"$VER\"/" "$CASK"
sed -i '' -E "s/^  sha256 \".*\"/  sha256 \"$SHA\"/" "$CASK"
ruby -c "$CASK"
if git -C "$TAP_DIR" diff --quiet -- Casks/knobler.rb; then
  echo "   cask já em $VER/$SHA — nada a commitar no tap"
else
  git -C "$TAP_DIR" add Casks/knobler.rb
  git -C "$TAP_DIR" commit -m "knobler $VER"
  git -C "$TAP_DIR" push
fi

echo ""
echo "✅ publicado v$VER. Instale com:"
echo "   brew tap luccas-silveira/knobler && brew trust luccas-silveira/knobler && brew install knobler"
