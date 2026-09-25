#!/usr/bin/env bash
# Builda o site e publica dist/ no servidor (nginx lê de /var/www/knobler-site).
# Uso: site/deploy.sh [--dry-run]   (--dry-run builda e lista o que o rsync enviaria)
set -euo pipefail
cd "$(dirname "$0")"

RSYNC_FLAGS=()
[ "${1:-}" = "--dry-run" ] && RSYNC_FLAGS=(--dry-run --itemize-changes)

npm ci
npm run build
rsync -az --delete ${RSYNC_FLAGS[@]+"${RSYNC_FLAGS[@]}"} dist/ root@147.79.87.179:/var/www/knobler-site/
