#!/usr/bin/env bash
# Gate do preview nítido no card de chegada do WhatsApp: a ligação nos
# arquivos que o ./tools/check.sh não compila (a view do card, a lista de
# fontes do snapshot e o harness). O modelo puro é provado no
# whatsappcartaomidiacheck.swift; aqui só se confere que a view o usa.
#
# Confere:
#   - Knobler/WhatsApp/WhatsAppCartaoView.swift:
#       * não tem `.frame(height: 120)` (o quadro segue a proporção);
#       * a imagem da frente não é mais esticada: toda linha com
#         `.scaledToFill()` é o avatar (`Circle()`) ou o fundo desfocado
#         (`.blur(`), na mesma linha ou nas 3 seguintes;
#       * tem `.scaledToFit()` e `.blur(`;
#       * pede a foto inteira (`store.midia.arquivo(`) e usa o modelo
#         (`WACartaoMidia.altura(`, `WACartaoMidia.baixaArquivo(`,
#         `WACartaoMidia.duracao(`, `WACartaoMidia.tentarDeNovo(`);
#       * avisa o VM da altura do quadro (`vm.medirMidiaWhatsApp(`), senão o
#         card não cresce e o quadro mais alto sai cortado;
#   - tools/notchview-fontes.txt lista Knobler/WhatsApp/WhatsAppCartaoMidia.swift;
#   - tools/main.swift tem os cenários `whatsapp-cartao-foto-empe`,
#     `whatsapp-cartao-foto-deitada` e `whatsapp-cartao-video`.
# Linha de comentário (`//` ou `#` na lista de fontes) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappcartaomidialigacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

FIXO='.frame(height: 120)'
ESTICA='.scaledToFill()'
VIEW_TEXTOS='.scaledToFit() .blur( store.midia.arquivo( WACartaoMidia.altura( WACartaoMidia.baixaArquivo( WACartaoMidia.duracao( WACartaoMidia.tentarDeNovo( vm.medirMidiaWhatsApp('
NOVOS='Knobler/WhatsApp/WhatsAppCartaoMidia.swift'
CENARIOS='"whatsapp-cartao-foto-empe" "whatsapp-cartao-foto-deitada" "whatsapp-cartao-video"'

# codigo <arquivo>: o arquivo com as linhas de comentário trocadas por linha
# vazia (a numeração se mantém).
codigo() { sed -E 's|^[[:space:]]*//.*$||' "$1" 2>/dev/null; }

# tem <arquivo> <texto fixo>: existe linha de código com o texto.
tem() { codigo "$1" | grep -qF -- "$2"; }

# esticadas <arquivo>: linhas de código com `.scaledToFill()` sem `Circle()`
# nem `.blur(` nela ou nas 3 seguintes. Uma por linha: "<n>: <texto>".
esticadas() {
  codigo "$1" | awk -v alvo="$ESTICA" '
    { l[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (index(l[i], alvo) == 0) continue
        ok = 0
        for (j = i; j <= i + 3 && j <= NR; j++)
          if (index(l[j], "Circle()") || index(l[j], ".blur(")) ok = 1
        if (!ok) { t = l[i]; sub(/^[ \t]+/, "", t); print i ": " t }
      }
    }'
}

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local view="$r/Knobler/WhatsApp/WhatsAppCartaoView.swift"
  local ft="$r/tools/notchview-fontes.txt"
  local mn="$r/tools/main.swift"
  local f t e

  for f in "$view" "$ft" "$mn"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$view" ]; then
    if tem "$view" "$FIXO"; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppCartaoView.swift ainda tem '$FIXO' (o quadro segue a proporção, 120…200)"
      erro=1
    fi
    e=$(esticadas "$view")
    if [ -n "$e" ]; then
      echo "FALHOU: Knobler/WhatsApp/WhatsAppCartaoView.swift estica a imagem da frente com '$ESTICA' (só avatar ou fundo com .blur):"
      printf '%s\n' "$e" | sed 's/^/    /'
      erro=1
    fi
    for t in $VIEW_TEXTOS; do
      if ! tem "$view" "$t"; then
        echo "FALHOU: Knobler/WhatsApp/WhatsAppCartaoView.swift sem '$t'"
        erro=1
      fi
    done
  fi

  if [ -f "$ft" ]; then
    for t in $NOVOS; do
      if ! grep -vE '^[[:space:]]*#' "$ft" | sed 's/[[:space:]]*$//; s/^[[:space:]]*//' | grep -qxF -- "$t"; then
        echo "FALHOU: tools/notchview-fontes.txt sem '$t'"
        erro=1
      fi
    done
  fi

  if [ -f "$mn" ]; then
    for t in $CENARIOS; do
      if ! tem "$mn" "$t"; then
        echo "FALHOU: tools/main.swift sem o cenário $t"
        erro=1
      fi
    done
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

VIEW="$T/r/Knobler/WhatsApp/WhatsAppCartaoView.swift"
FT="$T/r/tools/notchview-fontes.txt"
MN="$T/r/tools/main.swift"

# repo falso com a ligação certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/Knobler/WhatsApp" "$T/r/tools"
  cat > "$VIEW" <<'EOF'
struct WhatsAppCartaoView: View {
    // antes: Image(nsImage: miniatura).resizable().scaledToFill() com .frame(height: 120)
    var body: some View {
        if c.temMiniatura {
            quadro(c)
                .frame(height: WACartaoMidia.altura(larguraDisponivel: 320, proporcao: proporcao))
                .onChange(of: proporcao) { vm.medirMidiaWhatsApp(mensagemID: c.mensagemID, altura: $1) }
        }
    }

    @ViewBuilder
    private func avatar(_ c: CartaoWhatsApp) -> some View {
        if let img = foto.imagem {
            Image(nsImage: img).resizable().scaledToFill().clipShape(Circle())
        }
    }

    private func quadro(_ c: CartaoWhatsApp) -> some View {
        ZStack {
            Image(nsImage: imagem).resizable()
                .scaledToFill()
                .blur(radius: 18)
                .overlay(Color.black.opacity(0.35))
            Image(nsImage: imagem).resizable().scaledToFit()
            if c.ehVideo, let d = WACartaoMidia.duracao(segundos: c.segundosDoVideo) { Text(d) }
        }
    }

    private func carregarFoto(_ c: CartaoWhatsApp, chave k: WAChave, mensagem m: WAMensagem) async {
        guard WACartaoMidia.baixaArquivo(tipo: m.tipo) else { return }
        while !Task.isCancelled {
            let r = await store.midia.arquivo(chave: k, mensagem: m)
            guard WACartaoMidia.tentarDeNovo(r) else { break }
            try? await Task.sleep(for: .seconds(1))
        }
    }
}
EOF
  cat > "$FT" <<'EOF'
Knobler/NotchView.swift
Knobler/WhatsApp/WhatsAppCartao.swift
Knobler/WhatsApp/WhatsAppCartaoMidia.swift
Knobler/WhatsApp/WhatsAppCartaoView.swift
EOF
  cat > "$MN" <<'EOF'
let cenarios = [
    Scenario(name: "whatsapp-cartao-foto") { vm, _, _ in waCartaoCenario(vm) },
    Scenario(name: "whatsapp-cartao-foto-empe") { vm, _, _ in waCartaoCenario(vm) },
    Scenario(name: "whatsapp-cartao-foto-deitada") { vm, _, _ in waCartaoCenario(vm) },
    Scenario(name: "whatsapp-cartao-video") { vm, _, _ in waCartaoCenario(vm) },
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

montar
caso "ligação certa (comentário com o código antigo não conta)" 0 ""

# o quadro de 120 fixo de volta
montar
sed -i '' 's|^                .frame(height: WACartaoMidia.altura(larguraDisponivel: 320, proporcao: proporcao))|                .frame(height: 120)\
                .onAppear { _ = WACartaoMidia.altura(larguraDisponivel: 320, proporcao: proporcao) }|' "$VIEW"
caso "quadro com 120 fixo" 1 "ainda tem '$FIXO'"

# a imagem da frente esticada (o código de hoje)
montar
sed -i '' 's|Image(nsImage: imagem).resizable().scaledToFit()|Image(nsImage: imagem).resizable().scaledToFill()\
            Color.clear.aspectRatio(contentMode: .fit).scaledToFit()|' "$VIEW"
caso "frente com scaledToFill" 1 "estica a imagem da frente"

# o fundo sem desfoque é imagem esticada também
montar
grep -vF -- '.blur(radius: 18)' "$VIEW" > "$VIEW.novo"; mv "$VIEW.novo" "$VIEW"
caso "fundo sem blur" 1 "estica a imagem da frente"

# a imagem esticada longe do blur (mais de 3 linhas antes) não conta como fundo
montar
sed -i '' 's|^                .scaledToFill()$|                .scaledToFill()\
                .opacity(1)\
                .saturation(1)\
                .brightness(0)|' "$VIEW"
caso "scaledToFill longe do blur" 1 "estica a imagem da frente"

# avatar com scaledToFill (com Circle) não é a frente
montar
caso "avatar com scaledToFill passa" 0 ""

for t in $VIEW_TEXTOS; do
  montar
  grep -vF -- "$t" "$VIEW" > "$VIEW.novo"; mv "$VIEW.novo" "$VIEW"
  caso "view sem $t" 1 "WhatsAppCartaoView.swift sem '$t'"
done

montar
sed -i '' 's|^            let r = await store.midia.arquivo|            // let r = await store.midia.arquivo|' "$VIEW"
caso "arquivo só em comentário" 1 "sem 'store.midia.arquivo('"

montar
rm "$VIEW"
caso "view ausente" 1 "Knobler/WhatsApp/WhatsAppCartaoView.swift não existe"

for t in $NOVOS; do
  montar
  grep -vxF -- "$t" "$FT" > "$FT.novo"; mv "$FT.novo" "$FT"
  caso "fontes sem $t" 1 "notchview-fontes.txt sem '$t'"
  montar
  sed -i '' "s|^$t|# $t|" "$FT"
  caso "fonte comentada $t" 1 "notchview-fontes.txt sem '$t'"
done

for t in $CENARIOS; do
  montar
  grep -vF -- "$t" "$MN" > "$MN.novo"; mv "$MN.novo" "$MN"
  caso "harness sem $t" 1 "sem o cenário $t"
done

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappcartaomidialigacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappcartaomidialigacaocheck ok"
