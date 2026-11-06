#!/usr/bin/env bash
# Gate da etapa 22 do WhatsApp: a seção de duas colunas ligada nos arquivos que
# o ./tools/check.sh não roda (views SwiftUI e o harness de snapshot).
#
# O whatsapptelacheck prova `WhatsAppTela` e a paginação com VM e store de
# verdade, mas não que a view chama `adotarPadrao` nem que a NotchView desenha
# a seção e a contagem; o notchfontescheck só typecheca. Confere:
#   - Knobler/WhatsApp/WhatsAppSecaoView.swift chama `WhatsAppTela.adotarPadrao(`;
#   - Knobler/WhatsApp/WhatsAppListaView.swift chama `carregarMaisConversas(conta:`
#     (a página seguinte quando a última linha aparece);
#   - Knobler/NotchView.swift tem `WhatsAppSecaoView(vm: vm)` e
#     `contagem(whatsapp.estado.sinalDaFaixa)`, não tem mais o provisório
#     `vazio("phone.bubble.fill", "WhatsApp")` e nenhum `case` com `.whatsapp`
#     cai em `EmptyView()` (o primeiro case vence e a contagem nunca sairia);
#   - tools/notchview-fontes.txt lista os três arquivos novos;
#   - tools/main.swift desenha os cenários `whatsapp-*` na janela sintética
#     (`hasPrefix("whatsapp-")`) e tem `whatsapp-lista-4143`,
#     `whatsapp-lista-8292` e `whatsapp-faixa`.
# Linha de comentário (`//`) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsapptelaligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

ADOTAR='WhatsAppTela.adotarPadrao('
PAGINAR='carregarMaisConversas(conta:'
SECAO='WhatsAppSecaoView(vm: vm)'
FAIXA='contagem(whatsapp.estado.sinalDaFaixa)'
PROVISORIO='vazio("phone.bubble.fill", "WhatsApp")'
JANELA='hasPrefix("whatsapp-")'
NOVOS='Knobler/WhatsApp/WhatsAppTela.swift Knobler/WhatsApp/WhatsAppSecaoView.swift Knobler/WhatsApp/WhatsAppListaView.swift'
CENARIOS='"whatsapp-lista-4143" "whatsapp-lista-8292" "whatsapp-faixa"'

# linha <arquivo> <texto fixo>: número da primeira linha de código (não
# comentário) que contém o texto; vazio se não houver.
linha() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | head -1 | cut -d: -f1
}

tem() { [ -n "$(linha "$1" "$2")" ]; }

# case com .whatsapp cujo corpo é EmptyView(): número da linha do case, ou vazio
whatsapp_vazio() {
  awk '
    /^[[:space:]]*\/\// { next }
    pend && /^[[:space:]]*$/ { next }
    pend { if ($0 ~ /^[[:space:]]*EmptyView\(\)/) { print pend; exit } ; pend = 0 }
    /^[[:space:]]*case[[:space:]].*\.whatsapp([,:[:space:]]|$)/ {
      # corpo na mesma linha: `case .whatsapp: EmptyView()`
      if ($0 ~ /:[[:space:]]*EmptyView\(\)/) { print NR; exit }
      if ($0 ~ /:[[:space:]]*$/) pend = NR
    }
  ' "$1"
}

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local secao="$r/Knobler/WhatsApp/WhatsAppSecaoView.swift"
  local lista="$r/Knobler/WhatsApp/WhatsAppListaView.swift"
  local notch="$r/Knobler/NotchView.swift"
  local fontes="$r/tools/notchview-fontes.txt"
  local harness="$r/tools/main.swift"
  local f n

  for f in "$secao" "$lista" "$notch" "$fontes" "$harness"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$secao" ] && ! tem "$secao" "$ADOTAR"; then
    echo "FALHOU: Knobler/WhatsApp/WhatsAppSecaoView.swift sem '$ADOTAR'"
    erro=1
  fi

  if [ -f "$lista" ] && ! tem "$lista" "$PAGINAR"; then
    echo "FALHOU: Knobler/WhatsApp/WhatsAppListaView.swift sem '$PAGINAR'"
    erro=1
  fi

  if [ -f "$notch" ]; then
    for f in "$SECAO" "$FAIXA"; do
      if ! tem "$notch" "$f"; then
        echo "FALHOU: Knobler/NotchView.swift sem '$f'"
        erro=1
      fi
    done
    if tem "$notch" "$PROVISORIO"; then
      echo "FALHOU: Knobler/NotchView.swift ainda tem o provisório '$PROVISORIO' (linha $(linha "$notch" "$PROVISORIO"))"
      erro=1
    fi
    n=$(whatsapp_vazio "$notch")
    if [ -n "$n" ]; then
      echo "FALHOU: Knobler/NotchView.swift: case com .whatsapp em EmptyView() (linha $n) esconde a contagem da faixa"
      erro=1
    fi
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
    if ! tem "$harness" "$JANELA"; then
      echo "FALHOU: tools/main.swift sem '$JANELA' (ScrollView sai preto no ImageRenderer)"
      erro=1
    fi
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
            WhatsAppListaView(vm: vm)
            Color.clear
                .task(id: vm.whatsappContaSelecionada) {
                    await WhatsAppTela.adotarPadrao(vm: vm, store: store)
                }
        }
    }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppListaView.swift" <<'EOF'
import SwiftUI

struct WhatsAppListaView: View {
    @ObservedObject var vm: NotchViewModel
    @ObservedObject var store = WhatsAppStore.shared

    var body: some View {
        Text("linha")
            .onAppear { Task { await store.carregarMaisConversas(conta: "x") } }
    }
}
EOF
  cat > "$T/r/Knobler/NotchView.swift" <<'EOF'
import SwiftUI

struct NotchView: View {
    @ObservedObject private var whatsapp = WhatsAppStore.shared

    var conteudo: some View {
        switch vm.focus {
        case .musica: vazio("music.note", "Música")
        case .whatsapp: WhatsAppSecaoView(vm: vm)
        default: EmptyView()
        }
    }

    @ViewBuilder
    private func sinalVivo(_ s: NotchSection) -> some View {
        switch s {
        case .historico:
            contagem(history.items.count)
        case .whatsapp:
            contagem(whatsapp.estado.sinalDaFaixa)
        case .espelho, .mensagens, .agenda, .cor:
            EmptyView()
        }
    }
}
EOF
  cat > "$T/r/tools/notchview-fontes.txt" <<'EOF'
# fontes
Knobler/NotchView.swift
Knobler/WhatsApp/WhatsAppStore.swift
Knobler/WhatsApp/WhatsAppTela.swift
Knobler/WhatsApp/WhatsAppSecaoView.swift
Knobler/WhatsApp/WhatsAppListaView.swift
EOF
  cat > "$T/r/tools/main.swift" <<'EOF'
let scenarios = [
    Scenario(name: "whatsapp-lista-4143", realNotch: true, frameWidth: 860, frameHeight: 480) { vm, _, _ in },
    Scenario(name: "whatsapp-lista-8292", realNotch: true, frameWidth: 860, frameHeight: 480) { vm, _, _ in },
    Scenario(name: "whatsapp-faixa", realNotch: true, frameWidth: 860, frameHeight: 480) { vm, _, _ in },
]
if scenario.name.hasPrefix("expanded-") || scenario.name.hasPrefix("whatsapp-") {
    janela()
}
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
LIS="$T/r/Knobler/WhatsApp/WhatsAppListaView.swift"
NV="$T/r/Knobler/NotchView.swift"
FT="$T/r/tools/notchview-fontes.txt"
MN="$T/r/tools/main.swift"

montar
caso "ligação certa" 0 ""

montar
# comentário citando o provisório não conta
sed -i '' 's|^struct NotchView: View {|// antes: vazio("phone.bubble.fill", "WhatsApp")\
struct NotchView: View {|' "$NV"
caso "provisório só em comentário" 0 ""

montar
sed -i '' '/WhatsAppTela.adotarPadrao(/d' "$SEC"
caso "seção sem adotarPadrao" 1 "sem '$ADOTAR'"

montar
sed -i '' 's|^                    await WhatsAppTela.adotarPadrao(|                    // await WhatsAppTela.adotarPadrao(|' "$SEC"
caso "adotarPadrao só em comentário" 1 "sem '$ADOTAR'"

montar
sed -i '' 's|store.carregarMaisConversas(conta: "x")|store.recarregar()|' "$LIS"
caso "lista sem paginar" 1 "sem '$PAGINAR'"

montar
sed -i '' 's|case .whatsapp: WhatsAppSecaoView(vm: vm)|case .whatsapp: vazio("phone.bubble.fill", "WhatsApp")|' "$NV"
caso "NotchView sem a seção (provisório)" 1 "sem '$SECAO'"
caso "provisório de volta" 1 "ainda tem o provisório"

montar
sed -i '' '/contagem(whatsapp.estado.sinalDaFaixa)/d' "$NV"
caso "faixa sem contagem" 1 "sem '$FAIXA'"

montar
# .whatsapp esquecido na lista do EmptyView, ANTES da contagem: o primeiro vence
sed -i '' 's|^        case .historico:|        case .espelho, .whatsapp, .agenda:\
            EmptyView()\
        case .historico:|' "$NV"
caso ".whatsapp na lista do EmptyView" 1 "esconde a contagem da faixa"

montar
sed -i '' 's|^        case .espelho, .mensagens, .agenda, .cor:|        case .espelho, .mensagens, .whatsapp, .agenda, .cor:|' "$NV"
caso ".whatsapp também na lista do EmptyView" 1 "esconde a contagem da faixa"

montar
sed -i '' 's|^        case .historico:|        case .whatsapp: EmptyView()\
        case .historico:|' "$NV"
caso "case .whatsapp: EmptyView() numa linha" 1 "esconde a contagem da faixa"

for f in $NOVOS; do
  montar
  grep -vxF -- "$f" "$FT" > "$FT.novo"; mv "$FT.novo" "$FT"
  caso "fontes sem $f" 1 "tools/notchview-fontes.txt sem '$f'"
done

montar
sed -i '' 's|Knobler/WhatsApp/WhatsAppTela.swift|# Knobler/WhatsApp/WhatsAppTela.swift|' "$FT"
caso "fonte comentada" 1 "sem 'Knobler/WhatsApp/WhatsAppTela.swift'"

montar
sed -i '' 's/ || scenario.name.hasPrefix("whatsapp-")//' "$MN"
caso "harness sem janela sintética" 1 "sem '$JANELA'"

for f in $CENARIOS; do
  montar
  grep -vF -- "$f" "$MN" > "$MN.novo"; mv "$MN.novo" "$MN"
  caso "harness sem $f" 1 "sem o cenário $f"
done

montar
rm "$SEC"
caso "WhatsAppSecaoView.swift ausente" 1 "Knobler/WhatsApp/WhatsAppSecaoView.swift não existe"

montar
rm "$LIS"
caso "WhatsAppListaView.swift ausente" 1 "Knobler/WhatsApp/WhatsAppListaView.swift não existe"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsapptelaligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsapptelaligacaocheck ok"
