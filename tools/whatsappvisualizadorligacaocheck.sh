#!/usr/bin/env bash
# Gate da etapa 1 do visualizador do WhatsApp: foto e vídeo abrem dentro do
# notch, ligado nos arquivos que o ./tools/check.sh não compila (views SwiftUI
# e o harness de snapshot).
#
# O whatsappvisualizadorcheck prova o modelo (`WAVisualizador`, `.verNoNotch`,
# textos) e o estado por tela no NotchViewModel; aqui se confere que as views
# usam isso:
#   - Knobler/WhatsApp/WhatsAppBolhaView.swift não chama mais
#     `NSWorkspace.shared.open(` (foto/vídeo não vão pro Pré-Visualização no
#     clique) e abre o visualizador por `verMidiaWhatsApp(`;
#   - Knobler/WhatsApp/WhatsAppConversaView.swift mostra
#     `WhatsAppVisualizadorView(` por cima, olhando `whatsappVisualizando`, e
#     também não chama `NSWorkspace.shared.open(`;
#   - a seção e a lista não desenham o visualizador (ele cobre só a coluna da
#     conversa, não a lista);
#   - Knobler/WhatsApp/WhatsAppVisualizadorView.swift: pede o arquivo
#     (`.arquivo(chave:`) e tenta de novo (`Task.sleep(`), decide por
#     `WAVisualizador.estado(`, mostra `WAVisualizador.aviso(`,
#     `WAVisualizador.subtitulo(` e `WATextos.buscandoNoCelular(`; a foto em
#     `.scaledToFit()`; vídeo com AVKit que toca ao abrir (`.play()`) e para
#     ao fechar (`.pause()` ou `replaceCurrentItem(with: nil)`); os três botões
#     (`WATextos.abrirNoPreVisualizacao` com `NSWorkspace.shared.open(`,
#     `WATextos.mostrarNoFinder` com `activateFileViewerSelecting(`,
#     `WATextos.fechar` com `fecharVisualizadorWhatsApp(`); alerta em
#     `exclamationmark.triangle` (o `photo.badge.exclamationmark` é macOS 15+);
#   - tools/notchview-fontes.txt lista WhatsAppVisualizador.swift e
#     WhatsAppVisualizadorView.swift;
#   - tools/main.swift tem os cenários whatsapp-visualizador-foto,
#     -carregando, -video e -indisponivel.
# Linha de comentário (`//`) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappvisualizadorligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

ABRIR_APP='NSWorkspace.shared.open('
VER='verMidiaWhatsApp('
VIEW='WhatsAppVisualizadorView('
ESTADO_VM='whatsappVisualizando'
# o que a view do visualizador tem que conter (uma linha de código cada)
EXIGIDOS_VIS=(
  '.arquivo(chave:'
  'Task.sleep('
  'WAVisualizador.estado('
  'WAVisualizador.aviso('
  'WAVisualizador.subtitulo('
  'WATextos.buscandoNoCelular('
  '.scaledToFit()'
  'import AVKit'
  '.play()'
  'WATextos.abrirNoPreVisualizacao'
  'NSWorkspace.shared.open('
  'WATextos.mostrarNoFinder'
  'activateFileViewerSelecting('
  'WATextos.fechar'
  'fecharVisualizadorWhatsApp('
  'exclamationmark.triangle'
)
PARAR_A='.pause()'
PARAR_B='replaceCurrentItem(with: nil)'
SIMBOLO_15='photo.badge.exclamationmark'
NOVOS='Knobler/WhatsApp/WhatsAppVisualizador.swift Knobler/WhatsApp/WhatsAppVisualizadorView.swift'
CENARIOS='"whatsapp-visualizador-foto" "whatsapp-visualizador-carregando" "whatsapp-visualizador-video" "whatsapp-visualizador-indisponivel"'

# linha <arquivo> <texto fixo>: número da primeira linha de código (não
# comentário) que contém o texto; vazio se não houver.
linha() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | head -1 | cut -d: -f1
}

tem() { [ -n "$(linha "$1" "$2")" ]; }

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local bolha="$r/Knobler/WhatsApp/WhatsAppBolhaView.swift"
  local conv="$r/Knobler/WhatsApp/WhatsAppConversaView.swift"
  local secao="$r/Knobler/WhatsApp/WhatsAppSecaoView.swift"
  local lista="$r/Knobler/WhatsApp/WhatsAppListaView.swift"
  local vis="$r/Knobler/WhatsApp/WhatsAppVisualizadorView.swift"
  local fontes="$r/tools/notchview-fontes.txt"
  local harness="$r/tools/main.swift"
  local f

  for f in "$bolha" "$conv" "$secao" "$lista" "$vis" "$fontes" "$harness"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$bolha" ]; then
    if tem "$bolha" "$ABRIR_APP"; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppBolhaView.swift ainda abre no app padrão no clique ('$ABRIR_APP', linha $(linha "$bolha" "$ABRIR_APP"))"
      erro=1
    fi
    if ! tem "$bolha" "$VER"; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppBolhaView.swift sem '$VER' (o clique não abre o visualizador)"
      erro=1
    fi
  fi

  if [ -f "$conv" ]; then
    for f in "$VIEW" "$ESTADO_VM"; do
      if ! tem "$conv" "$f"; then
        echo "FALHOU: Knobler/WhatsApp/WhatsAppConversaView.swift sem '$f'"
        erro=1
      fi
    done
    if tem "$conv" "$ABRIR_APP"; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppConversaView.swift chama '$ABRIR_APP' (só o botão do visualizador abre no app padrão)"
      erro=1
    fi
  fi

  for f in "$secao" "$lista"; do
    if [ -f "$f" ] && tem "$f" "$VIEW"; then
      echo "FALHOU: ${f#"$r"/} desenha '$VIEW': o visualizador cobre só a coluna da conversa"
      erro=1
    fi
  done

  if [ -f "$vis" ]; then
    for f in "${EXIGIDOS_VIS[@]}"; do
      if ! tem "$vis" "$f"; then
        echo "FALHOU: Knobler/WhatsApp/WhatsAppVisualizadorView.swift sem '$f'"
        erro=1
      fi
    done
    if ! tem "$vis" "$PARAR_A" && ! tem "$vis" "$PARAR_B"; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppVisualizadorView.swift não para o vídeo ao fechar ('$PARAR_A' ou '$PARAR_B')"
      erro=1
    fi
    if tem "$vis" "$SIMBOLO_15"; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppVisualizadorView.swift usa '$SIMBOLO_15' (macOS 15+; o target é 14.2)"
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
  cat > "$T/r/Knobler/WhatsApp/WhatsAppBolhaView.swift" <<'EOF'
import SwiftUI

struct WhatsAppBolhaView: View {
    @ObservedObject var vm: NotchViewModel

    private func executar(_ acao: WAAcaoDaBolha) async {
        switch acao {
        case .verNoNotch: vm.verMidiaWhatsApp(chave: chave.texto, mensagemID: m.id)
        case .mostrarNoFinder: NSWorkspace.shared.activateFileViewerSelecting([url])
        default: break
        }
    }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppConversaView.swift" <<'EOF'
import SwiftUI

struct WhatsAppConversaView: View {
    @ObservedObject var vm: NotchViewModel

    var body: some View {
        coluna
            .overlay {
                if let v = vm.whatsappVisualizando, v.chave == chave.texto {
                    WhatsAppVisualizadorView(vm: vm, visto: v, store: store)
                }
            }
    }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppSecaoView.swift" <<'EOF'
import SwiftUI

struct WhatsAppSecaoView: View {
    var body: some View {
        HStack { WhatsAppListaView(vm: vm); WhatsAppConversaView(vm: vm) }
    }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppListaView.swift" <<'EOF'
import SwiftUI

struct WhatsAppListaView: View {
    var body: some View { Text("linha") }
}
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppVisualizadorView.swift" <<'EOF'
import AVKit
import SwiftUI

struct WhatsAppVisualizadorView: View {
    @State private var player: AVPlayer?

    var body: some View {
        VStack {
            Text(WAVisualizador.subtitulo(conversa: c.nome, ts: m.ts, agora: Date(), calendario: .current))
            Button(WATextos.abrirNoPreVisualizacao) { NSWorkspace.shared.open(url) }
            Button(WATextos.mostrarNoFinder) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            Button(WATextos.fechar) { player?.pause(); vm.fecharVisualizadorWhatsApp() }
            switch estado {
            case .carregando: Text(WATextos.buscandoNoCelular(video: video))
            case let .foto(u): Image(nsImage: NSImage(contentsOf: u)!).resizable().scaledToFit()
            case .video: VideoPlayer(player: player).onAppear { player?.play() }
            default:
                if let a = WAVisualizador.aviso(estado, mensagem: m, conversa: c) {
                    Image(systemName: "exclamationmark.triangle"); Text(a.titulo)
                }
            }
        }
        .task {
            for _ in 0..<180 {
                let r = await store.midia.arquivo(chave: chave, mensagem: m)
                estado = WAVisualizador.estado(resultado: r, midia: midia)
                guard r == .aguardando else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}
EOF
  cat > "$T/r/tools/notchview-fontes.txt" <<'EOF'
# fontes
Knobler/NotchView.swift
Knobler/WhatsApp/WhatsAppConversaView.swift
Knobler/WhatsApp/WhatsAppVisualizador.swift
Knobler/WhatsApp/WhatsAppVisualizadorView.swift
EOF
  cat > "$T/r/tools/main.swift" <<'EOF'
let scenarios = [
    Scenario(name: "whatsapp-visualizador-foto", realNotch: true) { vm, _, _ in },
    Scenario(name: "whatsapp-visualizador-carregando", realNotch: true) { vm, _, _ in },
    Scenario(name: "whatsapp-visualizador-video", realNotch: true) { vm, _, _ in },
    Scenario(name: "whatsapp-visualizador-indisponivel", realNotch: true) { vm, _, _ in },
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

BOL="$T/r/Knobler/WhatsApp/WhatsAppBolhaView.swift"
CONV="$T/r/Knobler/WhatsApp/WhatsAppConversaView.swift"
SEC="$T/r/Knobler/WhatsApp/WhatsAppSecaoView.swift"
LIS="$T/r/Knobler/WhatsApp/WhatsAppListaView.swift"
VIS="$T/r/Knobler/WhatsApp/WhatsAppVisualizadorView.swift"
FT="$T/r/tools/notchview-fontes.txt"
MN="$T/r/tools/main.swift"

montar
caso "ligação certa" 0 ""

montar
# o jeito antigo: clique em foto/vídeo abre no app padrão
sed -i '' 's|case .verNoNotch: vm.verMidiaWhatsApp(chave: chave.texto, mensagemID: m.id)|case .abrirArquivo: NSWorkspace.shared.open(url)|' "$BOL"
caso "bolha ainda abre no Pré-Visualização" 1 "ainda abre no app padrão"
caso "bolha sem verMidiaWhatsApp" 1 "sem '$VER'"

montar
# abre o visualizador E continua abrindo no app padrão
sed -i '' 's|^        default: break|        case .abrirArquivo: NSWorkspace.shared.open(url)\
        default: break|' "$BOL"
caso "bolha abre nos dois" 1 "ainda abre no app padrão"

montar
# comentário citando o open não conta
sed -i '' 's|^struct WhatsAppBolhaView: View {|// antes: NSWorkspace.shared.open(url)\
struct WhatsAppBolhaView: View {|' "$BOL"
caso "open só em comentário na bolha" 0 ""

montar
sed -i '' 's|^        case .verNoNotch: vm.verMidiaWhatsApp(|        // case .verNoNotch: vm.verMidiaWhatsApp(|' "$BOL"
caso "verMidiaWhatsApp só em comentário" 1 "sem '$VER'"

montar
sed -i '' '/WhatsAppVisualizadorView(vm: vm/d' "$CONV"
caso "conversa sem o visualizador" 1 "WhatsAppConversaView.swift sem '$VIEW'"

montar
sed -i '' 's|if let v = vm.whatsappVisualizando, v.chave == chave.texto {|if true {|' "$CONV"
caso "conversa não olha o estado do VM" 1 "sem '$ESTADO_VM'"

montar
sed -i '' 's|^        coluna$|        coluna.onTapGesture { NSWorkspace.shared.open(url) }|' "$CONV"
caso "conversa abre no app padrão" 1 "WhatsAppConversaView.swift chama"

montar
# o visualizador por cima da seção inteira cobriria a lista
sed -i '' 's|HStack { WhatsAppListaView(vm: vm); WhatsAppConversaView(vm: vm) }|HStack { WhatsAppListaView(vm: vm); WhatsAppConversaView(vm: vm) }.overlay { WhatsAppVisualizadorView(vm: vm) }|' "$SEC"
caso "visualizador na seção" 1 "WhatsAppSecaoView.swift desenha"

montar
sed -i '' 's|Text("linha")|Text("linha").overlay { WhatsAppVisualizadorView(vm: vm) }|' "$LIS"
caso "visualizador na lista" 1 "WhatsAppListaView.swift desenha"

for f in "${EXIGIDOS_VIS[@]}"; do
  montar
  grep -vF -- "$f" "$VIS" > "$VIS.novo"; mv "$VIS.novo" "$VIS"
  caso "visualizador sem $f" 1 "WhatsAppVisualizadorView.swift sem '$f'"
done

montar
# o botão Abrir no Pré-Visualização some (o open só existia nele)
sed -i '' 's|Button(WATextos.abrirNoPreVisualizacao) { NSWorkspace.shared.open(url) }|Button(WATextos.abrirNoPreVisualizacao) { }|' "$VIS"
caso "botão abrir sem open" 1 "sem 'NSWorkspace.shared.open('"

montar
sed -i '' 's|player?.pause(); ||' "$VIS"
caso "fechar não para o vídeo" 1 "não para o vídeo ao fechar"

montar
sed -i '' 's|player?.pause(); |player?.replaceCurrentItem(with: nil); |' "$VIS"
caso "para o vídeo trocando o item" 0 ""

montar
sed -i '' 's|"exclamationmark.triangle"|"photo.badge.exclamationmark"|' "$VIS"
caso "símbolo do macOS 15" 1 "macOS 15+"

for f in $NOVOS; do
  montar
  grep -vxF -- "$f" "$FT" > "$FT.novo"; mv "$FT.novo" "$FT"
  caso "fontes sem $f" 1 "tools/notchview-fontes.txt sem '$f'"
done

montar
sed -i '' 's|^Knobler/WhatsApp/WhatsAppVisualizadorView.swift|# Knobler/WhatsApp/WhatsAppVisualizadorView.swift|' "$FT"
caso "fonte comentada" 1 "sem 'Knobler/WhatsApp/WhatsAppVisualizadorView.swift'"

for f in $CENARIOS; do
  montar
  grep -vF -- "$f" "$MN" > "$MN.novo"; mv "$MN.novo" "$MN"
  caso "harness sem $f" 1 "sem o cenário $f"
done

montar
rm "$VIS"
caso "WhatsAppVisualizadorView.swift ausente" 1 "Knobler/WhatsApp/WhatsAppVisualizadorView.swift não existe"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappvisualizadorligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappvisualizadorligacaocheck ok"
