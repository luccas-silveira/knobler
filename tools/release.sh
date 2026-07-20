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

if [ "$DRY" -eq 0 ]; then
  command -v gh >/dev/null || { echo "gh não instalado" >&2; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "gh não autenticado (gh auth login)" >&2; exit 1; }
  git -C "$TAP_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || { echo "tap não encontrado em $TAP_DIR. Ajuste KNOBLER_TAP_DIR." >&2; exit 1; }
  git -C "$REPO_ROOT" branch -r --contains HEAD 2>/dev/null | grep -q . \
    || { echo "HEAD não está em nenhum branch remoto — dê 'git push' antes (o release taga este commit)." >&2; exit 1; }
  # só fontes que entram no build; ignora docs untracked pra o aviso não virar ruído
  [ -z "$(git -C "$REPO_ROOT" status --porcelain -- Knobler project.yml tools)" ] \
    || echo "⚠️  mudanças não-commitadas em fontes — o zip buildado pode divergir da tag v$VER."
fi

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

echo "==> publicando release v$VER"
if gh release view "v$VER" >/dev/null 2>&1; then
  gh release upload "v$VER" "$ZIP" --clobber
else
  # --target no commit buildado: a tag aponta pro código real, de qualquer branch
  gh release create "v$VER" "$ZIP" --title "Knobler v$VER" --notes "Knobler v$VER" \
    --target "$(git rev-parse HEAD)"
fi

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
echo "✅ publicado. Instale com:"
echo "   brew tap luccas-silveira/knobler"
echo "   brew trust luccas-silveira/knobler"
echo "   brew install --cask knobler"
