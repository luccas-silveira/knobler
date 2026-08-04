#!/bin/bash
# Painel de acompanhamento dos mapas do wayfinder.
#   ./.wayfinder/painel.sh          → http://localhost:8123/painel.html
#   ./.wayfinder/painel.sh 9000     → outra porta
# A página lê os .md em tempo real: editou ticket, é só recarregar.
set -euo pipefail
porta="${1:-8123}"
cd "$(dirname "$0")"
echo "→ http://localhost:$porta/painel.html   (ctrl-c pra parar)"
open "http://localhost:$porta/painel.html" 2>/dev/null || true
exec python3 -m http.server "$porta" --bind 127.0.0.1
