#!/usr/bin/env bash
# Gate da etapa 26 do WhatsApp: o card de chegada ligado nos arquivos que o
# ./tools/check.sh não compila (NotchView, AppDelegate, a view do card e o
# harness de snapshot).
#
# O whatsappintegracaocheck prova a `WhatsAppIntegracao` e o
# `responderCartao` com VM e store de verdade, mas não que o app cria a
# integração e a liga ao store, nem que a NotchView desenha o card. Confere:
#   - Knobler/NotchView.swift tem `vm.aplicarCartaoWhatsApp(em: &layout)` numa
#     linha entre `private var presentation: NotchPresentation {` e o
#     `return NotchPresentation(` que fecha essa propriedade, e desenha
#     `WhatsAppCartaoView(vm: vm`;
#   - Knobler/KnoblerApp.swift tem `WhatsAppIntegracao(telas:`,
#     `WhatsAppStore.shared.aoChegarMensagem =` e
#     `WhatsAppStore.shared.aoDispensarCartao =`;
#   - Knobler/WhatsApp/WhatsAppCartaoView.swift fecha pelo store
#     (`dispensarCartao(chave:`), responde pelo store (`responderCartao(`),
#     abre a conversa na tela (`abrirWhatsApp(chave:`), liga o campo ao
#     rascunho (`definirRascunho(`) e avisa o foco (`atualizarEdicaoWhatsApp(`
#     e `campoEmUso`);
#   - tools/notchview-fontes.txt lista WhatsAppIntegracao.swift e
#     WhatsAppCartaoView.swift;
#   - tools/main.swift tem os cenários `whatsapp-cartao-texto`,
#     `whatsapp-cartao-grupo`, `whatsapp-cartao-foto`,
#     `whatsapp-cartao-agrupado` e `whatsapp-cartao-respondendo`.
# Linha de comentário (`//` ou `#` na lista de fontes) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappintegracaoligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

APLICAR='vm.aplicarCartaoWhatsApp(em: &layout)'
INICIO='private var presentation: NotchPresentation {'
FIM='return NotchPresentation('
CARTAO='WhatsAppCartaoView(vm: vm'
INTEGRACAO='WhatsAppIntegracao(telas:'
CHEGADA='WhatsAppStore.shared.aoChegarMensagem ='
DISPENSA='WhatsAppStore.shared.aoDispensarCartao ='
VIEW_TEXTOS='dispensarCartao(chave: responderCartao( abrirWhatsApp(chave: definirRascunho( atualizarEdicaoWhatsApp( campoEmUso'
NOVOS='Knobler/WhatsApp/WhatsAppIntegracao.swift Knobler/WhatsApp/WhatsAppCartaoView.swift'
CENARIOS='"whatsapp-cartao-texto" "whatsapp-cartao-grupo" "whatsapp-cartao-foto" "whatsapp-cartao-agrupado" "whatsapp-cartao-respondendo"'

# linhas <arquivo> <texto fixo>: números das linhas de código (não
# comentário) que contêm o texto, um por linha.
linhas() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//' | cut -d: -f1
}

# linha <arquivo> <texto fixo>: a primeira delas; vazio se não houver.
linha() { linhas "$1" "$2" | head -1; }

# tem <arquivo> <texto fixo>: existe linha de código com o texto.
tem() { [ -n "$(linha "$1" "$2")" ]; }

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local nv="$r/Knobler/NotchView.swift"
  local app="$r/Knobler/KnoblerApp.swift"
  local view="$r/Knobler/WhatsApp/WhatsAppCartaoView.swift"
  local ft="$r/tools/notchview-fontes.txt"
  local mn="$r/tools/main.swift"
  local f t p q l dentro

  for f in "$nv" "$app" "$view" "$ft" "$mn"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  if [ -f "$nv" ]; then
    p=$(linha "$nv" "$INICIO")
    q=""
    if [ -z "$p" ]; then
      echo "FALHOU: Knobler/NotchView.swift sem '$INICIO'"
      erro=1
    else
      # o primeiro `return NotchPresentation(` depois do início da propriedade
      for l in $(linhas "$nv" "$FIM"); do
        if [ "$l" -gt "$p" ]; then q="$l"; break; fi
      done
      if [ -z "$q" ]; then
        echo "FALHOU: Knobler/NotchView.swift sem '$FIM' depois de '$INICIO'"
        erro=1
      fi
    fi
    if ! tem "$nv" "$APLICAR"; then
      echo "FALHOU: Knobler/NotchView.swift sem '$APLICAR'"
      erro=1
    elif [ -n "$p" ] && [ -n "$q" ]; then
      dentro=0
      for l in $(linhas "$nv" "$APLICAR"); do
        if [ "$l" -gt "$p" ] && [ "$l" -lt "$q" ]; then dentro=1; fi
      done
      if [ "$dentro" -ne 1 ]; then
        echo "FALHOU: '$APLICAR' fora de presentation (tem que estar entre as linhas $p e $q da NotchView)"
        erro=1
      fi
    fi
    if ! tem "$nv" "$CARTAO"; then
      echo "FALHOU: Knobler/NotchView.swift não desenha '$CARTAO'"
      erro=1
    fi
  fi

  if [ -f "$app" ]; then
    for t in "$INTEGRACAO" "$CHEGADA" "$DISPENSA"; do
      if ! tem "$app" "$t"; then
        echo "FALHOU: Knobler/KnoblerApp.swift sem '$t'"
        erro=1
      fi
    done
  fi

  if [ -f "$view" ]; then
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

NV="$T/r/Knobler/NotchView.swift"
APP="$T/r/Knobler/KnoblerApp.swift"
VIEW="$T/r/Knobler/WhatsApp/WhatsAppCartaoView.swift"
FT="$T/r/tools/notchview-fontes.txt"
MN="$T/r/tools/main.swift"

# repo falso com a ligação certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/Knobler/WhatsApp" "$T/r/tools"
  cat > "$NV" <<'EOF'
struct NotchView: View {
    // o card do WhatsApp liga pelo vm.aplicarCartaoWhatsApp(em: &layout)
    private var presentation: NotchPresentation {
        var layout = NotchPresentation.Layout()
        layout.notificationExtra = Self.alturaExtra(vm.activeNotification, aberto: vm.notificationHeld)
        vm.aplicarCartaoWhatsApp(em: &layout)
        return NotchPresentation(content: vm.contentState(), layout: layout)
    }

    var notch: some View {
        switch mode {
        case .notification:
            if let n = vm.activeNotification, n.whatsapp != nil {
                WhatsAppCartaoView(vm: vm, notificacao: n)
            } else {
                notificationCard
            }
        }
    }

    func outra() -> NotchPresentation {
        return NotchPresentation(content: .init(), layout: .init())
    }
}
EOF
  cat > "$APP" <<'EOF'
final class AppDelegate {
    private lazy var whatsapp = WhatsAppIntegracao(telas: { [weak self] in self?.notches.values.map(\.viewModel) ?? [] },
                                                   publicar: { [weak self] in self?.publicar($0) })
    func ligar() {
        let integracao = whatsapp
        WhatsAppStore.shared.aoChegarMensagem = { m, c, conta in integracao.chegou(mensagem: m, conversa: c, conta: conta, numero: conta?.conta ?? "") }
        WhatsAppStore.shared.aoDispensarCartao = { integracao.respondeu(chave: $0) }
    }
}
EOF
  cat > "$VIEW" <<'EOF'
struct WhatsAppCartaoView: View {
    var body: some View {
        Button { store.dispensarCartao(chave: c.chave) } label: { Image(systemName: "xmark") }
        TextField("Responder…", text: Binding(get: { store.rascunho(k) }, set: { store.definirRascunho($0, para: k) }))
            .onChange(of: focado) { vm.atualizarEdicaoWhatsApp($1); store.campoEmUso = $1 ? k : nil }
        Button { Task { await store.responderCartao(chave: k, texto: store.rascunho(k)) } } label: { Image(systemName: "paperplane.fill") }
        cabecalho.onTapGesture { vm.abrirWhatsApp(chave: c.chave, conta: c.conta) }
    }
}
EOF
  cat > "$FT" <<'EOF'
Knobler/NotchView.swift
Knobler/WhatsApp/WhatsAppCartao.swift
Knobler/WhatsApp/WhatsAppIntegracao.swift
Knobler/WhatsApp/WhatsAppCartaoView.swift
EOF
  cat > "$MN" <<'EOF'
let cenarios = [
    Scenario("whatsapp-cartao-texto") { vm in vm.activeNotification = cartaoMarina },
    Scenario("whatsapp-cartao-grupo") { vm in vm.activeNotification = cartaoGrupo },
    Scenario("whatsapp-cartao-foto") { vm in vm.activeNotification = cartaoFoto },
    Scenario("whatsapp-cartao-agrupado") { vm in vm.activeNotification = cartaoRafa },
    Scenario("whatsapp-cartao-respondendo") { vm in vm.whatsappEditando = true },
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
caso "ligação certa (comentário com a chamada antes de presentation não conta)" 0 ""

montar
grep -vF -- "$APLICAR" "$NV" > "$NV.novo"; mv "$NV.novo" "$NV"
caso "NotchView sem aplicarCartaoWhatsApp" 1 "sem '$APLICAR'"

montar
sed -i '' 's|^        vm.aplicarCartaoWhatsApp|        // vm.aplicarCartaoWhatsApp|' "$NV"
caso "aplicarCartaoWhatsApp só em comentário" 1 "sem '$APLICAR'"

# a chamada depois do return (código morto) não vale
montar
grep -vF -- "$APLICAR" "$NV" > "$NV.novo"; mv "$NV.novo" "$NV"
sed -i '' 's|^    var notch: some View {|    var notch: some View {\
        let _ = vm.aplicarCartaoWhatsApp(em: \&layout)|' "$NV"
caso "aplicarCartaoWhatsApp fora de presentation" 1 "fora de presentation"

montar
sed -i '' 's|private var presentation: NotchPresentation {|private var apresentacao: NotchPresentation {|' "$NV"
caso "NotchView sem presentation" 1 "sem '$INICIO'"

montar
sed -i '' 's|WhatsAppCartaoView(vm: vm, notificacao: n)|notificationCard|' "$NV"
caso "NotchView sem WhatsAppCartaoView" 1 "não desenha '$CARTAO'"

for t in "$INTEGRACAO" "$CHEGADA" "$DISPENSA"; do
  montar
  grep -vF -- "$t" "$APP" > "$APP.novo"; mv "$APP.novo" "$APP"
  caso "KnoblerApp sem $t" 1 "Knobler/KnoblerApp.swift sem '$t'"
done

# ligado sem o `WhatsAppStore.shared.` na frente não vale (o gate procura a linha exata)
montar
sed -i '' 's|WhatsAppStore.shared.aoDispensarCartao =|store.aoDispensarCartao =|' "$APP"
caso "aoDispensarCartao sem WhatsAppStore.shared" 1 "sem '$DISPENSA'"

for t in $VIEW_TEXTOS; do
  montar
  grep -vF -- "$t" "$VIEW" > "$VIEW.novo"; mv "$VIEW.novo" "$VIEW"
  caso "WhatsAppCartaoView sem $t" 1 "WhatsAppCartaoView.swift sem '$t'"
done

montar
rm "$VIEW"
caso "WhatsAppCartaoView.swift ausente" 1 "Knobler/WhatsApp/WhatsAppCartaoView.swift não existe"

for t in $NOVOS; do
  montar
  grep -vxF -- "$t" "$FT" > "$FT.novo"; mv "$FT.novo" "$FT"
  caso "fontes sem $t" 1 "notchview-fontes.txt sem '$t'"
done

montar
sed -i '' 's|^Knobler/WhatsApp/WhatsAppIntegracao.swift|# Knobler/WhatsApp/WhatsAppIntegracao.swift|' "$FT"
caso "fonte comentada" 1 "sem 'Knobler/WhatsApp/WhatsAppIntegracao.swift'"

for t in $CENARIOS; do
  montar
  grep -vF -- "$t" "$MN" > "$MN.novo"; mv "$MN.novo" "$MN"
  caso "harness sem $t" 1 "sem o cenário $t"
done

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappintegracaoligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappintegracaoligacaocheck ok"
