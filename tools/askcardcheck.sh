#!/usr/bin/env bash
# Gate das etapas 3 e 4 do card de pergunta
# (docs/vesta/plans/2026-11-18-card-pergunta.md): a estrutura do card
# redesenhado nos arquivos que o ./tools/check.sh não roda (views SwiftUI e o
# harness de snapshot). O notchfontescheck só typecheca.
# Etapa 3 confere:
#   - Knobler/Ask.swift não existe mais; os quatro arquivos de view de
#     Knobler/AskCard/ existem, cada um declara a sua struct, as três peças são
#     usadas fora do próprio arquivo e leem o `AskEstilo` do AskCardView.swift;
#   - tools/notchview-fontes.txt lista os quatro e não lista Knobler/Ask.swift;
#   - o `contentID` de Knobler/NotchView.swift segue com o id da pergunta e não
#     tem mais a página (trocar de aba não anima o card inteiro);
#   - Knobler/AskCard/ sem `@State … hovered` e sem `lineLimit(hovered`: o
#     destaque sai do reducer (`.setHighlight(`) e a descrição sai inteira;
#   - o placeholder é "Outra resposta…", sem a dica de Enter/ditado dentro;
#   - `AlturaDoAskKey` mora no AskCardView.swift com `value = nextValue()`, sem
#     `max(` (o maior valor visto impede o card de encolher);
#   - as views usam `AskRotulo.separar(`, `AskResumo.texto(`,
#     `AskLegenda.itens(`, o selo "Recomendada", `.choose(index:`,
#     `.goTo(page:`, `.cancelActive`, `accessibilityReduceMotion` e
#     `glifoDoAtalho`; o AskCardModelo.swift não conta como view;
#   - Knobler/KnoblerApp.swift atribui `glifoDoAtalho` a partir de
#     `getShortcut(for: .abrirNotch)` (o harness fixa o atalho, então só o app
#     de verdade ficaria sem a legenda);
#   - tools/main.swift tem os cinco cenários `ask-*`, com os dados do mockup e
#     a volta por `.goTo(page:`, manda o prefixo `ask-` para a janela real e
#     fixa `vm.glifoDoAtalho = { "⌃⌥K" }`.
# Etapa 4 (preview sempre inteiro) confere:
#   - Knobler/AskCard/AskPreviewView.swift existe, declara `struct
#     AskPreviewView`, está em tools/notchview-fontes.txt, é usada fora do
#     próprio arquivo e lê o `AskEstilo`;
#   - AskCardView.swift declara `static func layoutDoPreview(`, chama a função,
#     e é por ela que passa o `AskPreviewLayout.calcular(`; a medida da letra vem
#     de `monospacedSystemFont(` (avanço fixo corta a moldura);
#   - Knobler/NotchView.swift chama `layoutDoPreview(`, tira a largura da
#     propriedade `larguraDoCard` do layout, não fixa mais 540 no `questionSize`, não chama
#     `AskPreviewLayout.calcular(` por conta própria e soma `quadro.height` na
#     estimativa do primeiro frame;
#   - Knobler/AskCard/ sem `.frame(width: 250)` e sem letra monoespaçada de
#     9 pt; `design: .monospaced` só no AskPreviewView.swift; a lista ao lado do
#     preview tem a largura que o cálculo supõe (236 ou `AskPreviewLayout.lista`);
#   - o card decide por `.lado`; alguma view usa `.fonte` e `.quadro` do layout;
#     o AskPreviewView.swift tem `.fixedSize(` e o `ScrollView` dele só aparece
#     depois de um `if`/`guard`/`switch` com `rola`;
#   - tools/main.swift tem `ask-preview` e `ask-preview-largo` com
#     `frameWidth: 900`, o destaque na segunda opção por `.setHighlight(1)`, a
#     tabela larga do mockup e o `AskCardView.layoutDoPreview(` nos dois.
# Linha de comentário (`//`) não conta.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que cada verificação reprova.
#
# Uso: bash tools/askcardcheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

PASTA='Knobler/AskCard'
VIEWS='AskCardView AskAbasView AskOpcaoView AskRodapeView AskPreviewView'
PECAS='AskAbasView AskOpcaoView AskRodapeView AskPreviewView'
CENARIOS='ask-simple ask-multi-vazio ask-multiselect ask-preview ask-preview-largo ask-paged ask-revisita'
CENARIOS_DE_PREVIEW='ask-preview ask-preview-largo'
# linha de ~100 colunas da tabela `LARGA` do mockup
LINHA_LARGA='Shift+Tab volta à lista'
PLACEHOLDER='"Outra resposta…"'
ROTULO_DO_MOCKUP='Atalho global foca o card (Recomendado)'
# texto fixo que tem de aparecer em alguma view, e por quê
USOS=(
  'AskRotulo.separar(|o rótulo perde o "(Recomendado)" pelo modelo'
  'AskResumo.texto(|a aba respondida mostra o resumo do modelo'
  'AskLegenda.itens(|a legenda vem do modelo'
  '"Recomendada"|selo da opção recomendada'
  '.setHighlight(|o destaque do cursor vai para o reducer'
  '.choose(index:|clique na opção simples'
  '.goTo(page:|clique na aba'
  '.cancelActive|o ✕ manda a pergunta para o terminal'
  'accessibilityReduceMotion|troca de aba só com opacidade quando reduzir movimento'
  'glifoDoAtalho|a legenda em repouso mostra o atalho da view model'
)

# contar <arquivo> <texto fixo>: linhas de código (não comentário) com o texto.
# Sem `grep -q` no fim do pipe: com pipefail ele derruba o grep de cima (SIGPIPE).
contar() {
  local n
  n=$(grep -vE '^[[:space:]]*//' "$1" 2>/dev/null | grep -cF -- "$2")
  echo "${n:-0}"
}
contar_re() {
  local n
  n=$(grep -vE '^[[:space:]]*//' "$1" 2>/dev/null | grep -cE -- "$2")
  echo "${n:-0}"
}
# Sem passar pelo `contar`: o autoteste chama isto milhares de vezes e cada
# `$( )` é um processo a mais. `>/dev/null` no lugar do `-q` pelo mesmo SIGPIPE.
tem() { grep -vE '^[[:space:]]*//' "$1" 2>/dev/null | grep -F -- "$2" >/dev/null; }
tem_re() { grep -vE '^[[:space:]]*//' "$1" 2>/dev/null | grep -E -- "$2" >/dev/null; }

# views <raiz>: os .swift de Knobler/AskCard/ menos o modelo puro, um por linha
views() {
  local f
  for f in "$1/$PASTA"/*.swift; do
    [ -e "$f" ] || continue
    [ "${f##*/}" = AskCardModelo.swift ] && continue
    printf '%s\n' "$f"
  done
}

# nas_views <raiz> <texto fixo> [arquivo a pular]
nas_views() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ "$f" = "${3:-}" ] && continue
    tem "$f" "$2" && return 0
  done < <(views "$1")
  return 1
}

# nas_views_re <raiz> <regex>
nas_views_re() {
  local f
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    tem_re "$f" "$2" && return 0
  done < <(views "$1")
  return 1
}

# corpo do `questionSize` do NotchView, sem comentário (nem o de fim de linha):
# da declaração até a chave que fecha (conta chaves)
question_size() {
  awk '
    /^[[:space:]]*\/\// { next }
    !pega && /var[[:space:]]+questionSize/ { pega = 1 }
    pega {
      sub(/[[:space:]]\/\/.*$/, "")
      print
      abre += gsub(/\{/, "{"); fecha += gsub(/\}/, "}")
      if (abre > 0 && abre == fecha) exit
    }
  ' "$1"
}

# rolagem_do_preview <arquivo>: `sem` (nenhum ScrollView), `solto` (algum
# ScrollView antes de qualquer `if`/`guard`/`switch` com `rola`) ou `ok`.
# Ternário na mesma linha do ScrollView não conta: o ScrollView existiria sempre.
rolagem_do_preview() {
  awk '
    /^[[:space:]]*\/\// { next }
    /ScrollView/ && !/(^|[^A-Za-z0-9_])(if|guard|switch)[[:space:]]/ { visto = 1; if (!cond) solto = 1; next }
    /(^|[^A-Za-z0-9_])(if|guard|switch)([[:space:]]|[[:space:]].*[^A-Za-z0-9_])rola([^A-Za-z0-9_]|$)/ { cond = 1 }
    /ScrollView/ { visto = 1; if (!cond) solto = 1 }
    END { print (!visto ? "sem" : (solto ? "solto" : "ok")) }
  ' "$1"
}

# atribuição do contentID inteira (pode quebrar em mais de uma linha), sem comentário
content_id() {
  awk '
    /^[[:space:]]*\/\// { next }
    pega && /^[[:space:]]*(return|let|var|if|guard|layout\.|vm\.|\})/ { pega = 0 }
    /contentID[[:space:]]*=/ { pega = 1 }
    pega { print }
  ' "$1"
}

# corpo da struct AlturaDoAskKey, sem comentário
altura_key() {
  awk '
    /^[[:space:]]*\/\// { next }
    /struct[[:space:]]+AlturaDoAskKey/ { pega = 1 }
    pega { print }
    pega && /^\}/ { exit }
  ' "$1"
}

# condição que manda o cenário para a janela real: do `if` com o prefixo
# "agenda-" até a chave que abre o bloco
condicao_da_janela() {
  awk '
    /^[[:space:]]*\/\// { next }
    /if[[:space:]].*hasPrefix\("agenda-"\)/ { pega = 1 }
    pega { print }
    pega && /\{[[:space:]]*$/ { exit }
  ' "$1"
}

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local card="$r/$PASTA/AskCardView.swift"
  local notch="$r/Knobler/NotchView.swift"
  local app="$r/Knobler/KnoblerApp.swift"
  local fontes="$r/tools/notchview-fontes.txt"
  local harness="$r/tools/main.swift"
  local previa="$r/$PASTA/AskPreviewView.swift"
  local v f n bloco uso texto motivo

  # --- arquivos ---
  if [ -e "$r/Knobler/Ask.swift" ]; then
    echo "FALHOU: Knobler/Ask.swift ainda existe (o card migra para $PASTA/)"
    erro=1
  fi
  for v in $VIEWS; do
    f="$r/$PASTA/$v.swift"
    if [ ! -f "$f" ]; then
      echo "FALHOU: $PASTA/$v.swift não existe"
      erro=1
    elif ! tem_re "$f" "struct[[:space:]]+$v([^A-Za-z0-9_]|\$)"; then
      echo "FALHOU: $PASTA/$v.swift não declara 'struct $v'"
      erro=1
    fi
  done
  for v in $PECAS; do
    f="$r/$PASTA/$v.swift"
    if ! nas_views "$r" "$v(" "$f"; then
      echo "FALHOU: nenhuma view de $PASTA/ usa '$v(' fora do próprio arquivo (peça sem uso)"
      erro=1
    fi
    if [ -f "$f" ] && ! tem "$f" 'AskEstilo.'; then
      echo "FALHOU: $PASTA/$v.swift não usa 'AskEstilo.' (opacidades e raios soltos na peça)"
      erro=1
    fi
  done
  if [ -f "$card" ] && ! tem_re "$card" 'enum[[:space:]]+AskEstilo([^A-Za-z0-9_]|$)'; then
    echo "FALHOU: $PASTA/AskCardView.swift não declara 'enum AskEstilo'"
    erro=1
  fi

  # --- lista de fontes do snapshot ---
  if [ ! -f "$fontes" ]; then
    echo "FALHOU: tools/notchview-fontes.txt não existe"
    erro=1
  else
    for v in $VIEWS; do
      if ! grep -qxF -- "$PASTA/$v.swift" "$fontes"; then
        echo "FALHOU: tools/notchview-fontes.txt sem '$PASTA/$v.swift'"
        erro=1
      fi
    done
    if grep -qxF -- 'Knobler/Ask.swift' "$fontes"; then
      echo "FALHOU: tools/notchview-fontes.txt ainda lista 'Knobler/Ask.swift'"
      erro=1
    fi
  fi

  # --- contentID sem a página ---
  if [ ! -f "$notch" ]; then
    echo "FALHOU: Knobler/NotchView.swift não existe"
    erro=1
  else
    bloco=$(content_id "$notch")
    case "$bloco" in
      *'state.page'*)
        echo "FALHOU: Knobler/NotchView.swift: o contentID ainda leva a página do Ask (trocar de aba anima o card inteiro)"
        erro=1 ;;
    esac
    case "$bloco" in
      *'askStore.state.active?.id'*) ;;
      *)
        echo "FALHOU: Knobler/NotchView.swift: o contentID perdeu 'askStore.state.active?.id' (pergunta nova tem que trocar o card)"
        erro=1 ;;
    esac
  fi

  # --- destaque sai do estado, descrição inteira ---
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if tem_re "$f" '@State[^/]*[^A-Za-z0-9_]hovered([^A-Za-z0-9_]|$)'; then
      echo "FALHOU: ${f#"$r"/} ainda guarda o destaque em '@State … hovered' (sai do AskState.highlight)"
      erro=1
    fi
    if tem "$f" 'lineLimit(hovered'; then
      echo "FALHOU: ${f#"$r"/} ainda corta a descrição com 'lineLimit(hovered' (sai sempre inteira)"
      erro=1
    fi
    if tem_re "$f" '"Outra resposta…[^"]'; then
      echo "FALHOU: ${f#"$r"/}: o placeholder leva texto além de $PLACEHOLDER (a dica vai na legenda)"
      erro=1
    fi
  done < <(views "$r")

  # --- placeholder ---
  if ! nas_views "$r" "$PLACEHOLDER"; then
    echo "FALHOU: nenhuma view de $PASTA/ tem o placeholder $PLACEHOLDER"
    erro=1
  fi

  # --- altura medida ---
  if [ -f "$card" ]; then
    bloco=$(altura_key "$card")
    if [ -z "$bloco" ]; then
      echo "FALHOU: $PASTA/AskCardView.swift não declara 'struct AlturaDoAskKey' (a chave vai junto com o card)"
      erro=1
    else
      case "$bloco" in
        *'max('*)
          echo "FALHOU: AlturaDoAskKey ainda usa 'max(' no reduce (o card não encolhe ao trocar de aba)"
          erro=1 ;;
      esac
      if ! printf '%s\n' "$bloco" | grep -E 'value[[:space:]]*=[[:space:]]*nextValue\(\)' >/dev/null; then
        echo "FALHOU: AlturaDoAskKey sem 'value = nextValue()' no reduce"
        erro=1
      fi
    fi
  fi

  # --- ligações das views ---
  for uso in "${USOS[@]}"; do
    texto="${uso%%|*}"; motivo="${uso#*|}"
    if ! nas_views "$r" "$texto"; then
      echo "FALHOU: nenhuma view de $PASTA/ usa '$texto' ($motivo)"
      erro=1
    fi
  done

  # --- atalho no app de verdade ---
  if [ ! -f "$app" ]; then
    echo "FALHOU: Knobler/KnoblerApp.swift não existe"
    erro=1
  else
    if ! tem_re "$app" 'glifoDoAtalho[[:space:]]*='; then
      echo "FALHOU: Knobler/KnoblerApp.swift não atribui 'glifoDoAtalho' (a legenda fica sem atalho no app)"
      erro=1
    fi
    if ! tem "$app" 'getShortcut(for: .abrirNotch)'; then
      echo "FALHOU: Knobler/KnoblerApp.swift sem 'getShortcut(for: .abrirNotch)' (o atalho exibido é o de abrir o notch)"
      erro=1
    fi
  fi

  # --- harness de snapshot ---
  if [ ! -f "$harness" ]; then
    echo "FALHOU: tools/main.swift não existe"
    erro=1
  else
    for v in $CENARIOS; do
      if ! tem "$harness" "Scenario(name: \"$v\""; then
        echo "FALHOU: tools/main.swift sem o cenário \"$v\""
        erro=1
      fi
    done
    case "$(condicao_da_janela "$harness")" in
      *'hasPrefix("ask-")'*) ;;
      *)
        echo "FALHOU: tools/main.swift: a condição da janela real não tem hasPrefix(\"ask-\") (campo de texto sai \"proibido\" no ImageRenderer)"
        erro=1 ;;
    esac
    if ! tem_re "$harness" 'glifoDoAtalho[[:space:]]*=[[:space:]]*\{[[:space:]]*"⌃⌥K"[[:space:]]*\}'; then
      echo "FALHOU: tools/main.swift não fixa vm.glifoDoAtalho = { \"⌃⌥K\" }"
      erro=1
    fi
    if ! tem "$harness" "$ROTULO_DO_MOCKUP"; then
      echo "FALHOU: tools/main.swift sem a opção do mockup '$ROTULO_DO_MOCKUP' (sem ela nenhum PNG prova o selo Recomendada)"
      erro=1
    fi
    if ! tem "$harness" '.goTo(page:'; then
      echo "FALHOU: tools/main.swift sem '.goTo(page:' (o ask-revisita volta à primeira por ação real do reducer)"
      erro=1
    fi
  fi

  # === etapa 4: preview sempre inteiro ===

  # --- uma função só para o tamanho do preview ---
  if [ -f "$card" ]; then
    if ! tem_re "$card" 'static[[:space:]]+func[[:space:]]+layoutDoPreview[[:space:]]*\('; then
      echo "FALHOU: $PASTA/AskCardView.swift não declara 'static func layoutDoPreview(' (card e NotchView medem o preview pela mesma função)"
      erro=1
    fi
    n=$(( $(contar "$card" 'layoutDoPreview(') - $(contar_re "$card" 'func[[:space:]]+layoutDoPreview[[:space:]]*\(') ))
    if [ "$n" -le 0 ]; then
      echo "FALHOU: $PASTA/AskCardView.swift não chama 'layoutDoPreview(' (o card desenha o preview sem o layout que o NotchView usa)"
      erro=1
    fi
    if ! tem "$card" 'AskPreviewLayout.calcular('; then
      echo "FALHOU: $PASTA/AskCardView.swift sem 'AskPreviewLayout.calcular(' (o layoutDoPreview passa pelo modelo da etapa 2)"
      erro=1
    fi
    if ! tem_re "$card" '\.lado([^A-Za-z0-9_]|$)'; then
      echo "FALHOU: $PASTA/AskCardView.swift não lê '.lado' do layout (o preview largo não desce para baixo da lista)"
      erro=1
    fi
    if ! tem_re "$card" '\.frame\(width:[[:space:]]*(236|AskPreviewLayout\.lista)[[:space:]]*[,)]'; then
      echo "FALHOU: $PASTA/AskCardView.swift: a lista ao lado do preview não tem '.frame(width: 236)' nem '.frame(width: AskPreviewLayout.lista)' (largura diferente da que o cálculo supõe corta o preview)"
      erro=1
    fi
  fi
  if ! nas_views "$r" 'monospacedSystemFont('; then
    echo "FALHOU: nenhuma view de $PASTA/ mede a letra com 'monospacedSystemFont(' (avanço e linha fixos cortam a moldura do preview)"
    erro=1
  fi

  # --- restos do preview antigo e peça nova ---
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if tem_re "$f" '\.frame\(width:[[:space:]]*250([^0-9]|$)'; then
      echo "FALHOU: ${f#"$r"/} ainda tem '.frame(width: 250)' (a lista ao lado do preview mede 236)"
      erro=1
    fi
    if tem_re "$f" 'size:[[:space:]]*9[[:space:]]*,[^)]*design:[[:space:]]*\.monospaced'; then
      echo "FALHOU: ${f#"$r"/} ainda tem letra monoespaçada de 9 pt (o preview usa a letra do layout, 11 pt de base)"
      erro=1
    fi
    if [ "$f" != "$previa" ] && tem_re "$f" 'design:[[:space:]]*\.monospaced'; then
      echo "FALHOU: ${f#"$r"/} desenha letra monoespaçada fora do AskPreviewView.swift (o preview é da peça nova)"
      erro=1
    fi
  done < <(views "$r")
  if ! nas_views_re "$r" '\.fonte([^A-Za-z0-9_]|$)'; then
    echo "FALHOU: nenhuma view de $PASTA/ usa '.fonte' do layout (a letra do preview não encolhe quando ele não cabe)"
    erro=1
  fi
  if ! nas_views_re "$r" '\.quadro([^A-Za-z0-9_]|$)'; then
    echo "FALHOU: nenhuma view de $PASTA/ usa '.quadro' do layout (o quadro muda de tamanho com o destaque)"
    erro=1
  fi
  if [ -f "$previa" ]; then
    if ! tem "$previa" '.fixedSize('; then
      echo "FALHOU: $PASTA/AskPreviewView.swift sem '.fixedSize(' (o texto do preview quebra ou trunca em vez de sair inteiro)"
      erro=1
    fi
    case "$(rolagem_do_preview "$previa")" in
      sem)
        echo "FALHOU: $PASTA/AskPreviewView.swift sem 'ScrollView' (preview que não cabe nem no piso da letra fica cortado)"
        erro=1 ;;
      solto)
        echo "FALHOU: $PASTA/AskPreviewView.swift: 'ScrollView' fora de um 'if … rola' (o preview só rola quando o layout manda)"
        erro=1 ;;
    esac
  fi

  # --- largura do card no NotchView ---
  if [ -f "$notch" ]; then
    if ! tem "$notch" 'layoutDoPreview('; then
      echo "FALHOU: Knobler/NotchView.swift não chama 'layoutDoPreview(' (a largura do card diverge do que o card desenha)"
      erro=1
    fi
    # a propriedade do layout; `NotchMetrics.larguraDoCard(` é função de outro card
    if ! tem_re "$notch" 'larguraDoCard([^A-Za-z0-9_(]|$)'; then
      echo "FALHOU: Knobler/NotchView.swift não usa 'larguraDoCard' do layout (a largura do card com preview vem dele)"
      erro=1
    fi
    if printf '%s\n' "$(question_size "$notch")" | grep -E '(^|[^0-9.])540([^0-9]|$)' >/dev/null; then
      echo "FALHOU: Knobler/NotchView.swift: o questionSize ainda fixa 540 de largura (o card alarga até caber o preview)"
      erro=1
    fi
    if tem "$notch" 'AskPreviewLayout.calcular('; then
      echo "FALHOU: Knobler/NotchView.swift chama 'AskPreviewLayout.calcular(' por conta própria (só o layoutDoPreview do card calcula)"
      erro=1
    fi
    if ! tem "$notch" 'quadro.height'; then
      echo "FALHOU: Knobler/NotchView.swift sem 'quadro.height' (a estimativa do primeiro frame não soma o preview que vai embaixo)"
      erro=1
    fi
  fi

  # --- cenários de preview no harness ---
  if [ -f "$harness" ]; then
    for v in $CENARIOS_DE_PREVIEW; do
      if ! tem_re "$harness" "Scenario\\(name: \"$v\"[^{]*frameWidth:[[:space:]]*900([^0-9]|\$)"; then
        echo "FALHOU: tools/main.swift: o cenário \"$v\" sem 'frameWidth: 900' (o card alargado bate no limite da janela)"
        erro=1
      fi
    done
    if [ "$(contar "$harness" 'AskCardView.layoutDoPreview(')" -lt 2 ]; then
      echo "FALHOU: tools/main.swift sem 'AskCardView.layoutDoPreview(' nos dois cenários de preview (nada prova ao lado/embaixo, letra e rolagem)"
      erro=1
    fi
    if ! tem "$harness" '.setHighlight(1)'; then
      echo "FALHOU: tools/main.swift sem '.setHighlight(1)' (o ask-preview mostra o preview da segunda opção, a em destaque)"
      erro=1
    fi
    if ! tem "$harness" "$LINHA_LARGA"; then
      echo "FALHOU: tools/main.swift sem a tabela larga do mockup ('$LINHA_LARGA'; sem ela nenhum PNG prova o preview embaixo)"
      erro=1
    fi
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

# repo falso com a estrutura certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/$PASTA" "$T/r/tools"
  cat > "$T/r/$PASTA/AskCardModelo.swift" <<'EOF'
import Foundation

enum AskResumo {
    static func texto(_ answer: AskAnswer?) -> String {
        AskRotulo.separar(answer?.labels.first ?? "").texto
    }
}
// na view: AskResumo.texto( e AskLegenda.itens( e glifoDoAtalho
EOF
  cat > "$T/r/$PASTA/AskCardView.swift" <<'EOF'
import SwiftUI

enum AskEstilo {
    static let linha = 0.06
}

struct AskCardView: View {
    @ObservedObject var vm: NotchViewModel
    let askStore: AskStore
    @Environment(\.accessibilityReduceMotion) private var reduzMovimento

    static func layoutDoPreview(question: AskQuestion, disponivel: CGSize, topo: CGFloat) -> AskPreviewLayout? {
        let letra = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        return AskPreviewLayout.calcular(
            previews: question.options.compactMap(\.preview),
            avanco: letra.maximumAdvancement.width, linha: letra.ascender - letra.descender + letra.leading,
            larguraMaxima: disponivel.width - 64, alturaMaxima: max(120, disponivel.height - 24 - topo - 150))
    }

    var body: some View {
        VStack {
            AskAbasView(ir: { askStore.send(.goTo(page: $0)) })
            Button { askStore.send(.cancelActive) } label: { Text("x") }
            if let previa = Self.layoutDoPreview(question: question, disponivel: vm.availableSize, topo: 32) {
                if previa.lado {
                    HStack(alignment: .top, spacing: 10) {
                        lista.frame(width: AskPreviewLayout.lista)
                        AskPreviewView(texto: texto, layout: previa)
                    }
                } else {
                    VStack(spacing: 8) { lista; AskPreviewView(texto: texto, layout: previa) }
                }
            } else {
                lista
            }
            AskRodapeView(itens: AskLegenda.itens(teclado: false, campo: false, multipla: false,
                                                  abas: false, atalho: vm.glifoDoAtalho()))
        }
    }

    private var lista: some View {
        VStack {
            AskOpcaoView(rotulo: AskRotulo.separar("a").texto,
                         entrar: { askStore.send(.setHighlight(0)) },
                         clicar: { askStore.send(.choose(index: 0)) })
        }
    }
}

struct AlturaDoAskKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
EOF
  cat > "$T/r/$PASTA/AskAbasView.swift" <<'EOF'
import SwiftUI

struct AskAbasView: View {
    var body: some View {
        Text(AskResumo.texto(nil)).opacity(AskEstilo.linha)
    }
}
EOF
  cat > "$T/r/$PASTA/AskOpcaoView.swift" <<'EOF'
import SwiftUI

struct AskOpcaoView: View {
    var body: some View {
        Text("Recomendada").opacity(AskEstilo.linha)
    }
}
EOF
  cat > "$T/r/$PASTA/AskRodapeView.swift" <<'EOF'
import SwiftUI

struct AskRodapeView: View {
    var body: some View {
        TextField("Outra resposta…", text: .constant("")).opacity(AskEstilo.linha)
    }
}
EOF
  cat > "$T/r/$PASTA/AskPreviewView.swift" <<'EOF'
import SwiftUI

struct AskPreviewView: View {
    let texto: String
    let layout: AskPreviewLayout

    var body: some View {
        Group {
            if layout.rola {
                ScrollView([.vertical, .horizontal]) { corpo }
            } else {
                corpo
            }
        }
        .frame(width: layout.quadro.width, height: layout.quadro.height, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(AskEstilo.linha)))
    }

    private var corpo: some View {
        Text(texto)
            .font(.system(size: layout.fonte, design: .monospaced))
            .fixedSize()
    }
}
EOF
  cat > "$T/r/Knobler/NotchView.swift" <<'EOF'
import SwiftUI

struct NotchView: View {
    private var presentation: NotchPresentation {
        layout.questionSize = questionSize
        layout.contentID = "\(askStore.state.active?.id ?? "")/\(agentRequestStore.state.active?.id ?? "")"
        return NotchPresentation(content: vm.contentState(question: true), layout: layout)
    }
    private var questionSize: CGSize {
        let question = ask.questions[min(askStore.state.page, ask.questions.count - 1)]
        let previa = AskCardView.layoutDoPreview(question: question, disponivel: vm.availableSize, topo: 32)
        var height: CGFloat = 120
        if let previa, !previa.lado { height += previa.quadro.height + 8 }
        return CGSize(width: previa?.larguraDoCard ?? 460, height: height)
    }
}
EOF
  cat > "$T/r/Knobler/KnoblerApp.swift" <<'EOF'
let vm = NotchViewModel()
vm.glifoDoAtalho = { KeyboardShortcuts.getShortcut(for: .abrirNotch)?.shortcutGlyph }
EOF
  cat > "$T/r/tools/notchview-fontes.txt" <<'EOF'
# fontes
Knobler/NotchView.swift
Knobler/AskModels.swift
Knobler/AskCard/AskCardModelo.swift
Knobler/AskCard/AskCardView.swift
Knobler/AskCard/AskAbasView.swift
Knobler/AskCard/AskOpcaoView.swift
Knobler/AskCard/AskRodapeView.swift
Knobler/AskCard/AskPreviewView.swift
EOF
  cat > "$T/r/tools/main.swift" <<'EOF'
let rotulo = "Atalho global foca o card (Recomendado)"
let scenarios = [
    Scenario(name: "ask-simple", realNotch: true) { _, _, askStore in },
    Scenario(name: "ask-multi-vazio", realNotch: true) { _, _, askStore in },
    Scenario(name: "ask-multiselect", realNotch: true) { _, _, askStore in },
    Scenario(name: "ask-preview", realNotch: true, frameHeight: 560, frameWidth: 900) { vm, _, askStore in
        askStore.send(.setHighlight(1))
        let layout = AskCardView.layoutDoPreview(question: abas, disponivel: vm.availableSize, topo: 32)
        precondition(layout?.lado == true)
    },
    Scenario(name: "ask-preview-largo", realNotch: true, frameHeight: 560, frameWidth: 900) { vm, _, askStore in
        let tabela = "Tab        leva o cursor ao campo            Shift+Tab volta à lista"
        let layout = AskCardView.layoutDoPreview(question: larga, disponivel: vm.availableSize, topo: 32)
        precondition(layout?.lado == false)
    },
    Scenario(name: "ask-paged", realNotch: true) { _, _, askStore in },
    Scenario(name: "ask-revisita", realNotch: true) { _, _, askStore in
        askStore.send(.goTo(page: 0))
    },
]
let vm = NotchViewModel()
vm.glifoDoAtalho = { "⌃⌥K" }
if scenario.name.hasPrefix("agenda-") || scenario.name.hasPrefix("lembretes-")
    || scenario.name.hasPrefix("whatsapp-") || scenario.name.hasPrefix("ask-") {
    janela()
}
if scenario.name.hasPrefix("ask-") { outraCoisa() }
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
  elif [ -n "$texto" ] && [ "$(printf '%s\n' "$saida" | grep -cF -- "$texto")" = 0 ]; then
    echo "autoteste ($nome): saída sem '$texto'"
    printf '%s\n' "$saida" | sed 's/^/    | /'
    AUTO=1
  fi
}

CV="$T/r/$PASTA/AskCardView.swift"
AB="$T/r/$PASTA/AskAbasView.swift"
OP="$T/r/$PASTA/AskOpcaoView.swift"
RD="$T/r/$PASTA/AskRodapeView.swift"
PV="$T/r/$PASTA/AskPreviewView.swift"
NV="$T/r/Knobler/NotchView.swift"
KA="$T/r/Knobler/KnoblerApp.swift"
FT="$T/r/tools/notchview-fontes.txt"
MN="$T/r/tools/main.swift"

montar
caso "estrutura certa" 0 ""

montar
# o que saiu, citado em comentário, não conta
sed -i '' 's|^struct AskCardView: View {|// antes: @State private var hovered: String? e .lineLimit(hovered == x ? nil : 2)\
// antes: "Outra resposta… (Enter envia; ⌥ direita dita)" e value = max(value, nextValue())\
struct AskCardView: View {|' "$CV"
caso "legado só em comentário" 0 ""

# --- arquivos
montar
echo 'struct AskCardView {}' > "$T/r/Knobler/Ask.swift"
caso "Ask.swift de volta" 1 "Knobler/Ask.swift ainda existe"

for v in $VIEWS; do
  montar
  rm "$T/r/$PASTA/$v.swift"
  caso "$v.swift ausente" 1 "$PASTA/$v.swift não existe"

  montar
  sed -i '' "s|^struct $v: View {|struct Outra: View {|" "$T/r/$PASTA/$v.swift"
  caso "$v.swift sem a struct" 1 "não declara 'struct $v'"

  montar
  grep -vxF -- "$PASTA/$v.swift" "$FT" > "$FT.novo"; mv "$FT.novo" "$FT"
  caso "fontes sem $v.swift" 1 "tools/notchview-fontes.txt sem '$PASTA/$v.swift'"
done

for v in $PECAS; do
  montar
  # peça criada e nunca chamada: o card inteiro ficou no AskCardView
  sed -i '' "s|$v(|Text(|" "$CV"
  caso "$v sem uso" 1 "usa '$v(' fora do próprio arquivo"

  montar
  sed -i '' 's|AskEstilo.linha|0.06|' "$T/r/$PASTA/$v.swift"
  caso "$v sem AskEstilo" 1 "$PASTA/$v.swift não usa 'AskEstilo.'"
done

montar
# só o próprio arquivo cita a peça (um #Preview): não conta como uso
sed -i '' 's|AskOpcaoView(|Text(|' "$CV"
echo '#Preview { AskOpcaoView() }' >> "$OP"
caso "peça só no próprio arquivo" 1 "usa 'AskOpcaoView(' fora do próprio arquivo"

montar
sed -i '' 's|^enum AskEstilo {|enum Estilo {|' "$CV"
caso "sem enum AskEstilo" 1 "não declara 'enum AskEstilo'"

# --- fontes
montar
echo 'Knobler/Ask.swift' >> "$FT"
caso "fontes ainda com Ask.swift" 1 "ainda lista 'Knobler/Ask.swift'"

montar
sed -i '' 's|^Knobler/AskCard/AskAbasView.swift$|# Knobler/AskCard/AskAbasView.swift|' "$FT"
caso "fonte comentada" 1 "tools/notchview-fontes.txt sem '$PASTA/AskAbasView.swift'"

# --- contentID
montar
sed -i '' 's|?? "")/\\(agentRequestStore|?? "")/\\(askStore.state.page)/\\(agentRequestStore|' "$NV"
caso "contentID com a página" 1 "o contentID ainda leva a página"

montar
# a mesma atribuição quebrada em duas linhas
sed -i '' 's|^        layout.contentID = .*$|        layout.contentID = "\\(askStore.state.active?.id ?? "")"\
            + "/\\(askStore.state.page)/\\(agentRequestStore.state.active?.id ?? "")"|' "$NV"
caso "contentID com a página na linha de baixo" 1 "o contentID ainda leva a página"

montar
sed -i '' 's|^        layout.contentID = .*$|        layout.contentID = "\\(agentRequestStore.state.active?.id ?? "")"|' "$NV"
caso "contentID sem o id da pergunta" 1 "o contentID perdeu 'askStore.state.active?.id'"

# --- destaque e descrição
montar
sed -i '' 's|^    let askStore: AskStore$|    let askStore: AskStore\
    @State private var hovered: String?|' "$CV"
caso "@State private var hovered" 1 "ainda guarda o destaque em '@State … hovered'"

montar
sed -i '' 's|^struct AskOpcaoView: View {|struct AskOpcaoView: View {\
    @State var hovered = false|' "$OP"
caso "@State var hovered na peça" 1 "$PASTA/AskOpcaoView.swift ainda guarda o destaque"

montar
sed -i '' 's|Text("Recomendada")|Text("Recomendada").lineLimit(hovered == rotulo ? nil : 2)|' "$OP"
caso "lineLimit(hovered" 1 "ainda corta a descrição com 'lineLimit(hovered'"

# --- placeholder
montar
sed -i '' 's|"Outra resposta…"|"Outra resposta… (Enter envia; ⌥ direita dita)"|' "$RD"
caso "placeholder com a dica" 1 "o placeholder leva texto além de"

montar
sed -i '' 's|"Outra resposta…"|"Outra resposta..."|' "$RD"
caso "placeholder com três pontos" 1 "tem o placeholder"

montar
sed -i '' 's|"Outra resposta…"|"Responder"|' "$RD"
caso "placeholder trocado" 1 "tem o placeholder"

# --- altura medida
montar
sed -i '' 's|value = nextValue()|value = max(value, nextValue())|' "$CV"
caso "AlturaDoAskKey com max(" 1 "ainda usa 'max(' no reduce"

montar
sed -i '' 's|        value = nextValue()|        _ = nextValue()|' "$CV"
caso "reduce que não grava o valor" 1 "sem 'value = nextValue()'"

montar
sed -i '' 's|^struct AlturaDoAskKey: PreferenceKey {|struct OutraKey: PreferenceKey {|' "$CV"
caso "AlturaDoAskKey fora do card" 1 "não declara 'struct AlturaDoAskKey'"

montar
# max( em outro ponto do arquivo é legítimo: só o corpo da chave conta
sed -i '' 's|^enum AskEstilo {|enum AskEstilo {\
    static func largura(_ w: Double) -> Double { max(w, 460) }|' "$CV"
caso "max( fora da chave" 0 ""

# --- ligações das views
# trocar <texto fixo> <nome do caso> <texto esperado>: tira o texto de todas as views
trocar() {
  montar
  local f
  for f in "$CV" "$AB" "$OP" "$RD" "$PV"; do
    grep -vF -- "$1" "$f" > "$f.novo"; mv "$f.novo" "$f"
  done
  caso "$2" 1 "$3"
}
trocar 'AskRotulo.separar(' "views sem AskRotulo.separar (o modelo cita, e não conta)" "usa 'AskRotulo.separar('"
trocar 'AskResumo.texto(' "views sem AskResumo.texto" "usa 'AskResumo.texto('"
trocar 'AskLegenda.itens(' "views sem AskLegenda.itens" "usa 'AskLegenda.itens('"
trocar '"Recomendada"' "sem o selo Recomendada" "usa '\"Recomendada\"'"
trocar '.setHighlight(' "hover sem setHighlight" "usa '.setHighlight('"
trocar '.choose(index:' "clique sem choose" "usa '.choose(index:'"
trocar '.goTo(page:' "aba sem goTo" "usa '.goTo(page:'"
trocar '.cancelActive' "✕ sem cancelActive" "usa '.cancelActive'"
trocar 'accessibilityReduceMotion' "sem reduzir movimento" "usa 'accessibilityReduceMotion'"

montar
sed -i '' 's|atalho: vm.glifoDoAtalho()|atalho: nil|' "$CV"
caso "legenda com atalho fixo em nil" 1 "usa 'glifoDoAtalho'"

montar
sed -i '' 's|^            AskOpcaoView(rotulo: AskRotulo.separar("a").texto,|            // AskRotulo.separar( fica para depois\
            AskOpcaoView(rotulo: "a",|' "$CV"
caso "AskRotulo.separar só em comentário" 1 "usa 'AskRotulo.separar('"

# --- app
montar
sed -i '' '/glifoDoAtalho/d' "$KA"
caso "app sem glifoDoAtalho" 1 "Knobler/KnoblerApp.swift não atribui 'glifoDoAtalho'"

montar
sed -i '' 's|^vm.glifoDoAtalho = .*$|vm.glifoDoAtalho = { "⌃⌥K" }|' "$KA"
caso "app com atalho fixo" 1 "sem 'getShortcut(for: .abrirNotch)'"

montar
sed -i '' 's|^vm.glifoDoAtalho|// vm.glifoDoAtalho|' "$KA"
caso "app com a atribuição comentada" 1 "não atribui 'glifoDoAtalho'"

# --- harness
for v in $CENARIOS; do
  montar
  sed -i '' "s|Scenario(name: \"$v\"|Scenario(name: \"x-$v\"|" "$MN"
  caso "harness sem $v" 1 "sem o cenário \"$v\""
done

montar
# o prefixo existe em outro `if`, mas não na condição da janela real
sed -i '' 's/ || scenario.name.hasPrefix("ask-") {$/ {/' "$MN"
caso "ask- fora da janela real" 1 "a condição da janela real não tem hasPrefix(\"ask-\")"

montar
sed -i '' 's|^vm.glifoDoAtalho = .*$|vm.glifoDoAtalho = { nil }|' "$MN"
caso "harness sem o atalho fixo" 1 "não fixa vm.glifoDoAtalho"

montar
sed -i '' 's|Atalho global foca o card (Recomendado)|Hook PreToolUse|' "$MN"
caso "harness sem os dados do mockup" 1 "sem a opção do mockup"

montar
sed -i '' '/\.goTo(page: 0)/d' "$MN"
caso "revisita sem goTo" 1 "sem '.goTo(page:'"

# === etapa 4: preview sempre inteiro ===

# --- uma função só
montar
sed -i '' 's|static func layoutDoPreview(|static func tamanhoDoPreview(|; s|Self.layoutDoPreview(|Self.tamanhoDoPreview(|' "$CV"
caso "card sem layoutDoPreview" 1 "não declara 'static func layoutDoPreview('"

montar
sed -i '' 's|    static func layoutDoPreview(|    func layoutDoPreview(|' "$CV"
caso "layoutDoPreview de instância (o NotchView não alcança)" 1 "não declara 'static func layoutDoPreview('"

montar
# declarada e nunca usada pelo card: ele desenha com um layout próprio
sed -i '' 's|if let previa = Self.layoutDoPreview(question: question, disponivel: vm.availableSize, topo: 32) {|if let previa = layoutFixo {|' "$CV"
caso "card declara e não chama" 1 "AskCardView.swift não chama 'layoutDoPreview('"

montar
sed -i '' 's|        return AskPreviewLayout.calcular(|        return AskPreviewLayout(|' "$CV"
caso "layoutDoPreview sem o modelo" 1 "sem 'AskPreviewLayout.calcular('"

montar
# a chamada só citada em comentário não conta
sed -i '' 's|^            if let previa = Self.layoutDoPreview(.*$|            // Self.layoutDoPreview( entra depois\
            if let previa = layoutFixo {|' "$CV"
caso "chamada só em comentário" 1 "AskCardView.swift não chama 'layoutDoPreview('"

montar
sed -i '' '/monospacedSystemFont(/d; s|avanco: letra.maximumAdvancement.width, linha: .*$|avanco: 6.6, linha: 13,|' "$CV"
caso "avanço e linha fixos" 1 "mede a letra com 'monospacedSystemFont('"

montar
sed -i '' 's|                if previa.lado {|                if true {|' "$CV"
caso "card sem .lado" 1 "não lê '.lado' do layout"

# --- largura da lista
montar
sed -i '' 's|lista.frame(width: AskPreviewLayout.lista)|lista.frame(width: 250)|' "$CV"
caso "lista ainda com 250" 1 "ainda tem '.frame(width: 250)'"

montar
sed -i '' 's|lista.frame(width: AskPreviewLayout.lista)|lista.frame(width: 240)|' "$CV"
caso "lista com largura fora do cálculo" 1 "a lista ao lado do preview não tem '.frame(width: 236)'"

montar
sed -i '' 's|lista.frame(width: AskPreviewLayout.lista)|lista.frame(width: 236)|' "$CV"
caso "lista com 236 literal" 0 ""

montar
sed -i '' 's|lista.frame(width: AskPreviewLayout.lista)|lista.frame(width: 2360)|' "$CV"
caso "236 como prefixo de outro número" 1 "a lista ao lado do preview não tem '.frame(width: 236)'"

# --- letra do preview
montar
sed -i '' 's|size: layout.fonte, design: .monospaced|size: 9, design: .monospaced|' "$PV"
caso "letra monoespaçada de 9 pt" 1 "ainda tem letra monoespaçada de 9 pt"

montar
sed -i '' 's|size: layout.fonte, design: .monospaced|size: 9, weight: .regular, design: .monospaced|' "$PV"
caso "letra de 9 pt com peso no meio" 1 "ainda tem letra monoespaçada de 9 pt"

montar
sed -i '' 's|size: layout.fonte, design: .monospaced|size: 11, design: .monospaced|' "$PV"
caso "letra fixa em 11" 1 "usa '.fonte' do layout"

montar
# o preview desenhado dentro do card, com a peça nova ao lado
sed -i '' 's|^    private var lista: some View {|    private var antigo: some View { Text("p").font(.system(size: 11, design: .monospaced)) }\
    private var lista: some View {|' "$CV"
caso "letra monoespaçada no card" 1 "$PASTA/AskCardView.swift desenha letra monoespaçada fora do AskPreviewView.swift"

montar
# monospacedDigit não é letra monoespaçada: é o que o selo e o Confirmar usam
sed -i '' 's|^    private var lista: some View {|    private var n: some View { Text("2").monospacedDigit() }\
    private var lista: some View {|' "$CV"
caso "monospacedDigit no card" 0 ""

montar
sed -i '' 's|layout.quadro.width|332|; s|layout.quadro.height|180|' "$PV"
caso "quadro de tamanho fixo" 1 "usa '.quadro' do layout"

montar
sed -i '' '/\.fixedSize()/d' "$PV"
caso "preview sem fixedSize" 1 "AskPreviewView.swift sem '.fixedSize('"

# --- rolagem só sob `rola`
montar
sed -i '' 's|            if layout.rola {|            if true {|' "$PV"
caso "ScrollView sem a condição do layout" 1 "'ScrollView' fora de um 'if … rola'"

montar
sed -i '' 's|            if layout.rola {|            // if layout.rola {\
            if true {|' "$PV"
caso "condição de rola só em comentário" 1 "'ScrollView' fora de um 'if … rola'"

montar
# o ScrollView de hoje: sempre lá, com os eixos saindo de um ternário
sed -i '' 's|            if layout.rola {|            if true {|; s|ScrollView(\[.vertical, .horizontal\])|ScrollView(layout.rola ? [.vertical, .horizontal] : [])|' "$PV"
caso "ScrollView sempre, eixos por ternário" 1 "'ScrollView' fora de um 'if … rola'"

montar
sed -i '' 's|            if layout.rola {|            if layout.rolagem {|' "$PV"
caso "condição em outro campo" 1 "'ScrollView' fora de um 'if … rola'"

montar
sed -i '' 's|ScrollView(\[.vertical, .horizontal\]) { corpo }|corpo.clipped()|' "$PV"
caso "preview sem rolagem nenhuma" 1 "AskPreviewView.swift sem 'ScrollView'"

montar
sed -i '' 's|            if layout.rola {|            if !layout.rola { corpo } else if layout.rola {|' "$PV"
caso "condição negada antes do ScrollView" 0 ""

# --- NotchView
montar
sed -i '' 's|AskCardView.layoutDoPreview(question: question, disponivel: vm.availableSize, topo: 32)|layoutGuardado|' "$NV"
caso "NotchView sem layoutDoPreview" 1 "Knobler/NotchView.swift não chama 'layoutDoPreview('"

montar
sed -i '' 's|width: previa?.larguraDoCard ?? 460,|width: previa != nil ? 540 : 460,|' "$NV"
caso "NotchView com 540 fixo" 1 "o questionSize ainda fixa 540"

montar
sed -i '' 's|width: previa?.larguraDoCard ?? 460,|width: previa.map { $0.quadro.width + 286 } ?? 460,|' "$NV"
caso "NotchView sem larguraDoCard" 1 "não usa 'larguraDoCard' do layout"

montar
# a função de mesmo nome que o NotchView já chama para outro card não conta
sed -i '' 's|width: previa?.larguraDoCard ?? 460,|width: previa == nil ? 460 : NotchMetrics.larguraDoCard(vm.focus, padrao: 430, linkAberto: false),|' "$NV"
caso "larguraDoCard( de outro card" 1 "não usa 'larguraDoCard' do layout"

montar
sed -i '' 's|^        var height: CGFloat = 120$|        var height: CGFloat = 120\
        let outra = AskPreviewLayout.calcular(previews: [], avanco: 6.6, linha: 13, larguraMaxima: 836, alturaMaxima: 400)|' "$NV"
caso "NotchView calculando por conta própria" 1 "chama 'AskPreviewLayout.calcular(' por conta própria"

montar
sed -i '' '/previa.quadro.height/d' "$NV"
caso "estimativa sem o preview embaixo" 1 "Knobler/NotchView.swift sem 'quadro.height'"

montar
# 540 fora do questionSize é de outro card: não conta
sed -i '' 's|^    private var questionSize: CGSize {|    private var outroCard: CGSize { CGSize(width: 540, height: 80) }\
    private var questionSize: CGSize {|' "$NV"
caso "540 fora do questionSize" 0 ""

montar
sed -i '' 's|^        var height: CGFloat = 120$|        var height: CGFloat = 120  // antes: hasPreview ? 540 : 460\
        // return CGSize(width: hasPreview ? 540 : 460, height: height)|' "$NV"
caso "540 só em linha de comentário" 0 ""

# --- harness
for v in $CENARIOS_DE_PREVIEW; do
  montar
  sed -i '' "s|Scenario(name: \"$v\", realNotch: true, frameHeight: 560, frameWidth: 900)|Scenario(name: \"$v\", realNotch: true, frameHeight: 560)|" "$MN"
  caso "$v sem frameWidth" 1 "o cenário \"$v\" sem 'frameWidth: 900'"

  montar
  sed -i '' "s|Scenario(name: \"$v\", realNotch: true, frameHeight: 560, frameWidth: 900)|Scenario(name: \"$v\", realNotch: true, frameHeight: 560, frameWidth: 560)|" "$MN"
  caso "$v com a janela de 560" 1 "o cenário \"$v\" sem 'frameWidth: 900'"
done

montar
sed -i '' 's|question: larga, disponivel: vm.availableSize, topo: 32)|question: larga)|; s|AskCardView.layoutDoPreview(question: larga)|nil as AskPreviewLayout?|' "$MN"
caso "só um cenário confere o layout" 1 "sem 'AskCardView.layoutDoPreview(' nos dois cenários"

montar
sed -i '' 's|askStore.send(.setHighlight(1))|askStore.send(.setHighlight(0))|' "$MN"
caso "ask-preview com destaque na primeira" 1 "sem '.setHighlight(1)'"

montar
sed -i '' 's|Shift+Tab volta à lista|volta|' "$MN"
caso "harness sem a tabela larga" 1 "sem a tabela larga do mockup"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do askcardcheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "askcardcheck ok"
