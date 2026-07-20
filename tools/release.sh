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
