#!/usr/bin/env bash
# Gate da etapa 23 do WhatsApp: os estados de conexão e o pareamento ligados
# nos arquivos que o ./tools/check.sh não roda (views SwiftUI e o harness de
# snapshot).
#
# O whatsappqrcheck prova o QR e o que o estado faz em `iniciarPareamento`,
# `gerarOutroQR` e `tentarDeNovo`; o notchfontescheck só typecheca. Nenhum dos
# dois vê se a view chama isso nem se o snapshot desenha os estados. Confere:
#   - Knobler/WhatsApp/WhatsAppSecaoView.swift usa `WhatsAppEstadosView(` (a
#     coluna direita fora da conversa; o aviso da esquerda com a conta
#     deslogada já sai da WhatsAppListaView desde a etapa 22);
#   - Knobler/WhatsApp/WhatsAppEstadosView.swift desenha o QR com `WAQR.imagem(`,
#     pede o pareamento quando `precisaIniciarPareamento(` manda
#     (`iniciarPareamento()`), tem o "Gerar outro" (`gerarOutroQR()`), o
#     "Tentar de novo" (`tentarDeNovo()`), o Copiar (`NSPasteboard.general`) e o
#     apoio da chave por `apoioDaChave(ausente:`;
#   - tools/notchview-fontes.txt lista os dois arquivos novos;
#   - tools/main.swift tem os cenários dos nove estados e o QR sintético
#     `"2@knobler-snapshot"`.
# Linha de comentário (`//`) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappestadosligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SECAO_USA='WhatsAppEstadosView('
ESTADOS_USA='WAQR.imagem( precisaIniciarPareamento( iniciarPareamento() gerarOutroQR() tentarDeNovo() NSPasteboard.general apoioDaChave(ausente:'
NOVOS='Knobler/WhatsApp/WhatsAppQR.swift Knobler/WhatsApp/WhatsAppEstadosView.swift'
CENARIOS='"whatsapp-ponte-fora" "whatsapp-chave" "whatsapp-chave-ausente" "whatsapp-incompativel" "whatsapp-qr" "whatsapp-qr-expirado" "whatsapp-carregando" "whatsapp-vazio" "whatsapp-desconectada" "2@knobler-snapshot"'

# linha <arquivo> <texto fixo>: número da primeira linha de código (não
# comentário) que contém o texto; vazio se não houver.
linha() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | head -1 | cut -d: -f1
}

tem() { [ -n "$(linha "$1" "$2")" ]; }

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local secao="$r/Knobler/WhatsApp/WhatsAppSecaoView.swift"
  local estados="$r/Knobler/WhatsApp/WhatsAppEstadosView.swift"
  local fontes="$r/tools/notchview-fontes.txt"
  local harness="$r/tools/main.swift"
  local f

  for f in "$secao" "$estados" "$fontes" "$harness"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$secao" ]; then
    for f in $SECAO_USA; do
      if ! tem "$secao" "$f"; then
        echo "FALHOU: Knobler/WhatsApp/WhatsAppSecaoView.swift sem '$f'"
        erro=1
      fi
    done
  fi

  if [ -f "$estados" ]; then
    for f in $ESTADOS_USA; do
      if ! tem "$estados" "$f"; then
        echo "FALHOU: Knobler/WhatsApp/WhatsAppEstadosView.swift sem '$f'"
        erro=1
      fi
    done
  fi

  if [ -f "$fontes" ]; then
    for f in $NOVOS; do
      if ! grep -qxF -- "$f" "$fontes"; then
        echo "FALHOU: tools/notchview-fontes.txt sem '$f'"
        erro=1
      fi
    done
  fi

  if [ -f "$harness" ]; then
    for f in $CENARIOS; do
      if ! tem "$harness" "$f"; then
        echo "FALHOU: tools/main.swift sem o cenário $f"
        erro=1
      fi
    done
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# repo falso com a ligação certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/Knobler/WhatsApp" "$T/r/tools"
  cat > "$T/r/Knobler/WhatsApp/WhatsAppSecaoView.swift" <<'EOF'
import SwiftUI

struct WhatsAppSecaoView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var store = WhatsAppStore.shared

    var body: some View {
        HStack(spacing: 12) {
            if WhatsAppTela.esquerda(conta: nil) == .semPareamento {
                Text(WATextos.semPareamento)
            } else {
                WhatsAppListaView(vm: vm)
            }
            WhatsAppEstadosView(tela: .qr, store: store)
        }
    }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppEstadosView.swift" <<'EOF'
import AppKit
import SwiftUI

struct WhatsAppEstadosView: View {
    let tela: WATelaDireita
    @ObservedObject var store: WhatsAppStore

    var body: some View {
        VStack {
            if let img = WAQR.imagem(store.estado.pareamento?.qr ?? "", lado: 128) {
                Image(decorative: img, scale: 1)
            }
            Button(WATextos.qrGerarOutro) { Task { await store.gerarOutroQR() } }
            Button(WATextos.tentarDeNovo) { Task { await store.tentarDeNovo() } }
            Button("Copiar") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(WATextos.ponteForaComando, forType: .string)
            }
            Text(WATextos.apoioDaChave(ausente: true))
        }
        .task {
            if WhatsAppTela.precisaIniciarPareamento(conta: nil, pareamento: store.estado.pareamento) {
                await store.iniciarPareamento()
            }
        }
    }
}
EOF
  cat > "$T/r/tools/notchview-fontes.txt" <<'EOF'
# fontes
Knobler/WhatsApp/WhatsAppStore.swift
Knobler/WhatsApp/WhatsAppQR.swift
Knobler/WhatsApp/WhatsAppSecaoView.swift
Knobler/WhatsApp/WhatsAppEstadosView.swift
EOF
  cat > "$T/r/tools/main.swift" <<'EOF'
let qrSintetico = "2@knobler-snapshot"
let scenarios = [
    Scenario(name: "whatsapp-ponte-fora", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-chave", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-chave-ausente", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-incompativel", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-qr", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-qr-expirado", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-carregando", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-vazio", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
    Scenario(name: "whatsapp-desconectada", realNotch: true, frameHeight: 480, frameWidth: 860) { vm, _, _ in },
]
EOF
}

AUTO=0
# caso <nome> <código esperado> <texto esperado ou vazio> -- monta $T/r antes
caso() {
  local nome="$1" esperado="$2" texto="$3" saida codigo
  saida=$(verificar "$T/r" 2>&1); codigo=$?
  if [ "$codigo" != "$esperado" ]; then
    echo "autoteste ($nome): saiu com $codigo, esperado $esperado"
    printf '%s\n' "$saida" | sed 's/^/    | /'
    AUTO=1
  elif [ -n "$texto" ] && ! printf '%s\n' "$saida" | grep -qF -- "$texto"; then
    echo "autoteste ($nome): saída sem '$texto'"
    printf '%s\n' "$saida" | sed 's/^/    | /'
    AUTO=1
  fi
}

SEC="$T/r/Knobler/WhatsApp/WhatsAppSecaoView.swift"
EST="$T/r/Knobler/WhatsApp/WhatsAppEstadosView.swift"
FT="$T/r/tools/notchview-fontes.txt"
MN="$T/r/tools/main.swift"

montar
caso "ligação certa" 0 ""

for f in $SECAO_USA; do
  montar
  grep -vF -- "$f" "$SEC" > "$SEC.novo"; mv "$SEC.novo" "$SEC"
  caso "seção sem $f" 1 "WhatsAppSecaoView.swift sem '$f'"
done

montar
sed -i '' 's|^            WhatsAppEstadosView(|            // WhatsAppEstadosView(|' "$SEC"
caso "estados só em comentário" 1 "WhatsAppSecaoView.swift sem 'WhatsAppEstadosView('"

for f in $ESTADOS_USA; do
  montar
  grep -vF -- "$f" "$EST" > "$EST.novo"; mv "$EST.novo" "$EST"
  caso "estados sem $f" 1 "WhatsAppEstadosView.swift sem '$f'"
done

montar
sed -i '' 's|^                await store.iniciarPareamento()|                // await store.iniciarPareamento()|' "$EST"
caso "iniciarPareamento só em comentário" 1 "sem 'iniciarPareamento()'"

for f in $NOVOS; do
  montar
  grep -vxF -- "$f" "$FT" > "$FT.novo"; mv "$FT.novo" "$FT"
  caso "fontes sem $f" 1 "tools/notchview-fontes.txt sem '$f'"
done

montar
sed -i '' 's|^Knobler/WhatsApp/WhatsAppQR.swift|# Knobler/WhatsApp/WhatsAppQR.swift|' "$FT"
caso "fonte comentada" 1 "sem 'Knobler/WhatsApp/WhatsAppQR.swift'"

for f in $CENARIOS; do
  montar
  grep -vF -- "$f" "$MN" > "$MN.novo"; mv "$MN.novo" "$MN"
  caso "harness sem $f" 1 "sem o cenário $f"
done

montar
rm "$EST"
caso "WhatsAppEstadosView.swift ausente" 1 "Knobler/WhatsApp/WhatsAppEstadosView.swift não existe"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappestadosligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappestadosligacaocheck ok"
