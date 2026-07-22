#!/bin/bash
# Cria (uma vez só) o certificado local de assinatura de código do Knobler.
#
# Por quê: o release era assinado ad-hoc (`codesign --sign -`), e assinatura
# ad-hoc não tem identidade estável — o TCC ancora a permissão de Acessibilidade
# no cdhash do binário e a revoga a CADA versão nova. Resultado: o ditado morria
# em silêncio depois de todo update. Com um certificado fixo no keychain, o
# csreq gravado pelo TCC casa entre builds e a permissão sobrevive.
#
# Rode uma vez por máquina. Depois disso, `tools/release.sh` acha a identidade
# sozinho. O macOS pode pedir sua senha ao marcar o certificado como confiável.
set -euo pipefail

CN="${KNOBLER_SIGN_IDENTITY:-Knobler Local Signing}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -qF "$CN"; then
  echo "==> identidade \"$CN\" já existe — nada a fazer"
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> gerando certificado self-signed \"$CN\" (20 anos)"
openssl req -x509 -newkey rsa:2048 -nodes -days 7300 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -subj "/CN=$CN" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning" 2>/dev/null

# -legacy: o Security.framework não lê PKCS#12 com a cifra padrão do OpenSSL 3.
# Senha efêmera porque `-P ""` faz o `security import` falhar com
# "MAC verification failed"; o .p12 morre com o TMP no trap.
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:knobler

echo "==> importando no login keychain"
# -A: qualquer binário pode usar a chave, senão o codesign pede senha a cada build
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P knobler -A >/dev/null

echo "==> marcando como confiável para assinatura de código"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep -F "$CN"
echo "==> pronto. rode ./tools/release.sh normalmente."
