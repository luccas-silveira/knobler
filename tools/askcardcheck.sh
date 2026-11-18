#!/usr/bin/env bash
# Gate das etapas 3, 4, 5 e 6 do card de pergunta
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
# Etapa 5 (teto de 60% da tela, rolagem só na lista) confere:
#   - AskCardView.swift tem o parâmetro `alturaMaxima: CGFloat` e tira a altura
#     da área rolável de `AskTeto.daLista(` (a conta testada no
#     askcardmodelocheck, não uma conta solta na view);
#   - a rolagem da lista é `ScrollView(.vertical` e todo `ScrollView` do
#     AskCardView.swift fica num ramo de `if`/`guard`/`switch` com o teto na
#     condição (`teto`, `rola` ou `AskTeto.`): com espaço sobrando a lista é
#     desenhada direto;
#   - alguma view declara `struct AlturaDaListaDoAskKey`, publica a medida
#     (`preference(key: AlturaDaListaDoAskKey.self`) e lê
#     (`onPreferenceChange(AlturaDaListaDoAskKey.self`);
#   - nenhum arquivo de Knobler/AskCard/ usa `maxHeight: .infinity`;
#   - o `layoutDoPreview` desconta o mínimo da lista (`AskTeto.minimoDaLista`
#     ou 96): preview embaixo e alto encolhe a letra antes de empurrar o card
#     para fora da tela;
#   - Knobler/NotchView.swift passa `alturaMaxima:` na chamada que cria o
#     `AskCardView(` e usa `AskTeto.doCard(`;
#   - o `handleScroll` de Knobler/KnoblerApp.swift trata `.question` (deslizar
#     de lado sobre a pergunta não troca de música);
#   - tools/main.swift tem `ask-longo` e `ask-preview-alto`, os dois com a
#     altura disponível em 520; o `ask-longo` com a pergunta longa do mockup e
#     `AskTeto.doCard(`; o `ask-preview-alto` com `frameWidth: 900`, destaque na
#     primeira opção e a conta de `quadro.height`; e cada um dos três cenários
#     de preview chama `layoutDoPreview(` dentro do próprio bloco.
# Etapa 6 (teclado no card: posse pelo atalho, teclas pelo vigia, Esc solta)
# confere:
#   - Knobler/AskCard/AskTeclado.swift existe, declara `enum AskTeclado` e só
#     importa o Foundation; não conta como view (as ligações da etapa 3 têm de
#     estar nas views); tools/notchview-fontes.txt só precisa dele se alguma
#     fonte do snapshot (ou o tools/main.swift) usar as teclas; e
#     tools/check.sh roda o tools/asktecladocheck.swift com ele;
#   - Knobler/NotchViewModel.swift publica `tecladoNaPergunta` e
#     `campoDaPerguntaFocado`, tem `perguntaDoClaudeAtiva`,
#     `aoMudarTecladoDaPergunta` e `func darTecladoAPergunta(`, que chama o
#     aviso e compara o valor novo com o atual; no `alternarPeloTeclado`, o ramo
#     da pergunta (`.question`, `perguntaDoClaudeAtiva`, `darTecladoAPergunta(`)
#     vem antes de `setExpandedDirect(` e de `abertoPorTeclado = true`;
#   - Knobler/KnoblerApp.swift: o vigia de teclas (`addLocalMonitorForEvents`
#     de `.keyDown`) chama `AskTeclado.comando(` antes do guard do card aberto
#     pelo atalho (`abertoPorTeclado`), e esse guard exige modo diferente de
#     `.question`; o app trata os quatro comandos que não são ação do reducer;
#     o `makeKey` do `onKeyboardEligibilityChanged` só vem depois de olhar
#     `.question`; o `aoPerderTeclado` chama `darTecladoAPergunta(false)` sem
#     passar pelo guard do card de música; `perguntaDoClaudeAtiva` lê
#     `askStore.state.active` e não o `agentRequestStore`;
#     `aoMudarTecladoDaPergunta` tem `makeKey(`, `resignKey(` e
#     `.setHighlight(`; e existe um `darTecladoAPergunta(false)` fora do vigia
#     e do `aoPerderTeclado` (a posse cai quando a pergunta ativa muda);
#   - Knobler/AskCard/: nenhum `.onExitCommand` envia `.cancelActive`; nenhuma
#     view passa `teclado: false`/`teclado: true` fixo; o card usa
#     `vm.tecladoNaPergunta`, lê e grava `vm.campoDaPerguntaFocado` e chama
#     `darTecladoAPergunta(true)`; o rodapé tem o selo "⇥";
#   - Knobler/LinkPreviewView.swift não diz mais que o Esc fecha "como … no card
#     de pergunta" (este é o único ponto em que o comentário conta);
#   - tools/main.swift tem `ask-teclado` (`tecladoNaPergunta = true`,
#     `.setHighlight(1)`) e `ask-texto` (`tecladoNaPergunta = true`,
#     `campoDaPerguntaFocado = true`, o texto do mockup por `.setText(`), e o
#     `ask-preview` segue com `.setHighlight(1)` dentro do próprio bloco.
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
CENARIOS_DE_TETO='ask-longo ask-preview-alto'
CENARIOS_COM_LAYOUT='ask-preview ask-preview-largo ask-preview-alto'
CENARIOS_DE_TECLADO='ask-teclado ask-texto'
# texto do quadro "Escrevendo" do mockup
TEXTO_DO_MOCKUP='.setText("Atalho, mas só com o notch fechado")'
# quem cita um destes nomes usa o Knobler/AskCard/AskTeclado.swift
USA_TECLAS='(^|[^A-Za-z0-9_])Ask(Teclado|Tecla|Comando)([^A-Za-z0-9_]|$)'
# comandos do AskComando que o app executa por conta própria (`.acao` vai
# direto para o reducer), e o que cada um faz
COMANDOS=(
  'focarCampo|Tab não leva o cursor ao campo'
  'voltarALista|Esc e ⇧Tab no campo não devolvem o cursor à lista'
  'soltarTeclado|Esc na lista não solta o teclado'
  'cancelar|⌘. não manda a pergunta para o terminal'
)
# linha de ~100 colunas da tabela `LARGA` do mockup
LINHA_LARGA='Shift+Tab volta à lista'
# opção da pergunta `LONGA` do mockup
LINHA_LONGA='Guardar pela posição'
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

# views <raiz>: os .swift de Knobler/AskCard/ menos os dois arquivos puros (o
# modelo e as teclas), um por linha
views() {
  local f
  for f in "$1/$PASTA"/*.swift; do
    [ -e "$f" ] || continue
    [ "${f##*/}" = AskCardModelo.swift ] && continue
    [ "${f##*/}" = AskTeclado.swift ] && continue
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

# corpo_de <arquivo> <regex>: da primeira linha de código que casa com a regex
# até a chave que fecha o bloco (conta chaves), sem comentário (nem o de fim de
# linha)
corpo_de() {
  awk -v inicio="$2" '
    /^[[:space:]]*\/\// { next }
    !pega && $0 ~ inicio { pega = 1 }
    pega {
      sub(/[[:space:]]\/\/.*$/, "")
      print
      abre += gsub(/\{/, "{"); fecha += gsub(/\}/, "}")
      if (abre > 0 && abre == fecha) exit
    }
  ' "$1" 2>/dev/null
}

# chamada que cria o card no NotchView: do `AskCardView(` ao parêntese que fecha
# (pode quebrar em mais de uma linha), sem comentário. `AskCardView.` não conta.
criacao_do_card() {
  awk '
    /^[[:space:]]*\/\// { next }
    !pega && /AskCardView\(/ { pega = 1; sub(/^.*AskCardView\(/, "AskCardView(") }
    pega {
      sub(/[[:space:]]\/\/.*$/, "")
      print
      abre += gsub(/\(/, "("); fecha += gsub(/\)/, ")")
      if (abre == fecha) exit
    }
  ' "$1" 2>/dev/null
}

# rolagem_da_lista <arquivo>: `sem` (nenhum `ScrollView(.vertical`), `solto`
# (algum ScrollView fora de um ramo com o teto na condição) ou `ok`.
# Ramo com o teto: o bloco de um `if`/`guard`/`switch`/`case` cuja condição
# (que pode quebrar em mais de uma linha) cita `teto`, `rola` ou `AskTeto`; o
# `else` desse `if`; o resto do bloco depois de um `guard` assim; e o que
# estiver dentro de qualquer um deles. Ternário nos eixos
# (`ScrollView(x ? .vertical : [])`) é ScrollView sempre: dá `sem`.
rolagem_da_lista() {
  awk '
    function cita(t) { return t ~ /[Tt]eto|[Rr]ola/ }
    function palavra(t, p) { return t ~ ("(^|[^A-Za-z0-9_])(" p ")([^A-Za-z0-9_]|$)") }
    /^[[:space:]]*\/\// { next }
    {
      linha = $0
      sub(/[[:space:]]\/\/.*$/, "", linha)
      # `seg` = a declaração em curso desde a última chave; recomeça a cada
      # linha, menos na continuação de uma condição quebrada
      if (par <= 0) par = 0
      if (par == 0 && !segue && linha !~ /^[[:space:]]*else([^A-Za-z0-9_]|$)/) seg = ""
      n = length(linha)
      for (i = 1; i <= n; i++) {
        c = substr(linha, i, 1)
        if (c == "{") {
          proprio = (palavra(seg, "if|guard|switch|case") && cita(seg))
          herda = (!palavra(seg, "guard") && palavra(seg, "else") && ultimo)
          topo++
          ramo[topo] = (proprio || herda || (topo > 1 && (ramo[topo - 1] || guarda[topo - 1])))
          doguard[topo] = (palavra(seg, "guard") && cita(seg))
          guarda[topo] = 0
          seg = ""
        } else if (c == "}") {
          if (topo > 0) {
            ultimo = ramo[topo]
            g = doguard[topo]
            topo--
            if (g && topo > 0) guarda[topo] = 1
          }
          seg = ""
        } else {
          if (c == "(") par++
          else if (c == ")") par--
          else if (c == "S" && substr(linha, i, 10) == "ScrollView") {
            if (substr(linha, i, 20) == "ScrollView(.vertical") vertical = 1
            if (!(topo > 0 && (ramo[topo] || guarda[topo]))) solto = 1
          }
          seg = seg c
        }
      }
      seg = seg " "
      segue = (linha ~ /(,|&&|\|\||=|\()[[:space:]]*$/)
    }
    END { print (!vertical ? "sem" : (solto ? "solto" : "ok")) }
  ' "$1" 2>/dev/null
}

# bloco_do_cenario <arquivo> <nome>: do `Scenario(name: "<nome>"` até a linha
# antes do `Scenario(` seguinte, sem comentário
bloco_do_cenario() {
  awk -v alvo="Scenario(name: \"$2\"" '
    /^[[:space:]]*\/\// { next }
    index($0, "Scenario(") { pega = (index($0, alvo) > 0) }
    pega { print }
  ' "$1" 2>/dev/null
}

# esc_cancela <arquivo>: sai 0 se algum `.onExitCommand` do arquivo cita
# `cancelActive` (do `onExitCommand` até fechar as chaves; sem chave, só a
# linha quando a chamada fecha nela, senão a linha e a seguinte), sem comentário
esc_cancela() {
  awk '
    /^[[:space:]]*\/\// { next }
    {
      linha = $0
      sub(/[[:space:]]\/\/.*$/, "", linha)
      if (!pega && linha ~ /onExitCommand/) {
        pega = 1; abre = 0; fecha = 0; linhas = 0
        sub(/^.*onExitCommand/, "", linha)
      }
      if (pega) {
        linhas++
        if (linha ~ /cancelActive/) achou = 1
        abre += gsub(/\{/, "{", linha); fecha += gsub(/\}/, "}", linha)
        if (abre > 0 && abre == fecha) pega = 0
        else if (abre == 0 && (linhas >= 2 || linha ~ /\)[[:space:]]*$/)) pega = 0
      }
    }
    END { exit(achou ? 0 : 1) }
  ' "$1" 2>/dev/null
}

# vigia_de_teclas: lê da entrada padrão o bloco do vigia de `.keyDown` e
# imprime o que falta. O guard antigo é a declaração `guard` que cita
# `abertoPorTeclado`; a região dele vai até o `switch` das teclas do card de
# música (`focarVizinho`), para valer também um segundo `guard` só com o modo.
#   semguard    nenhum `abertoPorTeclado` no vigia
#   depois      `AskTeclado.comando(` só aparece depois do guard antigo
#   semquestion a região do guard antigo não cita `.question`
vigia_de_teclas() {
  awk '
    { linha[NR] = $0 }
    /(^|[^A-Za-z0-9_])guard([^A-Za-z0-9_]|$)/ { g = NR }
    !cmd && /AskTeclado\.comando\(/ { cmd = NR }
    !ini && /abertoPorTeclado/ { ini = (g ? g : NR); cita = NR }
    ini && !fim && NR > cita && /(^|[^A-Za-z0-9_])switch([^A-Za-z0-9_]|$)|focarVizinho/ { fim = NR }
    END {
      if (!ini) { print "semguard"; exit }
      if (cmd && cmd >= ini) print "depois"
      if (!fim) fim = NR + 1
      for (i = ini; i < fim; i++) if (linha[i] ~ /\.question([^A-Za-z0-9_]|$)/) q = 1
      if (!q) print "semquestion"
    }
  '
}

# antes_de <texto fixo>: lê um bloco da entrada padrão e imprime, numa linha
# só, o que vem antes da primeira ocorrência do texto
antes_de() {
  awk -v alvo="$1" '
    {
      i = index($0, alvo)
      if (i > 0) { printf "%s\n", substr($0, 1, i - 1); exit }
      printf "%s ", $0
    }
  '
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
  local teclas="$r/$PASTA/AskTeclado.swift"
  local rodape="$r/$PASTA/AskRodapeView.swift"
  local vmodel="$r/Knobler/NotchViewModel.swift"
  local link="$r/Knobler/LinkPreviewView.swift"
  local gates="$r/tools/check.sh"
  local v f n bloco uso texto motivo veredito vigia perder

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

  # === etapa 5: teto de 60% da tela, rolagem só na lista ===

  # --- o card recebe o teto e rola só a lista ---
  if [ -f "$card" ]; then
    if ! tem_re "$card" '(let|var)[[:space:]]+alturaMaxima[[:space:]]*:[[:space:]]*CGFloat'; then
      echo "FALHOU: $PASTA/AskCardView.swift sem o parâmetro 'alturaMaxima: CGFloat' (o card não sabe onde parar de crescer)"
      erro=1
    fi
    if ! tem "$card" 'AskTeto.daLista('; then
      echo "FALHOU: $PASTA/AskCardView.swift sem 'AskTeto.daLista(' (a altura da área rolável sai do modelo testado, não de conta solta na view)"
      erro=1
    fi
    case "$(rolagem_da_lista "$card")" in
      sem)
        echo "FALHOU: $PASTA/AskCardView.swift sem 'ScrollView(.vertical' (lista que passa do teto não rola e empurra o card para fora da tela)"
        erro=1 ;;
      solto)
        echo "FALHOU: $PASTA/AskCardView.swift: 'ScrollView' fora de um ramo de 'if'/'guard'/'switch' com o teto na condição ('teto', 'rola' ou 'AskTeto.'); com espaço sobrando a lista é desenhada direto"
        erro=1 ;;
    esac
    if ! corpo_de "$card" 'func[[:space:]]+layoutDoPreview[[:space:]]*[(]' \
        | grep -E 'AskTeto\.minimoDaLista|(^|[^0-9.A-Za-z_])96([^0-9.]|$)' >/dev/null; then
      echo "FALHOU: $PASTA/AskCardView.swift: o layoutDoPreview não desconta o mínimo da lista ('AskTeto.minimoDaLista' ou 96) quando o preview vai embaixo (preview alto empurra o card para fora da tela)"
      erro=1
    fi
  fi

  # --- a lista mede a própria altura natural ---
  if ! nas_views_re "$r" 'struct[[:space:]]+AlturaDaListaDoAskKey([^A-Za-z0-9_]|$)'; then
    echo "FALHOU: nenhuma view de $PASTA/ declara 'struct AlturaDaListaDoAskKey' (a lista não mede a própria altura natural)"
    erro=1
  fi
  if ! nas_views_re "$r" 'preference\([[:space:]]*key:[[:space:]]*AlturaDaListaDoAskKey\.self'; then
    echo "FALHOU: nenhuma view de $PASTA/ publica 'preference(key: AlturaDaListaDoAskKey.self' (ninguém mede a lista)"
    erro=1
  fi
  if ! nas_views_re "$r" 'onPreferenceChange\([[:space:]]*AlturaDaListaDoAskKey\.self'; then
    echo "FALHOU: nenhuma view de $PASTA/ lê 'onPreferenceChange(AlturaDaListaDoAskKey.self' (a medida da lista não chega à conta do teto)"
    erro=1
  fi

  # --- nada que trave a auto-medição ---
  for f in "$r/$PASTA"/*.swift; do
    [ -e "$f" ] || continue
    if tem_re "$f" 'maxHeight:[[:space:]]*\.infinity'; then
      echo "FALHOU: ${f#"$r"/} usa 'maxHeight: .infinity' (trava a auto-medição: o card ocupa o que derem em vez de dizer a própria altura)"
      erro=1
    fi
  done

  # --- o NotchView entrega o teto ---
  if [ -f "$notch" ]; then
    case "$(criacao_do_card "$notch")" in
      *'alturaMaxima:'*) ;;
      *)
        echo "FALHOU: Knobler/NotchView.swift não passa 'alturaMaxima:' ao criar o AskCardView (o card cresce sem teto)"
        erro=1 ;;
    esac
    if ! tem "$notch" 'AskTeto.doCard('; then
      echo "FALHOU: Knobler/NotchView.swift sem 'AskTeto.doCard(' (o teto de 60% sai do modelo testado, não de conta solta)"
      erro=1
    fi
  fi

  # --- gesto de lado com pergunta na tela ---
  if [ -f "$app" ]; then
    bloco=$(corpo_de "$app" 'func[[:space:]]+handleScroll[[:space:]]*[(]')
    if [ -z "$bloco" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift sem 'func handleScroll(' (é ali que o gesto de lado troca de música)"
      erro=1
    elif ! printf '%s\n' "$bloco" | grep -E '\.question([^A-Za-z0-9_]|$)' >/dev/null; then
      echo "FALHOU: Knobler/KnoblerApp.swift: o handleScroll não trata '.question' (deslizar de lado sobre a pergunta troca de música)"
      erro=1
    fi
  fi

  # --- cenários do teto no harness ---
  if [ -f "$harness" ]; then
    for v in $CENARIOS_DE_TETO; do
      bloco=$(bloco_do_cenario "$harness" "$v")
      if [ -z "$bloco" ]; then
        echo "FALHOU: tools/main.swift sem o cenário \"$v\""
        erro=1
        continue
      fi
      if ! printf '%s\n' "$bloco" | grep -E 'availableSize(\.height[[:space:]]*=|[[:space:]]*=.*height:)[[:space:]]*520([^0-9.]|$)' >/dev/null; then
        echo "FALHOU: tools/main.swift: o cenário \"$v\" não fixa a altura disponível em 520 (com os 900 de sempre nada bate no teto)"
        erro=1
      fi
      case "$v" in
        ask-longo)
          case "$bloco" in
            *'AskTeto.doCard('*) ;;
            *)
              echo "FALHOU: tools/main.swift: o cenário \"ask-longo\" sem 'AskTeto.doCard(' (nada prova que a pergunta longa passa do teto)"
              erro=1 ;;
          esac ;;
        ask-preview-alto)
          case "$bloco" in
            *'.setHighlight(0)'*) ;;
            *)
              echo "FALHOU: tools/main.swift: o cenário \"ask-preview-alto\" sem '.setHighlight(0)' (o preview alto é o da primeira opção)"
              erro=1 ;;
          esac
          case "$bloco" in
            *'quadro.height'*) ;;
            *)
              echo "FALHOU: tools/main.swift: o cenário \"ask-preview-alto\" sem a conta de 'quadro.height' (nada prova que o preview embaixo deixa o mínimo da lista dentro da tela)"
              erro=1 ;;
          esac ;;
      esac
    done
    if ! tem "$harness" "$LINHA_LONGA"; then
      echo "FALHOU: tools/main.swift sem a pergunta longa do mockup ('$LINHA_LONGA'; sem ela nenhum PNG prova a lista rolando)"
      erro=1
    fi
    if ! tem_re "$harness" 'Scenario\(name: "ask-preview-alto"[^{]*frameWidth:[[:space:]]*900([^0-9]|$)'; then
      echo "FALHOU: tools/main.swift: o cenário \"ask-preview-alto\" sem 'frameWidth: 900' (o card alargado bate no limite da janela)"
      erro=1
    fi
    for v in $CENARIOS_COM_LAYOUT; do
      case "$(bloco_do_cenario "$harness" "$v")" in
        *'layoutDoPreview('*) ;;
        *)
          echo "FALHOU: tools/main.swift: o cenário \"$v\" não chama 'layoutDoPreview(' (nada prova ao lado/embaixo, letra e rolagem nesse cenário)"
          erro=1 ;;
      esac
    done
  fi

  # === etapa 6: teclado no card ===

  # --- a função pura das teclas ---
  if [ ! -f "$teclas" ]; then
    echo "FALHOU: $PASTA/AskTeclado.swift não existe (a função pura que diz que tecla vira que comando)"
    erro=1
  else
    if ! tem_re "$teclas" 'enum[[:space:]]+AskTeclado([^A-Za-z0-9_]|$)'; then
      echo "FALHOU: $PASTA/AskTeclado.swift não declara 'enum AskTeclado'"
      erro=1
    fi
    n=$(grep -vE '^[[:space:]]*//' "$teclas" | grep -E '^[[:space:]]*(@[A-Za-z_]+[[:space:]]+)*import[[:space:]]' \
      | grep -cvE 'import[[:space:]]+Foundation[[:space:]]*$')
    if [ "${n:-0}" -gt 0 ]; then
      echo "FALHOU: $PASTA/AskTeclado.swift importa mais que o Foundation (a função das teclas é pura: sem NSEvent, AppKit ou SwiftUI)"
      erro=1
    fi
  fi
  # A linha nas fontes do snapshot só é exigida se alguma fonte usar as teclas:
  # o vigia mora no KnoblerApp.swift, que não é fonte do snapshot.
  if [ -f "$fontes" ] && ! grep -qxF -- "$PASTA/AskTeclado.swift" "$fontes"; then
    while IFS= read -r f; do
      case "$f" in ''|'#'*|"$PASTA/AskTeclado.swift") continue ;; esac
      if tem_re "$r/$f" "$USA_TECLAS"; then
        echo "FALHOU: tools/notchview-fontes.txt sem '$PASTA/AskTeclado.swift' ($f usa as teclas e entra no typecheck do snapshot)"
        erro=1
        break
      fi
    done < <(cat "$fontes"; echo tools/main.swift)
  fi
  if [ ! -f "$gates" ]; then
    echo "FALHOU: tools/check.sh não existe"
    erro=1
  elif ! grep -E '^swift_teste tools/asktecladocheck\.swift .*Knobler/AskModels\.swift .*Knobler/AskFeature\.swift .*Knobler/AskCard/AskTeclado\.swift' "$gates" >/dev/null; then
    echo "FALHOU: tools/check.sh sem a linha 'swift_teste tools/asktecladocheck.swift … Knobler/AskCard/AskTeclado.swift' (gate fora do check.sh a CI não vê)"
    erro=1
  fi

  # --- posse do teclado na view model ---
  if [ ! -f "$vmodel" ]; then
    echo "FALHOU: Knobler/NotchViewModel.swift não existe"
    erro=1
  else
    if ! tem_re "$vmodel" '@Published[^/]*var[[:space:]]+tecladoNaPergunta([^A-Za-z0-9_]|$)'; then
      echo "FALHOU: Knobler/NotchViewModel.swift sem '@Published var tecladoNaPergunta' (a posse do teclado é estado próprio da pergunta, não o abertoPorTeclado)"
      erro=1
    fi
    if ! tem_re "$vmodel" '@Published[^/]*var[[:space:]]+campoDaPerguntaFocado([^A-Za-z0-9_]|$)'; then
      echo "FALHOU: Knobler/NotchViewModel.swift sem '@Published var campoDaPerguntaFocado' (Tab e Esc levam o cursor ao campo e de volta por ele)"
      erro=1
    fi
    if ! tem_re "$vmodel" 'var[[:space:]]+perguntaDoClaudeAtiva[[:space:]]*:'; then
      echo "FALHOU: Knobler/NotchViewModel.swift sem 'var perguntaDoClaudeAtiva:' (o atalho não distingue a pergunta do Claude do card do Codex)"
      erro=1
    fi
    if ! tem_re "$vmodel" 'var[[:space:]]+aoMudarTecladoDaPergunta[[:space:]]*:'; then
      echo "FALHOU: Knobler/NotchViewModel.swift sem 'var aoMudarTecladoDaPergunta:' (o painel não fica sabendo da posse)"
      erro=1
    fi
    bloco=$(corpo_de "$vmodel" 'func[[:space:]]+darTecladoAPergunta[[:space:]]*[(]')
    if [ -z "$bloco" ]; then
      echo "FALHOU: Knobler/NotchViewModel.swift sem 'func darTecladoAPergunta('"
      erro=1
    else
      case "$bloco" in
        *aoMudarTecladoDaPergunta*) ;;
        *)
          echo "FALHOU: Knobler/NotchViewModel.swift: o darTecladoAPergunta não chama 'aoMudarTecladoDaPergunta' (o painel não vira janela-chave nem larga a chave)"
          erro=1 ;;
      esac
      if ! printf '%s\n' "$bloco" | grep -E '[!=]=' >/dev/null; then
        echo "FALHOU: Knobler/NotchViewModel.swift: o darTecladoAPergunta não compara o valor novo com o atual ('!=' ou '=='); avisando sem mudança, o resignKey do aviso chama o aoPerderTeclado, que chama o darTecladoAPergunta de novo"
        erro=1
      fi
    fi
    bloco=$(corpo_de "$vmodel" 'func[[:space:]]+alternarPeloTeclado[[:space:]]*[(]')
    if [ -z "$bloco" ]; then
      echo "FALHOU: Knobler/NotchViewModel.swift sem 'func alternarPeloTeclado(' (é por ele que o atalho global entra)"
      erro=1
    else
      veredito=$(printf '%s\n' "$bloco" | awk '
        !p && /perguntaDoClaudeAtiva/ { p = NR }
        !d && /darTecladoAPergunta\(/ { d = NR }
        !e && /setExpandedDirect\(|abertoPorTeclado[[:space:]]*=[[:space:]]*true/ { e = NR }
        /\.question([^A-Za-z0-9_]|$)/ { q = 1 }
        END {
          if (!p) print "semconsulta"
          if (!d) print "semposse"
          if (!q) print "semmodo"
          if (e && ((p && p > e) || (d && d > e))) print "depois"
        }')
      case "$veredito" in *semconsulta*)
        echo "FALHOU: Knobler/NotchViewModel.swift: o alternarPeloTeclado não consulta 'perguntaDoClaudeAtiva' (com o card do Codex na tela o atalho tem de se comportar como hoje)"
        erro=1 ;;
      esac
      case "$veredito" in *semposse*)
        echo "FALHOU: Knobler/NotchViewModel.swift: o alternarPeloTeclado não chama 'darTecladoAPergunta(' (com pergunta na tela o atalho não dá o teclado a ela)"
        erro=1 ;;
      esac
      case "$veredito" in *semmodo*)
        echo "FALHOU: Knobler/NotchViewModel.swift: o alternarPeloTeclado não olha '.question' (o ramo da pergunta só vale com a pergunta na tela)"
        erro=1 ;;
      esac
      case "$veredito" in *depois*)
        echo "FALHOU: Knobler/NotchViewModel.swift: no alternarPeloTeclado o ramo da pergunta vem depois de 'setExpandedDirect(' ou 'abertoPorTeclado = true' (o atalho arma o card de música por trás da pergunta)"
        erro=1 ;;
      esac
    fi
  fi

  # --- o app: vigia de teclas, herança da chave e posse que cai sozinha ---
  if [ -f "$app" ]; then
    vigia=$(corpo_de "$app" 'addLocalMonitorForEvents[(]matching:[[:space:]]*[.]keyDown')
    if [ -z "$vigia" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift sem o vigia de teclas ('addLocalMonitorForEvents(matching: .keyDown')"
      erro=1
    else
      case "$vigia" in
        *'AskTeclado.comando('*) ;;
        *)
          echo "FALHOU: Knobler/KnoblerApp.swift: o vigia de teclas não chama 'AskTeclado.comando(' (as teclas da pergunta não passam pela função testada)"
          erro=1 ;;
      esac
      veredito=$(printf '%s\n' "$vigia" | vigia_de_teclas)
      case "$veredito" in *semguard*)
        echo "FALHOU: Knobler/KnoblerApp.swift: o vigia de teclas perdeu o guard do card aberto pelo atalho ('abertoPorTeclado'; ← → Tab e Esc do card de música dependem dele)"
        erro=1 ;;
      esac
      case "$veredito" in *depois*)
        echo "FALHOU: Knobler/KnoblerApp.swift: no vigia de teclas, 'AskTeclado.comando(' vem depois do guard do card aberto pelo atalho (o guard devolve o evento antes e a tecla não chega à pergunta)"
        erro=1 ;;
      esac
      case "$veredito" in *semquestion*)
        echo "FALHOU: Knobler/KnoblerApp.swift: no vigia de teclas, o guard do card aberto pelo atalho não exige modo diferente de '.question' (← → Tab e Esc mexem no card de música por trás da pergunta)"
        erro=1 ;;
      esac
    fi
    for uso in "${COMANDOS[@]}"; do
      texto="${uso%%|*}"; motivo="${uso#*|}"
      if ! tem_re "$app" "[.]$texto([^A-Za-z0-9_]|\$)"; then
        echo "FALHOU: Knobler/KnoblerApp.swift não trata o comando '.$texto' ($motivo)"
        erro=1
      fi
    done

    bloco=$(corpo_de "$app" 'onKeyboardEligibilityChanged:[[:space:]]*[{]')
    if [ -z "$bloco" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift sem o bloco 'onKeyboardEligibilityChanged: {' (é ali que o painel herda a chave)"
      erro=1
    else
      veredito=$(printf '%s\n' "$bloco" | awk '
        !m && /makeKey\(/ { m = NR }
        !q && /\.question([^A-Za-z0-9_]|$)/ { q = NR }
        END { if (m && (!q || q > m)) print "herda" }')
      if [ "$veredito" = herda ]; then
        echo "FALHOU: Knobler/KnoblerApp.swift: o makeKey do onKeyboardEligibilityChanged não exige modo diferente de '.question' (pergunta que chega com o card do atalho aberto herda a chave e rouba o teclado)"
        erro=1
      fi
    fi

    perder=$(corpo_de "$app" 'aoPerderTeclado[[:space:]]*=[[:space:]]*[{]')
    if [ -z "$perder" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift não atribui 'aoPerderTeclado = {' (clicar em outro app tem de soltar o teclado da pergunta)"
      erro=1
    else
      case "$perder" in
        *'darTecladoAPergunta(false)'*)
          if printf '%s\n' "$perder" | antes_de 'darTecladoAPergunta(false)' \
              | grep -E '(^|[^A-Za-z0-9_])guard[^{]*(abertoPorTeclado|[.]music)' >/dev/null; then
            echo "FALHOU: Knobler/KnoblerApp.swift: no aoPerderTeclado, 'darTecladoAPergunta(false)' vem depois do guard do card de música (com pergunta na tela o guard sai antes e clicar em outro app não solta o teclado)"
            erro=1
          fi ;;
        *)
          echo "FALHOU: Knobler/KnoblerApp.swift: o aoPerderTeclado não chama 'darTecladoAPergunta(false)' (clicar em outro app não solta o teclado da pergunta)"
          erro=1 ;;
      esac
    fi

    bloco=$(corpo_de "$app" 'perguntaDoClaudeAtiva[[:space:]]*=[[:space:]]*[{]')
    if [ -z "$bloco" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift não atribui 'perguntaDoClaudeAtiva = {' (sem ela o atalho nunca dá o teclado à pergunta)"
      erro=1
    else
      if ! printf '%s\n' "$bloco" | grep -E 'askStore[?]?[.]state[.]active' >/dev/null; then
        echo "FALHOU: Knobler/KnoblerApp.swift: 'perguntaDoClaudeAtiva' não lê 'askStore.state.active'"
        erro=1
      fi
      case "$bloco" in *agentRequestStore*)
        echo "FALHOU: Knobler/KnoblerApp.swift: 'perguntaDoClaudeAtiva' cita o 'agentRequestStore' (só a pergunta do Claude conta; o card do Codex fica como hoje)"
        erro=1 ;;
      esac
    fi

    bloco=$(corpo_de "$app" 'aoMudarTecladoDaPergunta[[:space:]]*=[[:space:]]*[{]')
    if [ -z "$bloco" ]; then
      echo "FALHOU: Knobler/KnoblerApp.swift não atribui 'aoMudarTecladoDaPergunta = {' (a posse muda e o painel não vira nem deixa de ser janela-chave)"
      erro=1
    else
      case "$bloco" in *'makeKey('*) ;; *)
        echo "FALHOU: Knobler/KnoblerApp.swift: o aoMudarTecladoDaPergunta sem 'makeKey(' (ganhar o teclado não faz do painel a janela-chave)"
        erro=1 ;;
      esac
      case "$bloco" in *'resignKey('*) ;; *)
        echo "FALHOU: Knobler/KnoblerApp.swift: o aoMudarTecladoDaPergunta sem 'resignKey(' (soltar o teclado não devolve as teclas ao app da frente)"
        erro=1 ;;
      esac
      case "$bloco" in *'.setHighlight('*) ;; *)
        echo "FALHOU: Knobler/KnoblerApp.swift: o aoMudarTecladoDaPergunta sem '.setHighlight(' (o destaque entra com o teclado e sai com ele)"
        erro=1 ;;
      esac
    fi

    # a posse cai quando a pergunta ativa muda: uma chamada que não seja a do
    # Esc (vigia) nem a do clique em outro app (aoPerderTeclado)
    n=$(( $(contar "$app" 'darTecladoAPergunta(false)') \
      - $(printf '%s\n' "$vigia" | grep -cF -- 'darTecladoAPergunta(false)') \
      - $(printf '%s\n' "$perder" | grep -cF -- 'darTecladoAPergunta(false)') ))
    if [ "$n" -le 0 ] && ! tem "$notch" 'darTecladoAPergunta(false)' \
        && ! nas_views "$r" 'darTecladoAPergunta(false)'; then
      echo "FALHOU: nenhum 'darTecladoAPergunta(false)' fora do vigia de teclas e do aoPerderTeclado (a posse não cai quando a pergunta ativa muda: respondida, cancelada, expirada ou promovida da fila)"
      erro=1
    fi
  fi

  # --- o card segue a posse ---
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    if esc_cancela "$f"; then
      echo "FALHOU: ${f#"$r"/}: um '.onExitCommand' ainda envia '.cancelActive' (Esc solta o teclado; quem manda a pergunta para o terminal é o ✕ e o ⌘.)"
      erro=1
    fi
    if tem_re "$f" '(^|[^A-Za-z0-9_])teclado:[[:space:]]*(false|true)([^A-Za-z0-9_]|$)'; then
      echo "FALHOU: ${f#"$r"/} passa 'teclado:' fixo em false ou true (contorno do destaque, selos acesos e legenda de teclas seguem vm.tecladoNaPergunta)"
      erro=1
    fi
  done < <(views "$r")
  if [ -f "$card" ]; then
    if ! tem "$card" 'vm.tecladoNaPergunta'; then
      echo "FALHOU: $PASTA/AskCardView.swift não usa 'vm.tecladoNaPergunta' (o card não muda quando ganha o teclado)"
      erro=1
    fi
    if ! tem "$card" 'vm.campoDaPerguntaFocado'; then
      echo "FALHOU: $PASTA/AskCardView.swift não usa 'vm.campoDaPerguntaFocado' (Tab do vigia não leva o cursor ao campo)"
      erro=1
    elif ! tem_re "$card" 'vm[.]campoDaPerguntaFocado[[:space:]]*=[^=]'; then
      echo "FALHOU: $PASTA/AskCardView.swift não grava 'vm.campoDaPerguntaFocado =' (clicar no campo ou sair dele não chega à view model)"
      erro=1
    fi
    if ! tem "$card" 'darTecladoAPergunta(true)'; then
      echo "FALHOU: $PASTA/AskCardView.swift sem 'darTecladoAPergunta(true)' (clicar no campo de texto não dá o teclado à pergunta)"
      erro=1
    fi
  fi
  if [ -f "$rodape" ] && ! tem "$rodape" '"⇥"'; then
    echo "FALHOU: $PASTA/AskRodapeView.swift sem o selo \"⇥\" (com o teclado na lista, o campo mostra a tecla que leva a ele)"
    erro=1
  fi

  # --- o comentário do preview de link (aqui o que conta é o comentário) ---
  if [ -f "$link" ] && grep -E 'como[^.;(]*[[:space:]](no|do)[[:space:]]+card[[:space:]]+de[[:space:]]+pergunta' "$link" >/dev/null; then
    echo "FALHOU: Knobler/LinkPreviewView.swift ainda diz que o Esc fecha \"como … no card de pergunta\" (lá o Esc agora solta o teclado)"
    erro=1
  fi

  # --- cenários do teclado no harness ---
  if [ -f "$harness" ]; then
    for v in $CENARIOS_DE_TECLADO; do
      bloco=$(bloco_do_cenario "$harness" "$v")
      if [ -z "$bloco" ]; then
        echo "FALHOU: tools/main.swift sem o cenário \"$v\""
        erro=1
        continue
      fi
      if ! printf '%s\n' "$bloco" | grep -E 'tecladoNaPergunta[[:space:]]*=[[:space:]]*true' >/dev/null; then
        echo "FALHOU: tools/main.swift: o cenário \"$v\" não liga 'vm.tecladoNaPergunta = true' (o PNG sairia em repouso)"
        erro=1
      fi
      case "$v" in
        ask-teclado)
          case "$bloco" in *'.setHighlight(1)'*) ;; *)
            echo "FALHOU: tools/main.swift: o cenário \"ask-teclado\" sem '.setHighlight(1)' (o contorno do quadro do mockup é o da segunda opção)"
            erro=1 ;;
          esac ;;
        ask-texto)
          if ! printf '%s\n' "$bloco" | grep -E 'campoDaPerguntaFocado[[:space:]]*=[[:space:]]*true' >/dev/null; then
            echo "FALHOU: tools/main.swift: o cenário \"ask-texto\" não liga 'vm.campoDaPerguntaFocado = true' (a legenda do campo não aparece)"
            erro=1
          fi
          case "$bloco" in *"$TEXTO_DO_MOCKUP"*) ;; *)
            echo "FALHOU: tools/main.swift: o cenário \"ask-texto\" sem '$TEXTO_DO_MOCKUP' (o texto do quadro \"Escrevendo\" do mockup)"
            erro=1 ;;
          esac ;;
      esac
    done
    # com o ask-teclado no arquivo, a conferência da etapa 4 (arquivo inteiro)
    # não vê mais o ask-preview sem o destaque: quem pega é o bloco
    case "$(bloco_do_cenario "$harness" ask-preview)" in *'.setHighlight(1)'*) ;; *)
      echo "FALHOU: tools/main.swift: o cenário \"ask-preview\" sem '.setHighlight(1)' no próprio bloco (o preview exibido é o da segunda opção)"
      erro=1 ;;
    esac
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
    let alturaMaxima: CGFloat
    @State private var listaNatural: CGFloat = 0
    @State private var alturaDoCard: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduzMovimento

    static func layoutDoPreview(question: AskQuestion, disponivel: CGSize, topo: CGFloat) -> AskPreviewLayout? {
        let letra = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let reserva = cabeAoLado(question, disponivel) ? 0 : AskTeto.minimoDaLista
        return AskPreviewLayout.calcular(
            previews: question.options.compactMap(\.preview),
            avanco: letra.maximumAdvancement.width, linha: letra.ascender - letra.descender + letra.leading,
            larguraMaxima: disponivel.width - 64, alturaMaxima: max(120, disponivel.height - 24 - topo - 150 - reserva))
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
            AskRodapeView(itens: AskLegenda.itens(teclado: vm.tecladoNaPergunta, campo: textFocused, multipla: false,
                                                  abas: false, atalho: vm.glifoDoAtalho()),
                          selo: vm.tecladoNaPergunta && !textFocused)
        }
        .onPreferenceChange(AlturaDaListaDoAskKey.self) { listaNatural = $0 }
        .onChange(of: vm.campoDaPerguntaFocado) { textFocused = vm.campoDaPerguntaFocado }
        .onChange(of: textFocused) {
            vm.campoDaPerguntaFocado = textFocused
            if textFocused { vm.darTecladoAPergunta(true) }
        }
    }

    @ViewBuilder
    private var lista: some View {
        if let teto = AskTeto.daLista(natural: listaNatural, card: alturaDoCard,
                                      listaAtual: listaNatural, tetoDoCard: alturaMaxima) {
            ScrollView(.vertical) { opcoes }
                .frame(height: teto)
        } else {
            opcoes
        }
    }

    private var opcoes: some View {
        VStack {
            AskOpcaoView(rotulo: AskRotulo.separar("a").texto,
                         teclado: vm.tecladoNaPergunta,
                         entrar: { askStore.send(.setHighlight(0)) },
                         clicar: { askStore.send(.choose(index: 0)) })
        }
        .background(GeometryReader { p in
            Color.clear.preference(key: AlturaDaListaDoAskKey.self, value: p.size.height)
        })
    }
}

struct AlturaDoAskKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct AlturaDaListaDoAskKey: PreferenceKey {
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
    let selo: Bool
    var body: some View {
        TextField("Outra resposta…", text: .constant("")).opacity(AskEstilo.linha)
        if selo { AskSeloView(texto: "⇥") }
    }
}
EOF
  cat > "$T/r/$PASTA/AskTeclado.swift" <<'EOF'
import Foundation

struct AskTecla: Equatable {
    var codigo: Int
    var caracteres: String
}

enum AskComando: Equatable {
    case acao(AskAction)
    case focarCampo, voltarALista, soltarTeclado, cancelar
}

enum AskTeclado {
    static func comando(_ tecla: AskTecla, campo: Bool, estado: AskState) -> AskComando? {
        if tecla.caracteres == "2" { return .acao(.choose(index: 1)) }
        if tecla.codigo == 124 { return .acao(.goTo(page: estado.page + 1)) }
        if tecla.codigo == 125 { return .acao(.moveHighlight(by: 1)) }
        return nil
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
    private var questionCard: some View {
        AskCardView(vm: vm, askStore: askStore,
                    alturaMaxima: AskTeto.doCard(disponivel: vm.availableSize.height, topo: topInset))
            .frame(width: currentSize.width - 40)
    }
}
EOF
  cat > "$T/r/Knobler/NotchViewModel.swift" <<'EOF'
final class NotchViewModel: ObservableObject {
    @Published private(set) var abertoPorTeclado = false
    @Published var tecladoNaPergunta = false
    @Published var campoDaPerguntaFocado = false
    var perguntaDoClaudeAtiva: () -> Bool = { false }
    var aoMudarTecladoDaPergunta: ((Bool) -> Void)?

    func darTecladoAPergunta(_ liga: Bool) {
        guard tecladoNaPergunta != liga else { return }
        tecladoNaPergunta = liga
        aoMudarTecladoDaPergunta?(liga)
    }

    func alternarPeloTeclado() {
        if mode == .question, perguntaDoClaudeAtiva() { darTecladoAPergunta(!tecladoNaPergunta); return }
        if expanded && abertoPorTeclado { setExpandedDirect(false); return }
        abertoPorTeclado = true
        setExpandedDirect(true)
    }
}
EOF
  cat > "$T/r/Knobler/LinkPreviewView.swift" <<'EOF'
struct LinkPreviewView: View {
    var body: some View {
        // Esc fecha o preview, como na nota rápida
        Text("x").onExitCommand { preview.fechar() }
    }
}
EOF
  cat > "$T/r/Knobler/KnoblerApp.swift" <<'EOF'
let vm = NotchViewModel()
vm.glifoDoAtalho = { KeyboardShortcuts.getShortcut(for: .abrirNotch)?.shortcutGlyph }
func handleScroll(_ event: NSEvent) -> NSEvent? {
    let expanded = vm.mode == .music
    if vm.mode == .question { return event }
    return expanded ? nil : event
}
func setupAtalhoDoNotch() {
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
        if let window = NSApp.keyWindow as? NotchWindow, let vm = self?.vmDa(window),
           vm.tecladoNaPergunta, vm.mode == .question, self?.askStore?.state.active != nil {
            let tecla = AskTecla(codigo: Int(event.keyCode), caracteres: event.charactersIgnoringModifiers ?? "")
            let campo = window.firstResponder is NSText
            switch AskTeclado.comando(tecla, campo: campo, estado: askStore.state) {
            case .acao(let acao)?: askStore.send(acao)
            case .focarCampo?: vm.campoDaPerguntaFocado = true
            case .voltarALista?: vm.campoDaPerguntaFocado = false
            case .soltarTeclado?: vm.darTecladoAPergunta(false)
            case .cancelar?: askStore.send(.cancelActive)
            case nil: return campo ? event : nil
            }
            return nil
        }
        guard let window = NSApp.keyWindow as? NotchWindow, let vm = self?.vmDa(window),
              vm.abertoPorTeclado, vm.mode != .question, !(window.firstResponder is NSText) else { return event }
        switch Int(event.keyCode) {
        case kVK_LeftArrow: vm.focarVizinho(avancando: false)
        case kVK_Escape: vm.setExpandedDirect(false)
        default: return event
        }
        return nil
    }
}
func montarTela() {
    viewModel.perguntaDoClaudeAtiva = { [weak askStore] in askStore?.state.active != nil }
    viewModel.aoMudarTecladoDaPergunta = { [weak panel, weak viewModel] liga in
        if liga {
            panel?.allowsKeyboard = true
            panel?.makeKey()
            if askStore.state.highlight == nil { askStore.send(.setHighlight(0)) }
        } else {
            askStore.send(.setHighlight(nil))
            viewModel?.campoDaPerguntaFocado = false
            if panel?.isKeyWindow == true { panel?.resignKey() }
        }
    }
    let host = NotchHostingView(rootView: NotchView(vm: viewModel,
        onKeyboardEligibilityChanged: { [weak panel, weak viewModel] active in
            panel?.allowsKeyboard = active
            if !active, panel?.isKeyWindow == true { panel?.resignKey() }
            if active, viewModel?.abertoPorTeclado == true, viewModel?.mode != .question { panel?.makeKey() }
        }))
    panel.aoPerderTeclado = { [weak viewModel] in
        guard let viewModel else { return }
        viewModel.darTecladoAPergunta(false)
        guard viewModel.abertoPorTeclado, viewModel.mode == .music else { return }
        viewModel.setExpandedDirect(false)
    }
}
func observarPergunta() {
    askStore.$state.map(\.active?.id).removeDuplicates().sink { [weak self] _ in
        self?.notches.values.forEach { $0.viewModel.darTecladoAPergunta(false) }
    }
}
EOF
  cat > "$T/r/tools/check.sh" <<'EOF'
swift_teste tools/askcardmodelocheck.swift Knobler/AskModels.swift Knobler/AskCard/AskCardModelo.swift
swift_teste tools/asktecladocheck.swift Knobler/AskModels.swift Knobler/AskFeature.swift Knobler/AskCard/AskTeclado.swift
bash_teste tools/askcardcheck.sh
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
    Scenario(name: "ask-longo", realNotch: true, frameHeight: 620) { vm, _, askStore in
        vm.availableSize.height = 520
        let opcao = "Guardar pela posição"
        precondition(AskTeto.doCard(disponivel: 520, topo: 32) < 358)
    },
    Scenario(name: "ask-preview-alto", realNotch: true, frameHeight: 620, frameWidth: 900) { vm, _, askStore in
        vm.availableSize = CGSize(width: 900, height: 520)
        askStore.send(.setHighlight(0))
        let layout = AskCardView.layoutDoPreview(question: alta, disponivel: vm.availableSize, topo: 32)
        precondition((layout?.quadro.height ?? .infinity) <= 218)
    },
    Scenario(name: "ask-paged", realNotch: true) { _, _, askStore in },
    Scenario(name: "ask-revisita", realNotch: true) { _, _, askStore in
        askStore.send(.goTo(page: 0))
    },
    Scenario(name: "ask-teclado", realNotch: true, frameHeight: 480) { vm, _, askStore in
        vm.tecladoNaPergunta = true
        askStore.send(.setHighlight(1))
    },
    Scenario(name: "ask-texto", realNotch: true, frameHeight: 480) { vm, _, askStore in
        vm.tecladoNaPergunta = true
        vm.campoDaPerguntaFocado = true
        askStore.send(.setText("Atalho, mas só com o notch fechado"))
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
TC="$T/r/$PASTA/AskTeclado.swift"
VM="$T/r/Knobler/NotchViewModel.swift"
LK="$T/r/Knobler/LinkPreviewView.swift"
CK="$T/r/tools/check.sh"

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
# (o ask-preview-alto da etapa 5 também chama: sai junto, senão ainda seriam duas)
sed -i '' 's|question: larga, disponivel: vm.availableSize, topo: 32)|question: larga)|; s|AskCardView.layoutDoPreview(question: larga)|nil as AskPreviewLayout?|; s|AskCardView.layoutDoPreview(question: alta, disponivel: vm.availableSize, topo: 32)|nil as AskPreviewLayout?|' "$MN"
caso "só um cenário confere o layout" 1 "sem 'AskCardView.layoutDoPreview(' nos dois cenários"

montar
sed -i '' 's|askStore.send(.setHighlight(1))|askStore.send(.setHighlight(0))|' "$MN"
caso "ask-preview com destaque na primeira" 1 "sem '.setHighlight(1)'"

montar
sed -i '' 's|Shift+Tab volta à lista|volta|' "$MN"
caso "harness sem a tabela larga" 1 "sem a tabela larga do mockup"

# === etapa 5: teto de 60% da tela, rolagem só na lista ===

# nova_lista: troca a `lista` do card falso pelo texto da entrada padrão
nova_lista() {
  sed -i '' '/^    @ViewBuilder$/,/^    }$/d' "$CV"
  {
    sed -n '1,/^    private var opcoes: some View {$/p' "$CV" | sed '$d'
    cat
    sed -n '/^    private var opcoes: some View {$/,$p' "$CV"
  } > "$CV.novo"
  mv "$CV.novo" "$CV"
}

# --- parâmetro e conta do modelo
montar
sed -i '' '/^    let alturaMaxima: CGFloat$/d' "$CV"
caso "card sem alturaMaxima" 1 "sem o parâmetro 'alturaMaxima: CGFloat'"

montar
sed -i '' 's|^    let alturaMaxima: CGFloat$|    // let alturaMaxima: CGFloat|' "$CV"
caso "alturaMaxima só em comentário" 1 "sem o parâmetro 'alturaMaxima: CGFloat'"

montar
sed -i '' 's|^    let alturaMaxima: CGFloat$|    var alturaMaxima : CGFloat = .infinity|' "$CV"
caso "alturaMaxima como var com valor padrão" 0 ""

montar
sed -i '' 's|if let teto = AskTeto.daLista(natural: listaNatural, card: alturaDoCard,|if let teto = tetoNaMao(natural: listaNatural, card: alturaDoCard,|' "$CV"
caso "teto da lista por conta solta" 1 "sem 'AskTeto.daLista('"

# --- rolagem só sob o teto
montar
sed -i '' 's|ScrollView(.vertical) { opcoes }|opcoes.clipped()|' "$CV"
caso "lista sem rolagem" 1 "AskCardView.swift sem 'ScrollView(.vertical'"

montar
sed -i '' 's|^            ScrollView(.vertical) { opcoes }$|            // ScrollView(.vertical) { opcoes }\
            opcoes|' "$CV"
caso "rolagem só em comentário" 1 "AskCardView.swift sem 'ScrollView(.vertical'"

montar
# ScrollView sempre, com os eixos saindo de um ternário
sed -i '' 's|ScrollView(.vertical) { opcoes }|ScrollView(teto > 0 ? .vertical : []) { opcoes }|' "$CV"
caso "eixos da lista por ternário" 1 "AskCardView.swift sem 'ScrollView(.vertical'"

montar
# a condição existe, mas não é a do teto
sed -i '' 's|^        if let teto = AskTeto.daLista(natural: listaNatural, card: alturaDoCard,$|        if comBarra {|; /^ *listaAtual: listaNatural, tetoDoCard: alturaMaxima) {$/d; s|\.frame(height: teto)|.frame(height: 200)|' "$CV"
caso "ScrollView sob condição que não é o teto" 1 "'ScrollView' fora de um ramo de 'if'/'guard'/'switch' com o teto"

montar
# o ramo sem preview do corpo ganha rolagem sempre: é ramo, mas não do teto
sed -i '' 's|^                lista$|                ScrollView(.vertical) { lista }|' "$CV"
caso "ScrollView no ramo sem preview" 1 "'ScrollView' fora de um ramo de 'if'/'guard'/'switch' com o teto"

montar
# a lista certa, e uma segunda rolagem sem eixo em volta do corpo
sed -i '' 's|^            AskAbasView(ir: |            ScrollView { opcoes }\
            AskAbasView(ir: |' "$CV"
caso "segundo ScrollView solto no corpo" 1 "'ScrollView' fora de um ramo de 'if'/'guard'/'switch' com o teto"

montar
nova_lista <<'EOF'
    @ViewBuilder
    private var lista: some View {
        let teto = AskTeto.daLista(natural: listaNatural, card: alturaDoCard,
                                   listaAtual: listaNatural, tetoDoCard: alturaMaxima)
        if teto == nil {
            opcoes
        } else {
            ScrollView(.vertical) { opcoes }.frame(height: teto ?? 0)
        }
    }

EOF
caso "teto negado, rolagem no else" 0 ""

montar
nova_lista <<'EOF'
    private var lista: AnyView {
        guard let teto = AskTeto.daLista(natural: listaNatural, card: alturaDoCard,
                                         listaAtual: listaNatural, tetoDoCard: alturaMaxima)
        else { return AnyView(opcoes) }
        return AnyView(ScrollView(.vertical) { opcoes }.frame(height: teto))
    }

EOF
caso "rolagem depois de um guard do teto" 0 ""

montar
nova_lista <<'EOF'
    @ViewBuilder
    private var lista: some View {
        if let teto = AskTeto.daLista(natural: listaNatural, card: alturaDoCard,
                                      listaAtual: listaNatural, tetoDoCard: alturaMaxima) {
            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: true) { opcoes }
            }
            .frame(height: teto)
        } else {
            opcoes
        }
    }

EOF
caso "rolagem dentro de um contêiner do ramo" 0 ""

montar
nova_lista <<'EOF'
    private var lista: AnyView {
        guard let ask = askStore.state.active else { return AnyView(opcoes) }
        return AnyView(ScrollView(.vertical) { opcoes }.frame(height: 200))
    }

EOF
caso "rolagem depois de um guard que não é do teto" 1 "'ScrollView' fora de um ramo de 'if'/'guard'/'switch' com o teto"

# --- pendência da etapa 4: o preview embaixo reserva o mínimo da lista
montar
sed -i '' '/let reserva = /d; s| - 150 - reserva))| - 150))|' "$CV"
caso "layoutDoPreview sem reservar a lista" 1 "o layoutDoPreview não desconta o mínimo da lista"

montar
sed -i '' 's|AskTeto.minimoDaLista|96|' "$CV"
caso "mínimo da lista como 96 literal" 0 ""

montar
sed -i '' 's|AskTeto.minimoDaLista|196|' "$CV"
caso "96 como sufixo de outro número" 1 "o layoutDoPreview não desconta o mínimo da lista"

montar
# o 96 existe no arquivo, mas na lista: o preview continua sem reservar nada
sed -i '' '/let reserva = /d; s| - 150 - reserva))| - 150))|; s|\.frame(height: teto)|.frame(height: max(96, teto))|' "$CV"
caso "96 fora do layoutDoPreview" 1 "o layoutDoPreview não desconta o mínimo da lista"

# --- medida da lista
montar
sed -i '' 's|^struct AlturaDaListaDoAskKey: PreferenceKey {|struct OutraChave: PreferenceKey {|' "$CV"
caso "sem a chave da lista" 1 "declara 'struct AlturaDaListaDoAskKey'"

montar
# a lista medida com a chave do card: as duas medidas se misturam
sed -i '' '/^struct AlturaDaListaDoAskKey/,/^}$/d; s|AlturaDaListaDoAskKey|AlturaDoAskKey|' "$CV"
caso "lista medida com a chave do card" 1 "declara 'struct AlturaDaListaDoAskKey'"

montar
sed -i '' 's|Color.clear.preference(key: AlturaDaListaDoAskKey.self, value: p.size.height)|Color.clear|' "$CV"
caso "chave da lista sem ninguém publicar" 1 "publica 'preference(key: AlturaDaListaDoAskKey.self'"

montar
sed -i '' '/onPreferenceChange(AlturaDaListaDoAskKey.self)/d' "$CV"
caso "chave da lista sem ninguém ler" 1 "lê 'onPreferenceChange(AlturaDaListaDoAskKey.self'"

# --- maxHeight: .infinity
montar
sed -i '' 's|\.frame(height: teto)|.frame(maxHeight: .infinity)|' "$CV"
caso "maxHeight infinito no card" 1 "$PASTA/AskCardView.swift usa 'maxHeight: .infinity'"

montar
sed -i '' 's|^            \.fixedSize()$|            .fixedSize()\
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)|' "$PV"
caso "maxHeight infinito na peça do preview" 1 "$PASTA/AskPreviewView.swift usa 'maxHeight: .infinity'"

montar
sed -i '' 's|^            \.fixedSize()$|            .fixedSize()\
            // sem maxHeight: .infinity: trava a auto-medição\
            .frame(maxWidth: .infinity, alignment: .leading)|' "$PV"
caso "maxWidth infinito e maxHeight só em comentário" 0 ""

# --- NotchView
montar
sed -i '' 's|^        AskCardView(vm: vm, askStore: askStore,$|        AskCardView(vm: vm, askStore: askStore)|; /alturaMaxima: AskTeto.doCard(/d' "$NV"
caso "NotchView sem passar o teto" 1 "não passa 'alturaMaxima:' ao criar o AskCardView"

montar
# o rótulo aparece na chamada de outro card, não na do AskCardView
sed -i '' 's|^        AskCardView(vm: vm, askStore: askStore,$|        AskCardView(vm: vm, askStore: askStore)|; s|^                    alturaMaxima: AskTeto.doCard(disponivel: vm.availableSize.height, topo: topInset))$|        OutroCard(alturaMaxima: AskTeto.doCard(disponivel: vm.availableSize.height, topo: topInset))|' "$NV"
caso "alturaMaxima na chamada de outro card" 1 "não passa 'alturaMaxima:' ao criar o AskCardView"

montar
sed -i '' 's|alturaMaxima: AskTeto.doCard(disponivel: vm.availableSize.height, topo: topInset))|alturaMaxima: 0.6 * vm.availableSize.height - (topInset + 18))|' "$NV"
caso "teto do card por conta solta" 1 "Knobler/NotchView.swift sem 'AskTeto.doCard('"

montar
# chamada numa linha só, com o teto guardado antes
sed -i '' 's|^        AskCardView(vm: vm, askStore: askStore,$|        let teto = AskTeto.doCard(disponivel: vm.availableSize.height, topo: topInset)\
        return AskCardView(vm: vm, askStore: askStore, alturaMaxima: teto)|; /^                    alturaMaxima: AskTeto.doCard(/d' "$NV"
caso "teto guardado e chamada numa linha" 0 ""

# --- gesto de lado
montar
sed -i '' '/if vm.mode == .question/d' "$KA"
caso "handleScroll sem a pergunta" 1 "o handleScroll não trata '.question'"

montar
# o caso existe no arquivo, fora do handleScroll (é como está hoje)
sed -i '' '/if vm.mode == .question/d' "$KA"
echo 'let modo: Modo = perguntaAtiva ? .question : vm.mode' >> "$KA"
caso ".question só fora do handleScroll" 1 "o handleScroll não trata '.question'"

montar
sed -i '' 's|^    if vm.mode == .question { return event }$|    // if vm.mode == .question { return event }|' "$KA"
caso ".question só em comentário" 1 "o handleScroll não trata '.question'"

montar
sed -i '' '/if vm.mode == .question/d; s|^    let expanded = vm.mode == .music$|    let expanded = vm.mode == .music  // .question entra depois|' "$KA"
caso ".question só em comentário de fim de linha" 1 "o handleScroll não trata '.question'"

montar
sed -i '' 's|if vm.mode == .question { return event }|if vm.questionIsActive() { return event }|' "$KA"
caso "outro nome que começa com question" 1 "o handleScroll não trata '.question'"

montar
sed -i '' 's|^func handleScroll(|func tratarRolagem(|' "$KA"
caso "app sem handleScroll" 1 "sem 'func handleScroll('"

montar
sed -i '' 's|^    if vm.mode == .question { return event }$|    guard vm.mode != .question else { return event }|' "$KA"
caso "saída cedo por guard" 0 ""

# --- harness
for v in $CENARIOS_DE_TETO; do
  montar
  sed -i '' "s|Scenario(name: \"$v\"|Scenario(name: \"x-$v\"|" "$MN"
  caso "harness sem $v" 1 "sem o cenário \"$v\""
done

montar
sed -i '' 's|^        vm.availableSize.height = 520$|        vm.availableSize.height = 900|' "$MN"
caso "ask-longo na tela alta" 1 "o cenário \"ask-longo\" não fixa a altura disponível em 520"

montar
sed -i '' '/^        vm.availableSize.height = 520$/d' "$MN"
caso "ask-longo sem fixar a altura (a do vizinho não conta)" 1 "o cenário \"ask-longo\" não fixa a altura disponível em 520"

montar
sed -i '' 's|vm.availableSize = CGSize(width: 900, height: 520)|vm.availableSize = CGSize(width: 900, height: 900)|' "$MN"
caso "ask-preview-alto na tela alta" 1 "o cenário \"ask-preview-alto\" não fixa a altura disponível em 520"

montar
sed -i '' 's|vm.availableSize = CGSize(width: 900, height: 520)|vm.availableSize = CGSize(width: 520, height: 1520)|' "$MN"
caso "520 na largura e como sufixo" 1 "o cenário \"ask-preview-alto\" não fixa a altura disponível em 520"

montar
sed -i '' 's|precondition(AskTeto.doCard(disponivel: 520, topo: 32) < 358)|precondition(262 < 358)|' "$MN"
caso "ask-longo sem a conta do teto" 1 "o cenário \"ask-longo\" sem 'AskTeto.doCard('"

montar
# a conta existe, mas no bloco de outro cenário
sed -i '' 's|precondition(AskTeto.doCard(disponivel: 520, topo: 32) < 358)|precondition(262 < 358)|; s|^        precondition((layout?.quadro.height ?? .infinity) <= 218)$|        precondition((layout?.quadro.height ?? .infinity) <= 218 \&\& AskTeto.doCard(disponivel: 520, topo: 32) > 0)|' "$MN"
caso "conta do teto no cenário vizinho" 1 "o cenário \"ask-longo\" sem 'AskTeto.doCard('"

montar
sed -i '' 's|Guardar pela posição|Outra opção|' "$MN"
caso "harness sem a pergunta longa" 1 "sem a pergunta longa do mockup"

montar
sed -i '' 's|Scenario(name: "ask-preview-alto", realNotch: true, frameHeight: 620, frameWidth: 900)|Scenario(name: "ask-preview-alto", realNotch: true, frameHeight: 620)|' "$MN"
caso "ask-preview-alto sem frameWidth" 1 "o cenário \"ask-preview-alto\" sem 'frameWidth: 900'"

montar
sed -i '' 's|^        askStore.send(.setHighlight(0))$|        askStore.send(.setHighlight(1))|' "$MN"
caso "ask-preview-alto com destaque na segunda" 1 "o cenário \"ask-preview-alto\" sem '.setHighlight(0)'"

montar
sed -i '' '/quadro.height/d' "$MN"
caso "ask-preview-alto sem a conta da altura" 1 "o cenário \"ask-preview-alto\" sem a conta de 'quadro.height'"

montar
sed -i '' 's|AskCardView.layoutDoPreview(question: alta, disponivel: vm.availableSize, topo: 32)|layoutGuardado|' "$MN"
caso "ask-preview-alto sem conferir o layout" 1 "o cenário \"ask-preview-alto\" não chama 'layoutDoPreview('"

montar
# com três cenários de preview, a contagem da etapa 4 (duas chamadas) não vê
# este buraco: quem pega é a conferência por bloco
sed -i '' 's|AskCardView.layoutDoPreview(question: larga, disponivel: vm.availableSize, topo: 32)|layoutGuardado|' "$MN"
caso "ask-preview-largo sem conferir o layout, com três cenários" 1 "o cenário \"ask-preview-largo\" não chama 'layoutDoPreview('"

# === etapa 6: teclado no card ===

# --- a função pura das teclas
montar
rm "$TC"
caso "AskTeclado.swift ausente" 1 "$PASTA/AskTeclado.swift não existe"

montar
sed -i '' 's|^enum AskTeclado {|enum TeclasDoAsk {|' "$TC"
caso "AskTeclado.swift sem o enum" 1 "não declara 'enum AskTeclado'"

montar
sed -i '' 's|^import Foundation$|import Foundation\
import AppKit|' "$TC"
caso "teclas com AppKit" 1 "importa mais que o Foundation"

montar
sed -i '' 's|^import Foundation$|import Foundation\
// import AppKit|' "$TC"
caso "AppKit só em comentário" 0 ""

# o AskTeclado.swift do repo falso cita `.choose(index:` e `.goTo(page:`: os
# casos "clique sem choose" e "aba sem goTo" lá em cima só reprovam porque ele
# não conta como view

# --- fontes do snapshot: só quando alguma fonte usa as teclas
montar
echo 'let tecla = AskTecla(codigo: 36, caracteres: "\r")' >> "$CV"
caso "view usa as teclas e as fontes não as listam" 1 "tools/notchview-fontes.txt sem '$PASTA/AskTeclado.swift'"

montar
echo 'let tecla = AskTecla(codigo: 36, caracteres: "\r")' >> "$CV"
echo "$PASTA/AskTeclado.swift" >> "$FT"
caso "view usa as teclas e as fontes as listam" 0 ""

montar
echo 'precondition(AskTeclado.comando(tecla, campo: false, estado: askStore.state) == .focarCampo)' >> "$MN"
caso "harness usa as teclas e as fontes não as listam" 1 "tools/notchview-fontes.txt sem '$PASTA/AskTeclado.swift'"

montar
# outro nome que só começa igual não é uso
echo 'let x = AskTecladoVirtual()' >> "$CV"
caso "nome que só começa com AskTeclado" 0 ""

# --- registro no check.sh
montar
sed -i '' '/asktecladocheck/d' "$CK"
caso "check.sh sem o asktecladocheck" 1 "tools/check.sh sem a linha 'swift_teste tools/asktecladocheck.swift"

montar
sed -i '' 's|^swift_teste tools/asktecladocheck|# swift_teste tools/asktecladocheck|' "$CK"
caso "asktecladocheck comentado no check.sh" 1 "tools/check.sh sem a linha 'swift_teste tools/asktecladocheck.swift"

montar
sed -i '' 's| Knobler/AskCard/AskTeclado.swift$||' "$CK"
caso "asktecladocheck sem compilar o AskTeclado.swift" 1 "tools/check.sh sem a linha 'swift_teste tools/asktecladocheck.swift"

montar
rm "$CK"
caso "repo sem check.sh" 1 "tools/check.sh não existe"

# --- view model
montar
rm "$VM"
caso "repo sem a view model" 1 "Knobler/NotchViewModel.swift não existe"

montar
sed -i '' 's|^    @Published var tecladoNaPergunta = false$|    var tecladoNaPergunta = false|' "$VM"
caso "posse do teclado sem @Published" 1 "sem '@Published var tecladoNaPergunta'"

montar
sed -i '' 's|^    @Published var tecladoNaPergunta = false$|    // @Published var tecladoNaPergunta = false|' "$VM"
caso "posse do teclado só em comentário" 1 "sem '@Published var tecladoNaPergunta'"

montar
sed -i '' '/@Published var campoDaPerguntaFocado/d' "$VM"
caso "view model sem o foco do campo" 1 "sem '@Published var campoDaPerguntaFocado'"

montar
sed -i '' '/var perguntaDoClaudeAtiva:/d' "$VM"
caso "view model sem perguntaDoClaudeAtiva" 1 "sem 'var perguntaDoClaudeAtiva:'"

montar
sed -i '' '/var aoMudarTecladoDaPergunta:/d' "$VM"
caso "view model sem o aviso da posse" 1 "sem 'var aoMudarTecladoDaPergunta:'"

montar
sed -i '' 's|func darTecladoAPergunta(|func tomarTeclado(|' "$VM"
caso "view model sem darTecladoAPergunta" 1 "sem 'func darTecladoAPergunta('"

montar
sed -i '' '/aoMudarTecladoDaPergunta?(liga)/d' "$VM"
caso "darTecladoAPergunta sem avisar o painel" 1 "o darTecladoAPergunta não chama 'aoMudarTecladoDaPergunta'"

montar
sed -i '' '/guard tecladoNaPergunta != liga else { return }/d' "$VM"
caso "darTecladoAPergunta avisa sem mudança" 1 "o darTecladoAPergunta não compara o valor novo com o atual"

montar
sed -i '' 's|guard tecladoNaPergunta != liga else { return }|if tecladoNaPergunta == liga { return }|' "$VM"
caso "comparação por == com saída cedo" 0 ""

RAMO='if mode == .question, perguntaDoClaudeAtiva() { darTecladoAPergunta(!tecladoNaPergunta); return }'

montar
# como está hoje: o atalho só conhece o card de música
sed -i '' "/$RAMO/d" "$VM"
caso "alternarPeloTeclado sem o ramo da pergunta" 1 "o alternarPeloTeclado não consulta 'perguntaDoClaudeAtiva'"

montar
sed -i '' "s|^        $RAMO\$|        // $RAMO|" "$VM"
caso "ramo da pergunta só em comentário" 1 "o alternarPeloTeclado não chama 'darTecladoAPergunta('"

montar
sed -i '' "/$RAMO/d; s|^        abertoPorTeclado = true\$|        abertoPorTeclado = true\\
        $RAMO|" "$VM"
caso "ramo da pergunta depois de armar o card de música" 1 "o ramo da pergunta vem depois de 'setExpandedDirect(' ou 'abertoPorTeclado = true'"

montar
sed -i '' "/$RAMO/d; s|^        if expanded \&\& abertoPorTeclado { setExpandedDirect(false); return }\$|&\\
        $RAMO|" "$VM"
caso "ramo da pergunta depois de fechar o card de música" 1 "o ramo da pergunta vem depois de 'setExpandedDirect(' ou 'abertoPorTeclado = true'"

montar
sed -i '' 's|if mode == .question, perguntaDoClaudeAtiva() {|if perguntaDoClaudeAtiva() {|' "$VM"
caso "ramo da pergunta sem olhar o modo" 1 "o alternarPeloTeclado não olha '.question'"

montar
# o card do Codex divide o modo .question: sem a consulta ele ganharia a posse
sed -i '' 's|if mode == .question, perguntaDoClaudeAtiva() {|if mode == .question {|' "$VM"
caso "ramo da pergunta vale para o card do Codex" 1 "o alternarPeloTeclado não consulta 'perguntaDoClaudeAtiva'"

montar
sed -i '' 's|darTecladoAPergunta(!tecladoNaPergunta); return }|tecladoNaPergunta.toggle(); return }|' "$VM"
caso "ramo da pergunta grava a flag sem avisar" 1 "o alternarPeloTeclado não chama 'darTecladoAPergunta('"

montar
sed -i '' "s|^        $RAMO\$|        guard !(mode == .question \&\& perguntaDoClaudeAtiva()) else {\\
            darTecladoAPergunta(!tecladoNaPergunta)\\
            return\\
        }|" "$VM"
caso "ramo da pergunta por guard, em várias linhas" 0 ""

# --- vigia de teclas
montar
sed -i '' 's|switch AskTeclado.comando(tecla, campo: campo, estado: askStore.state) {|switch teclaNaMao(tecla, campo: campo) {|' "$KA"
caso "vigia com as regras na mão" 1 "o vigia de teclas não chama 'AskTeclado.comando('"

montar
# a função é chamada no arquivo, mas não de dentro do vigia
sed -i '' 's|switch AskTeclado.comando(tecla, campo: campo, estado: askStore.state) {|switch teclaNaMao(tecla, campo: campo) {|' "$KA"
echo 'let solto = AskTeclado.comando(tecla, campo: false, estado: estado)' >> "$KA"
caso "AskTeclado.comando só fora do vigia" 1 "o vigia de teclas não chama 'AskTeclado.comando('"

montar
sed -i '' 's|^            switch AskTeclado.comando(tecla, campo: campo, estado: askStore.state) {$|            // switch AskTeclado.comando(tecla, campo: campo, estado: askStore.state) {\
            switch teclaNaMao(tecla, campo: campo) {|' "$KA"
caso "AskTeclado.comando só em comentário" 1 "o vigia de teclas não chama 'AskTeclado.comando('"

montar
# o guard antigo sobe para antes do ramo da pergunta: devolve o evento primeiro
sed -i '' '/^        guard let window = NSApp.keyWindow/d; /^              vm.abertoPorTeclado, vm.mode != .question/d; s|^        if let window = NSApp.keyWindow as? NotchWindow, let vm = self?.vmDa(window),$|        guard let janela = NSApp.keyWindow as? NotchWindow, let dona = self?.vmDa(janela),\
              dona.abertoPorTeclado, dona.mode != .question, !(janela.firstResponder is NSText) else { return event }\
&|' "$KA"
caso "ramo da pergunta depois do guard antigo" 1 "'AskTeclado.comando(' vem depois do guard do card aberto pelo atalho"

montar
# o `.question` do ramo novo, que vem antes, não conta para o guard antigo
sed -i '' 's|vm.abertoPorTeclado, vm.mode != .question, |vm.abertoPorTeclado, |' "$KA"
caso "guard antigo sem o modo" 1 "o guard do card aberto pelo atalho não exige modo diferente de '.question'"

montar
sed -i '' 's|^              vm.abertoPorTeclado, vm.mode != .question, \(.*\)$|              vm.abertoPorTeclado, \1\
        guard vm.mode != .question else { return event }|' "$KA"
caso "modo num segundo guard, antes do switch" 0 ""

montar
# o modo só é olhado depois que ← já mexeu no card de música
sed -i '' 's|vm.abertoPorTeclado, vm.mode != .question, |vm.abertoPorTeclado, |; s|^        case kVK_Escape: vm.setExpandedDirect(false)$|        case kVK_Escape: if vm.mode != .question { vm.setExpandedDirect(false) }|' "$KA"
caso "modo só dentro do switch antigo" 1 "o guard do card aberto pelo atalho não exige modo diferente de '.question'"

montar
sed -i '' '/^        guard let window = NSApp.keyWindow/d; /^              vm.abertoPorTeclado, vm.mode != .question/d' "$KA"
caso "vigia sem o guard antigo" 1 "o vigia de teclas perdeu o guard do card aberto pelo atalho"

montar
sed -i '' 's|addLocalMonitorForEvents(matching: .keyDown)|addLocalMonitorForEvents(matching: .scrollWheel)|' "$KA"
caso "app sem vigia de teclas" 1 "sem o vigia de teclas"

for uso in "${COMANDOS[@]}"; do
  texto="${uso%%|*}"
  montar
  sed -i '' "/case [.]$texto?:/d" "$KA"
  caso "vigia sem tratar .$texto" 1 "não trata o comando '.$texto'"
done

montar
# .cancelActive não é o comando .cancelar
sed -i '' 's|case .cancelar?: askStore.send(.cancelActive)|default: askStore.send(.cancelActive)|' "$KA"
caso "cancelActive não conta como .cancelar" 1 "não trata o comando '.cancelar'"

# --- herança da chave
MAKEKEY='if active, viewModel?.abertoPorTeclado == true, viewModel?.mode != .question { panel?.makeKey() }'

montar
# como está hoje
sed -i '' "s|$MAKEKEY|if active, viewModel?.abertoPorTeclado == true { panel?.makeKey() }|" "$KA"
caso "makeKey automático sem olhar o modo" 1 "o makeKey do onKeyboardEligibilityChanged não exige modo diferente de '.question'"

montar
sed -i '' "s|^            $MAKEKEY\$|            guard viewModel?.mode != .question else { return }\\
            if active, viewModel?.abertoPorTeclado == true { panel?.makeKey() }|" "$KA"
caso "modo num guard antes do makeKey" 0 ""

montar
sed -i '' "s|^            $MAKEKEY\$|            if active, viewModel?.abertoPorTeclado == true { panel?.makeKey() }\\
            if viewModel?.mode == .question { registrar() }|" "$KA"
caso "modo olhado só depois do makeKey" 1 "o makeKey do onKeyboardEligibilityChanged não exige modo diferente de '.question'"

montar
sed -i '' 's|^        onKeyboardEligibilityChanged: { \[weak panel, weak viewModel\] active in$|        onKeyboardEligibilityChanged: nil|; /panel?.allowsKeyboard = active/,/^        }))$/d' "$KA"
caso "app sem o bloco de elegibilidade" 1 "sem o bloco 'onKeyboardEligibilityChanged: {'"

# --- clicar em outro app solta
montar
sed -i '' '/^        viewModel.darTecladoAPergunta(false)$/d' "$KA"
caso "aoPerderTeclado sem soltar a pergunta" 1 "o aoPerderTeclado não chama 'darTecladoAPergunta(false)'"

montar
sed -i '' 's|^        viewModel.darTecladoAPergunta(false)$|        // viewModel.darTecladoAPergunta(false)|' "$KA"
caso "soltar só em comentário" 1 "o aoPerderTeclado não chama 'darTecladoAPergunta(false)'"

montar
# com pergunta na tela o modo não é .music: o guard sai antes da chamada
sed -i '' '/^        viewModel.darTecladoAPergunta(false)$/d; s|^        guard viewModel.abertoPorTeclado, viewModel.mode == .music else { return }$|&\
        viewModel.darTecladoAPergunta(false)|' "$KA"
caso "soltar depois do guard do card de música" 1 "'darTecladoAPergunta(false)' vem depois do guard do card de música"

montar
sed -i '' '/^        viewModel.darTecladoAPergunta(false)$/d; s|^        guard let viewModel else { return }$|        guard let viewModel, viewModel.abertoPorTeclado,\
              viewModel.mode == .music else { return }\
        viewModel.darTecladoAPergunta(false)|; /^        guard viewModel.abertoPorTeclado, viewModel.mode == .music else { return }$/d' "$KA"
caso "soltar depois do guard antigo, quebrado em duas linhas" 1 "'darTecladoAPergunta(false)' vem depois do guard do card de música"

montar
sed -i '' '/^        viewModel.darTecladoAPergunta(false)$/d; s|^        guard viewModel.abertoPorTeclado, viewModel.mode == .music else { return }$|        if viewModel.abertoPorTeclado, viewModel.mode == .music { viewModel.setExpandedDirect(false) }\
        viewModel.darTecladoAPergunta(false)|; /^        viewModel.setExpandedDirect(false)$/d' "$KA"
caso "soltar depois de um if do card de música" 0 ""

montar
sed -i '' 's|^    panel.aoPerderTeclado = { \[weak viewModel\] in$|    panel.aoPerderFoco = { [weak viewModel] in|' "$KA"
caso "app sem aoPerderTeclado" 1 "não atribui 'aoPerderTeclado = {'"

# --- quem é a pergunta do Claude
montar
sed -i '' '/viewModel.perguntaDoClaudeAtiva = /d' "$KA"
caso "app sem atribuir perguntaDoClaudeAtiva" 1 "não atribui 'perguntaDoClaudeAtiva = {'"

montar
sed -i '' 's|^    viewModel.perguntaDoClaudeAtiva = .*$|    viewModel.perguntaDoClaudeAtiva = { [weak askStore, weak agentRequestStore] in\
        askStore?.state.active != nil \|\| agentRequestStore?.state.active != nil\
    }|' "$KA"
caso "perguntaDoClaudeAtiva conta o card do Codex" 1 "'perguntaDoClaudeAtiva' cita o 'agentRequestStore'"

montar
sed -i '' 's|^    viewModel.perguntaDoClaudeAtiva = .*$|    viewModel.perguntaDoClaudeAtiva = { [weak viewModel] in viewModel?.questionIsActive() == true }|' "$KA"
caso "perguntaDoClaudeAtiva pelo questionIsActive" 1 "'perguntaDoClaudeAtiva' não lê 'askStore.state.active'"

montar
sed -i '' 's|^    viewModel.perguntaDoClaudeAtiva = .*$|    viewModel.perguntaDoClaudeAtiva = {\
        askStore.state.active != nil\
    }|' "$KA"
caso "perguntaDoClaudeAtiva em três linhas, sem weak" 0 ""

# --- o painel segue a posse
montar
sed -i '' 's|viewModel.aoMudarTecladoDaPergunta = {|viewModel.aoMudarOutraCoisa = {|' "$KA"
caso "app sem atribuir o aviso da posse" 1 "não atribui 'aoMudarTecladoDaPergunta = {'"

montar
# o makeKey do bloco de elegibilidade não conta
sed -i '' '/^            panel?.makeKey()$/d' "$KA"
caso "ganhar o teclado sem makeKey" 1 "o aoMudarTecladoDaPergunta sem 'makeKey('"

montar
# o resignKey do bloco de elegibilidade não conta
sed -i '' '/^            if panel?.isKeyWindow == true { panel?.resignKey() }$/d' "$KA"
caso "soltar o teclado sem resignKey" 1 "o aoMudarTecladoDaPergunta sem 'resignKey('"

montar
sed -i '' '/askStore.send(.setHighlight(0))/d; /askStore.send(.setHighlight(nil))/d' "$KA"
caso "posse sem mexer no destaque" 1 "o aoMudarTecladoDaPergunta sem '.setHighlight('"

# --- a posse cai quando a pergunta ativa muda
montar
sed -i '' '/forEach { \$0.viewModel.darTecladoAPergunta(false) }/d' "$KA"
caso "posse não cai com a troca de pergunta" 1 "nenhum 'darTecladoAPergunta(false)' fora do vigia de teclas e do aoPerderTeclado"

montar
sed -i '' '/forEach { \$0.viewModel.darTecladoAPergunta(false) }/d' "$KA"
echo '// .onChange(of: askStore.state.active?.id) { vm.darTecladoAPergunta(false) }' >> "$NV"
caso "queda da posse só em comentário" 1 "nenhum 'darTecladoAPergunta(false)' fora do vigia de teclas e do aoPerderTeclado"

montar
sed -i '' '/forEach { \$0.viewModel.darTecladoAPergunta(false) }/d' "$KA"
echo 'let cai = { vm.darTecladoAPergunta(false) }' >> "$NV"
caso "queda da posse no NotchView" 0 ""

# --- Esc não cancela mais
montar
# como está hoje
sed -i '' 's|^        .onPreferenceChange(AlturaDaListaDoAskKey.self) { listaNatural = $0 }$|&\
        .onExitCommand { askStore.send(.cancelActive) }|' "$CV"
caso "Esc do card ainda cancela" 1 "$PASTA/AskCardView.swift: um '.onExitCommand' ainda envia '.cancelActive'"

montar
sed -i '' 's|^        TextField("Outra resposta…", text: .constant("")).opacity(AskEstilo.linha)$|&\
            .onExitCommand {\
                askStore.send(.cancelActive)\
            }|' "$RD"
caso "Esc do rodapé cancela, em três linhas" 1 "$PASTA/AskRodapeView.swift: um '.onExitCommand' ainda envia '.cancelActive'"

montar
sed -i '' 's|^        .onPreferenceChange(AlturaDaListaDoAskKey.self) { listaNatural = $0 }$|&\
        // .onExitCommand { askStore.send(.cancelActive) }|' "$CV"
caso "Esc que cancela só em comentário" 0 ""

montar
# o ✕ logo abaixo continua enviando .cancelActive: não é do onExitCommand
sed -i '' 's|^            Button { askStore.send(.cancelActive) } label: { Text("x") }$|            Text("y").onExitCommand { vm.campoDaPerguntaFocado = false }\
&|' "$CV"
caso "Esc do campo só devolve o cursor" 0 ""

montar
sed -i '' 's|^            Button { askStore.send(.cancelActive) } label: { Text("x") }$|            Text("y").onExitCommand(perform: voltarALista)\
&|' "$CV"
caso "onExitCommand(perform:) seguido do ✕" 0 ""

# --- as peças seguem a posse
montar
# como está hoje
sed -i '' 's|AskLegenda.itens(teclado: vm.tecladoNaPergunta, campo: textFocused|AskLegenda.itens(teclado: false, campo: textFocused|' "$CV"
caso "legenda com teclado fixo em false" 1 "$PASTA/AskCardView.swift passa 'teclado:' fixo em false ou true"

montar
sed -i '' 's|AskLegenda.itens(teclado: vm.tecladoNaPergunta, campo: textFocused|AskLegenda.itens(teclado: true, campo: textFocused|' "$CV"
caso "legenda com teclado fixo em true" 1 "$PASTA/AskCardView.swift passa 'teclado:' fixo em false ou true"

montar
# como está hoje
sed -i '' 's|^                         teclado: vm.tecladoNaPergunta,$|                         teclado: false,|' "$CV"
caso "opção com teclado fixo em false" 1 "$PASTA/AskCardView.swift passa 'teclado:' fixo em false ou true"

montar
sed -i '' 's|^struct AskOpcaoView: View {$|struct AskOpcaoView: View {\
    var teclado: Bool = false\
    // antes: teclado: false|' "$OP"
caso "parâmetro com padrão e literal só em comentário" 0 ""

montar
sed -i '' 's|vm.tecladoNaPergunta|comTeclado|g' "$CV"
caso "card sem ler a posse da view model" 1 "$PASTA/AskCardView.swift não usa 'vm.tecladoNaPergunta'"

montar
sed -i '' '/vm.campoDaPerguntaFocado/d' "$CV"
caso "card sem o foco da view model" 1 "$PASTA/AskCardView.swift não usa 'vm.campoDaPerguntaFocado'"

montar
# lê (Tab do vigia chega), mas o clique no campo não volta para a view model
sed -i '' '/^            vm.campoDaPerguntaFocado = textFocused$/d' "$CV"
caso "card não grava o foco de volta" 1 "$PASTA/AskCardView.swift não grava 'vm.campoDaPerguntaFocado ='"

montar
sed -i '' 's|^            vm.campoDaPerguntaFocado = textFocused$|            if vm.campoDaPerguntaFocado == textFocused { return }|' "$CV"
caso "comparação não é gravação" 1 "$PASTA/AskCardView.swift não grava 'vm.campoDaPerguntaFocado ='"

montar
sed -i '' '/if textFocused { vm.darTecladoAPergunta(true) }/d' "$CV"
caso "clique no campo não dá o teclado" 1 "$PASTA/AskCardView.swift sem 'darTecladoAPergunta(true)'"

montar
sed -i '' '/AskSeloView(texto: "⇥")/d' "$RD"
caso "rodapé sem o selo do Tab" 1 "$PASTA/AskRodapeView.swift sem o selo \"⇥\""

montar
sed -i '' 's|^        if selo { AskSeloView(texto: "⇥") }$|        // if selo { AskSeloView(texto: "⇥") }|' "$RD"
caso "selo do Tab só em comentário" 1 "$PASTA/AskRodapeView.swift sem o selo \"⇥\""

# --- comentário do preview de link
montar
# como está hoje
sed -i '' 's|como na nota rápida$|como na nota rápida e no card de pergunta|' "$LK"
caso "comentário do link ainda cita o card de pergunta" 1 "Knobler/LinkPreviewView.swift ainda diz"

montar
sed -i '' 's|como na nota rápida$|como na nota rápida (no card de pergunta o Esc solta o teclado)|' "$LK"
caso "comentário do link cita o card pela diferença" 0 ""

montar
rm "$LK"
caso "repo sem o preview de link" 0 ""

# --- harness
for v in $CENARIOS_DE_TECLADO; do
  montar
  sed -i '' "s|Scenario(name: \"$v\"|Scenario(name: \"x-$v\"|" "$MN"
  caso "harness sem $v" 1 "sem o cenário \"$v\""
done

montar
# a flag ligada no cenário vizinho não conta
sed -i '' '/Scenario(name: "ask-teclado"/,/^    },$/{/vm.tecladoNaPergunta = true/d;}' "$MN"
caso "ask-teclado sem a posse" 1 "o cenário \"ask-teclado\" não liga 'vm.tecladoNaPergunta = true'"

montar
sed -i '' '/Scenario(name: "ask-texto"/,/^    },$/{/vm.tecladoNaPergunta = true/d;}' "$MN"
caso "ask-texto sem a posse" 1 "o cenário \"ask-texto\" não liga 'vm.tecladoNaPergunta = true'"

montar
sed -i '' '/Scenario(name: "ask-teclado"/,/^    },$/s|vm.tecladoNaPergunta = true|vm.tecladoNaPergunta = false|' "$MN"
caso "ask-teclado com a posse desligada" 1 "o cenário \"ask-teclado\" não liga 'vm.tecladoNaPergunta = true'"

montar
# o .setHighlight(1) do ask-preview não conta
sed -i '' '/Scenario(name: "ask-teclado"/,/^    },$/s|askStore.send(.setHighlight(1))|askStore.send(.setHighlight(0))|' "$MN"
caso "ask-teclado com destaque na primeira" 1 "o cenário \"ask-teclado\" sem '.setHighlight(1)'"

montar
sed -i '' '/vm.campoDaPerguntaFocado = true/d' "$MN"
caso "ask-texto sem o cursor no campo" 1 "o cenário \"ask-texto\" não liga 'vm.campoDaPerguntaFocado = true'"

montar
sed -i '' 's|vm.campoDaPerguntaFocado = true|vm.campoDaPerguntaFocado = false|' "$MN"
caso "ask-texto com o cursor fora do campo" 1 "o cenário \"ask-texto\" não liga 'vm.campoDaPerguntaFocado = true'"

montar
sed -i '' 's|Atalho, mas só com o notch fechado|Outra resposta qualquer|' "$MN"
caso "ask-texto sem o texto do mockup" 1 "o cenário \"ask-texto\" sem '.setText("

montar
# com o ask-teclado no arquivo, a conferência da etapa 4 (arquivo inteiro) não
# vê este buraco: quem pega é a conferência por bloco
sed -i '' '/Scenario(name: "ask-preview",/,/^    },$/s|askStore.send(.setHighlight(1))|askStore.send(.setHighlight(0))|' "$MN"
caso "ask-preview sem o destaque, com o ask-teclado no arquivo" 1 "o cenário \"ask-preview\" sem '.setHighlight(1)' no próprio bloco"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do askcardcheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "askcardcheck ok"
