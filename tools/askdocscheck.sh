#!/usr/bin/env bash
# Gate da etapa 8 do card de pergunta (docs/vesta/plans/2026-11-18-card-pergunta.md):
# a documentação, a novidade da 0.38.0 e o catálogo de snapshots.
#
# Confere o que quem lê vê:
#   - novidade: Knobler/Novidades/0.38.0.html existe, é só um ou mais
#     `<section class="novidade">` com `<h3>` e `<p>` não vazios (nada fora
#     deles, sem <html>, <head>, <body>, <style> nem <script>) e fala da
#     pergunta; "0.38.0" está em `NovidadesCatalogo.versoes`;
#   - CHANGELOG.md: no bloco `## [0.38.0]` se o release já correu, senão no
#     `## [Unreleased]`, `### Added` tem itens para o teclado no card pelo
#     atalho, abas com volta, o selo "Recomendada", a espera com selo durante
#     a digitação e o preview inteiro; `### Changed` tem Esc soltando o teclado
#     (cancelar é `⌘.` ou ✕), descrições inteiras e o teto de 60% com a lista
#     rolando;
#   - docs/ask.md e Knobler/AskCard/ sem "1/N", "Esc cancela" e "Esc manda";
#     docs/ask.md sem "paginadas" nem "Clique numa opção", com o atalho que dá
#     o teclado ao card, a tabela de teclas (↑ ↓ ← → números ⏎ espaço ⇥ esc
#     ⌘.; esc solta, ⌘. cancela), abas com volta, envio quando acaba a última
#     pendente, preview inteiro, a espera com o selo "Claude perguntou"
#     durante a digitação e o ✕ cancelando; as duas imagens seguem citadas e
#     existem;
#   - .claude/skills/snapshot-ui/SKILL.md: a lista do que não renderiza
#     offscreen não põe mais os ask-* (nem o AskCardView) ali, nenhum trecho
#     diz que ask-simple/ask-multiselect cortam, e um trecho cita a janela
#     real com todos os prefixos que o tools/main.swift manda pra ela
#     (inclusive `ask-`).
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que cada verificação reprova.
#
# Uso: bash tools/askdocscheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

VERSAO="0.38.0"

# unidades <arquivo>: uma linha por unidade de Markdown — título, linha de
# tabela, item de lista (com as continuações) ou parágrafo.
unidades() {
  awk '
    function sai() { if (u != "") print u; u = "" }
    /^[[:space:]]*$/            { sai(); next }
    /^#/                        { sai(); print; next }
    /^\|/                       { sai(); print; next }
    /^([-*]|[0-9]+\.) /         { sai(); u = $0; next }
    /^[[:space:]]+[^[:space:]]/ { l = $0; sub(/^[[:space:]]+/, "", l); u = (u == "" ? l : u " " l); next }
                                { u = (u == "" ? $0 : u " " $0) }
    END                         { sai() }
  ' "$1" 2>/dev/null
}

# trechos <arquivo>: o texto entre dois títulos, numa linha só.
trechos() {
  awk '
    /^#/ { if (t != "") print t; t = ""; next }
         { t = t " " $0 }
    END  { if (t != "") print t }
  ' "$1" 2>/dev/null
}

# itens_cl <CHANGELOG> <bloco>: `<seção>\t<item>` para cada item `- ` do bloco.
itens_cl() {
  awk -v alvo="$2" '
    function sai() { if (u != "" && dentro) print s "\t" u; u = "" }
    /^## /   { sai(); b = $0; sub(/^## \[/, "", b); sub(/\].*$/, "", b); dentro = (b == alvo); s = ""; next }
    /^### /  { sai(); s = $0; next }
    /^- /    { sai(); u = $0; next }
    /^[[:space:]]+[^[:space:]]/ { if (u != "") { l = $0; sub(/^[[:space:]]+/, "", l); u = u " " l }; next }
             { sai() }
    END      { sai() }
  ' "$1" 2>/dev/null
}

# casa <texto> <padrão ERE>…: o texto casa com todos (sem caixa).
casa() {
  local t="$1" p; shift
  for p in "$@"; do printf '%s\n' "$t" | grep -qiE -- "$p" || return 1; done
}

# alguma <linhas> <padrão>…: alguma linha casa com todos os padrões.
alguma() {
  local linhas="$1" l; shift
  while IFS= read -r l; do
    [ -n "$l" ] && casa "$l" "$@" && return 0
  done <<< "$linhas"
  return 1
}

# palavra solta, sem pegar "escolhe" nem "acaba"
ESC='(^|[^[:alpha:]])esc([^[:alpha:]]|$)'
ABA='(^|[^[:alpha:]])abas?([^[:alpha:]]|$)'
CANCELA='cancel'
FECHAR='✕|×'

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local nov="$r/Knobler/Novidades/$VERSAO.html"
  local cat="$r/Knobler/NovidadesCatalogo.swift"
  local cl="$r/CHANGELOG.md"
  local ask="$r/docs/ask.md"
  local skill="$r/.claude/skills/snapshot-ui/SKILL.md"
  local harness="$r/tools/main.swift"
  local f bloco itens add chg u tabela linhas res achado prefixos p trecho lista

  for f in "$cat" "$cl" "$ask" "$skill"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  # --- novidade ---------------------------------------------------------------
  if [ ! -f "$nov" ]; then
    echo "FALHOU: Knobler/Novidades/$VERSAO.html não existe"
    erro=1
  else
    if grep -qiE -- '<(html|head|body|style|script)[[:space:]>]' "$nov"; then
      echo "FALHOU: Knobler/Novidades/$VERSAO.html tem <html>, <head>, <body>, <style> ou <script> — é só o corpo, no formato do 0.37.0.html"
      erro=1
    fi
    perl -0777 -ne '
      s/<!--.*?-->//gs;
      my $t = $_; $t =~ s/^\s+|\s+$//g;
      my ($n, $ok) = (0, 1);
      while ($t =~ s/^<section class="novidade">(.*?)<\/section>\s*//s) {
        $n++;
        my $c = $1;
        for my $tag ("h3", "p") {
          my ($dentro) = $c =~ /<$tag(?:\s[^>]*)?>(.*?)<\/$tag>/s;
          $dentro = "" unless defined $dentro;
          $dentro =~ s/<[^>]*>//g;
          $ok = 0 unless $dentro =~ /\S/;
        }
      }
      exit 2 if $n == 0 || $t ne "";
      exit 3 unless $ok;
      exit 0;
    ' "$nov"
    res=$?
    if [ "$res" -eq 2 ]; then
      echo "FALHOU: Knobler/Novidades/$VERSAO.html não é só <section class=\"novidade\">…</section> (tem texto fora da seção ou nenhuma seção)"
      erro=1
    elif [ "$res" -eq 3 ]; then
      echo "FALHOU: Knobler/Novidades/$VERSAO.html tem seção sem <h3> ou sem <p> com texto"
      erro=1
    elif [ "$res" -ne 0 ]; then
      echo "FALHOU: Knobler/Novidades/$VERSAO.html não pôde ser lido (perl saiu $res)"
      erro=1
    fi
    if ! sed -e 's/<[^>]*>//g' "$nov" | grep -qi -- 'pergunt'; then
      echo "FALHOU: Knobler/Novidades/$VERSAO.html não fala da pergunta do Claude"
      erro=1
    fi
  fi
  if [ -f "$cat" ] && ! grep -E -- 'static let versoes' "$cat" | grep -qF -- "\"$VERSAO\""; then
    echo "FALHOU: NovidadesCatalogo.versoes sem \"$VERSAO\""
    erro=1
  fi

  # --- CHANGELOG.md -----------------------------------------------------------
  if [ -f "$cl" ]; then
    # o release renomeia o [Unreleased] para a versão; os dois valem
    if grep -q "^## \[$VERSAO\]" "$cl"; then bloco="$VERSAO"; else bloco="Unreleased"; fi
    if ! grep -q "^## \[$bloco\]" "$cl"; then
      echo "FALHOU: CHANGELOG.md sem '## [Unreleased]' nem '## [$VERSAO]'"
      erro=1
    else
      itens=$(itens_cl "$cl" "$bloco")
      add=$(printf '%s\n' "$itens" | awk -F'\t' '$1 == "### Added" { print $2 }')
      chg=$(printf '%s\n' "$itens" | awk -F'\t' '$1 == "### Changed" { print $2 }')
      alguma "$add" 'teclado' 'atalho' \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Added sem o teclado no card pelo atalho"; erro=1; }
      alguma "$add" "$ABA" 'volt' \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Added sem as abas com volta"; erro=1; }
      alguma "$add" 'recomendad' \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Added sem o selo \"Recomendada\""; erro=1; }
      alguma "$add" 'digit' 'selo|claude perguntou' \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Added sem a espera com selo durante a digitação"; erro=1; }
      alguma "$add" 'preview' 'inteir' \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Added sem o preview sempre inteiro"; erro=1; }
      alguma "$chg" "$ESC" 'solt' '⌘\.' "$FECHAR" \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Changed sem Esc soltando o teclado (cancelar é ⌘. ou ✕)"; erro=1; }
      alguma "$chg" 'descri' 'inteir' \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Changed sem as descrições sempre inteiras"; erro=1; }
      alguma "$chg" '60[[:space:]]*%' 'rol' \
        || { echo "FALHOU: CHANGELOG.md [$bloco] ### Changed sem o teto de 60% da tela com a lista rolando"; erro=1; }
    fi
  fi

  # --- frases antigas ---------------------------------------------------------
  achado=$(grep -rniE -- '1/N|Esc cancela|Esc manda' "$ask" "$r/Knobler/AskCard" 2>/dev/null | sed "s|^$r/||")
  if [ -n "$achado" ]; then
    printf '%s\n' "$achado" | while IFS= read -r l; do
      echo "FALHOU: frase antiga (1/N, Esc cancela, Esc manda): $l"
    done
    erro=1
  fi

  # --- docs/ask.md ------------------------------------------------------------
  if [ -f "$ask" ]; then
    if grep -qi -- 'paginad' "$ask"; then
      echo "FALHOU: docs/ask.md ainda diz que as perguntas são paginadas"
      erro=1
    fi
    if grep -qi -- 'clique numa opção' "$ask"; then
      echo "FALHOU: docs/ask.md ainda tem 'Clique numa opção'"
      erro=1
    fi
    for f in ask-simple ask-multiselect; do
      if ! grep -qF -- "images/$f.png" "$ask"; then
        echo "FALHOU: docs/ask.md não mostra mais images/$f.png"
        erro=1
      elif [ ! -f "$r/docs/images/$f.png" ]; then
        echo "FALHOU: docs/images/$f.png não existe"
        erro=1
      fi
    done

    u=$(unidades "$ask")
    tabela=$(printf '%s\n' "$u" | grep '^|' | grep -vE '^\|[[:space:]:|-]+$')
    if [ -z "$tabela" ]; then
      echo "FALHOU: docs/ask.md sem a tabela de teclas"
      erro=1
    else
      for p in '↑' '↓' '←' '→' '⌘\.' "$ESC" '⏎|↩|enter|return' '⇥|tab' 'espaço|space|␣'; do
        if ! printf '%s\n' "$tabela" | grep -qiE -- "$p"; then
          echo "FALHOU: tabela de teclas do docs/ask.md sem a tecla /$p/"
          erro=1
        fi
      done
      if ! printf '%s\n' "$tabela" | awk -F'|' '$2 ~ /[1-9]/ { ok = 1 } END { exit !ok }'; then
        echo "FALHOU: tabela de teclas do docs/ask.md sem a linha dos números"
        erro=1
      fi
      linhas=$(printf '%s\n' "$tabela" | awk -F'|' 'tolower($2) ~ /(^|[^a-z])esc([^a-z]|$)/')
      if [ -z "$linhas" ] || ! alguma "$linhas" 'solt'; then
        echo "FALHOU: tabela de teclas do docs/ask.md não diz que esc solta o teclado"
        erro=1
      fi
      linhas=$(printf '%s\n' "$tabela" | awk -F'|' 'index($2, "⌘.")')
      if [ -z "$linhas" ] || ! alguma "$linhas" "$CANCELA"; then
        echo "FALHOU: tabela de teclas do docs/ask.md não diz que ⌘. cancela"
        erro=1
      fi
    fi
    alguma "$u" 'atalho' 'teclado' \
      || { echo "FALHOU: docs/ask.md não diz qual atalho dá o teclado ao card"; erro=1; }
    alguma "$u" "$ABA" 'volt|respondid' \
      || { echo "FALHOU: docs/ask.md não descreve as abas com volta"; erro=1; }
    alguma "$u" 'pendente' 'envi' \
      || { echo "FALHOU: docs/ask.md não diz que a rodada é enviada quando acaba a última pendente"; erro=1; }
    alguma "$u" 'preview' 'inteir' \
      || { echo "FALHOU: docs/ask.md não diz que o preview sai sempre inteiro"; erro=1; }
    alguma "$u" 'claude perguntou' 'digit' \
      || { echo "FALHOU: docs/ask.md não descreve a espera com o selo \"Claude perguntou\" durante a digitação"; erro=1; }
    alguma "$u" "$FECHAR" "$CANCELA" \
      || { echo "FALHOU: docs/ask.md não diz que o ✕ cancela"; erro=1; }
  fi

  # --- .claude/skills/snapshot-ui/SKILL.md -------------------------------------
  if [ -f "$skill" ]; then
    if ! grep -qiE -- '^#+ .*não renderiza' "$skill"; then
      echo "FALHOU: SKILL.md do snapshot-ui sem a seção do que não renderiza offscreen"
      erro=1
    else
      lista=$(awk 'tolower($0) ~ /^#+ .*não renderiza/ { f = 1; next } f && /^#/ { exit } f' "$skill" > "$T/lista.md"
              unidades "$T/lista.md" | grep -E '^([-*]|[0-9]+\.) ')
      # um item pode citar os ask-* só pra mandá-los à janela real
      while IFS= read -r u; do
        if casa "$u" 'ask-|AskCardView' && ! casa "$u" 'janela'; then
          echo "FALHOU: SKILL.md do snapshot-ui ainda lista o card de pergunta (ask-*/AskCardView) entre o que não renderiza: ${u:0:90}"
          erro=1
        fi
      done <<< "$lista"
    fi
    if alguma "$(unidades "$skill")" 'ask-simple|ask-multiselect' 'cort'; then
      echo "FALHOU: SKILL.md do snapshot-ui ainda diz que ask-simple/ask-multiselect cortam"
      erro=1
    fi
    prefixos=$( { awk '/if scenario\.name\.hasPrefix\(/ { f = 1 } f { print } f && /\{[[:space:]]*$/ { exit }' "$harness" 2>/dev/null \
                  | grep -oE 'hasPrefix\("[^"]+"\)' | sed -E 's/hasPrefix\("([^"]+)"\)/\1/'; echo "ask-"; } | sort -u)
    achado=0
    while IFS= read -r trecho; do
      casa "$trecho" 'janela real|janela sintética|NSHostingView|NotchWindow' || continue
      achado=1
      while IFS= read -r p; do
        printf '%s\n' "$trecho" | grep -qF -- "$p" || { achado=0; break; }
      done <<< "$prefixos"
      [ "$achado" -eq 1 ] && break
    done <<< "$(trechos "$skill")"
    if [ "$achado" -ne 1 ]; then
      echo "FALHOU: SKILL.md do snapshot-ui sem um trecho da janela real citando os prefixos que o tools/main.swift manda pra ela: $(printf '%s ' $prefixos)"
      erro=1
    fi
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

R="$T/r"
NOV="$R/Knobler/Novidades/$VERSAO.html"
CAT="$R/Knobler/NovidadesCatalogo.swift"
CL="$R/CHANGELOG.md"
ASK="$R/docs/ask.md"
SK="$R/.claude/skills/snapshot-ui/SKILL.md"
HN="$R/tools/main.swift"

# repo falso com tudo certo; cada caso estraga uma coisa
montar() {
  rm -rf "$R"
  mkdir -p "$R/Knobler/Novidades" "$R/Knobler/AskCard" "$R/docs/images" "$R/tools" \
    "$R/.claude/skills/snapshot-ui"
  : > "$R/docs/images/ask-simple.png"
  : > "$R/docs/images/ask-multiselect.png"
  printf '// esc no campo volta à lista; na lista solta o teclado\n' > "$R/Knobler/AskCard/AskTeclado.swift"
  cat > "$NOV" <<'EOF'
<section class="novidade">
  <h3>Responda o Claude sem tirar a mão do teclado</h3>
  <p>A pergunta do Claude no notch agora tem abas e responde pelo teclado:
     aperte o atalho do notch e use as setas e os números.</p>
</section>
EOF
  cat > "$CAT" <<'EOF'
enum NovidadesCatalogo {
    static let versoes: [String] = ["0.36.0", "0.37.0", "0.38.0"]
}
EOF
  cat > "$CL" <<'EOF'
# Changelog

## [Unreleased]

### Added
- O atalho do notch dá o teclado ao card de pergunta do Claude.
- Várias perguntas viram abas, e dá para voltar a uma já respondida.
- Opção recomendada pelo Claude ganha o selo "Recomendada".
- Se você está digitando no notch, a pergunta espera com o selo "Claude
  perguntou" no topo.
- O preview da opção sai sempre inteiro.

### Changed
- Esc no card solta o teclado em vez de cancelar a pergunta; cancelar é `⌘.`
  ou o ✕.
- As descrições das opções saem sempre inteiras.
- O card para de crescer em 60% da tela e a lista rola.

### Fixed
- Outra coisa.

## [0.37.0] - 2026-11-10

### Changed
- Coisa antiga.
EOF
  cat > "$ASK" <<'EOF'
# Perguntas do Claude Code (Ask)

![Card de pergunta simples](images/ask-simple.png)

![Card de múltipla escolha](images/ask-multiselect.png)

## O que faz

A pergunta aparece no notch sem roubar o teclado.

## Como usar

O atalho do notch (⌃⌥K por padrão) dá o teclado ao card; apertar de novo
solta.

| Tecla | Efeito |
|---|---|
| `↑` `↓` | move o destaque |
| `1`…`9` | escolhe a opção |
| `⏎` | responde |
| `espaço` | marca na múltipla |
| `←` `→` | troca de aba |
| `⇥` | vai ao campo |
| `esc` | solta o teclado; o card fica |
| `⌘.` | cancela a pergunta |

Com várias perguntas o topo vira abas, e dá para voltar a uma aba respondida.
Responder leva à próxima pendente; sem pendente, a rodada é enviada.

O preview da opção sai sempre inteiro.

Se você está digitando no notch, a pergunta espera com o selo "Claude
perguntou" no topo.

O ✕ cancela a pergunta, que volta para o terminal.
EOF
  cat > "$SK" <<'EOF'
# Snapshots

## O que não renderiza offscreen

- `NavigationSplitView` (repro isolado).
- `TextField` — vira o ícone de "proibido".
- `ScrollView` — sai preta.

Os cenários `agenda-`, `lembretes-`, `monitores-`, `whatsapp-` e `ask-` rodam
numa janela real (`NotchWindow` com `NSHostingView`), não no `ImageRenderer`.

## Capturar Ajustes

Tire o screenshot da janela real.
EOF
  cat > "$HN" <<'EOF'
    if scenario.name.hasPrefix("agenda-") || scenario.name.hasPrefix("lembretes-") || scenario.name.hasPrefix("monitores-")
        || scenario.name.hasPrefix("whatsapp-") || scenario.name.hasPrefix("ask-") {
        _ = NSApplication.shared
    }
    if scenario.name.hasPrefix("ask-espera-") {
    }
EOF
}

AUTO=0
# caso <nome> <código esperado> <texto esperado ou vazio> -- monta $R antes
caso() {
  local nome="$1" esperado="$2" texto="$3" saida codigo
  saida=$(verificar "$R" 2>&1); codigo=$?
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

# troca <arquivo> <de> <para>: substituição literal (perl, sem regex)
troca() { DE="$2" PARA="$3" perl -0777 -pi -e 's/\Q$ENV{DE}\E/$ENV{PARA}/g' "$1"; }
# tira <arquivo> <trecho>: apaga as linhas que contêm o trecho
tira() { grep -vF -- "$2" "$1" > "$1.novo"; mv "$1.novo" "$1"; }

montar
caso "tudo certo" 0 ""

montar
troca "$CL" '## [Unreleased]' "## [Unreleased]

## [$VERSAO] - 2026-11-20"
caso "depois do release (bloco virou [$VERSAO])" 0 ""

# novidade
montar
rm "$NOV"
caso "novidade ausente" 1 "$VERSAO.html não existe"

montar
troca "$CAT" ', "0.38.0"' ''
caso "catálogo sem a versão" 1 "NovidadesCatalogo.versoes sem"

montar
printf '<html><body>\n%s\n</body></html>\n' "$(cat "$NOV")" > "$NOV"
caso "novidade com <html>" 1 "tem <html>"

montar
printf '<style>p{color:red}</style>\n' >> "$NOV"
caso "novidade com <style>" 1 "tem <html>, <head>, <body>, <style>"

montar
printf '<p>solto fora da seção</p>\n' >> "$NOV"
caso "texto fora da seção" 1 "não é só <section"

montar
troca "$NOV" '<section class="novidade">' '<div class="novidade">'
troca "$NOV" '</section>' '</div>'
caso "sem section.novidade" 1 "não é só <section"

montar
tira "$NOV" '<h3>'
caso "seção sem h3" 1 "sem <h3> ou sem <p>"

montar
printf '<section class="novidade">\n  <h3>Pergunta</h3>\n</section>\n' > "$NOV"
caso "seção sem p" 1 "sem <h3> ou sem <p>"

montar
printf '<section class="novidade">\n  <h3>Print</h3>\n  <p>Agora copia sozinho.</p>\n</section>\n' > "$NOV"
caso "novidade de outro assunto" 1 "não fala da pergunta"

# CHANGELOG
montar
tira "$CL" 'O atalho do notch dá o teclado'
caso "Added sem teclado pelo atalho" 1 "sem o teclado no card pelo atalho"

montar
troca "$CL" ', e dá para voltar a uma já respondida' ''
caso "Added sem a volta nas abas" 1 "sem as abas com volta"

montar
tira "$CL" 'Recomendada'
caso "Added sem o selo Recomendada" 1 "sem o selo"

montar
tira "$CL" 'Se você está digitando'
tira "$CL" 'perguntou" no topo.'
caso "Added sem a espera com selo" 1 "sem a espera com selo"

montar
troca "$CL" 'O preview da opção sai sempre inteiro.' 'O preview da opção ficou maior.'
caso "Added sem o preview inteiro" 1 "sem o preview sempre inteiro"

montar
troca "$CL" '### Changed
- Esc' '### Fixed
- Esc'
caso "Esc fora de ### Changed" 1 "sem Esc soltando o teclado"

montar
troca "$CL" 'cancelar é `⌘.`
  ou o ✕' 'cancelar é o ✕'
caso "Changed sem ⌘." 1 "sem Esc soltando o teclado"

montar
troca "$CL" 'cancelar é `⌘.`
  ou o ✕' 'cancelar é `⌘.`'
caso "Changed sem ✕" 1 "sem Esc soltando o teclado"

montar
tira "$CL" 'As descrições das opções'
caso "Changed sem descrições inteiras" 1 "sem as descrições sempre inteiras"

montar
troca "$CL" 'para de crescer em 60% da tela e a lista rola' 'ficou mais alto'
caso "Changed sem o teto de 60%" 1 "sem o teto de 60%"

montar
cat > "$CL" <<'EOF'
# Changelog

## [Unreleased]

### Fixed
- Outra coisa.

## [0.37.0] - 2026-11-10

### Added
- O atalho do notch dá o teclado ao card de pergunta do Claude.
- Várias perguntas viram abas, e dá para voltar a uma já respondida.
- Opção recomendada pelo Claude ganha o selo "Recomendada".
- Se você está digitando no notch, a pergunta espera com o selo "Claude perguntou".
- O preview da opção sai sempre inteiro.

### Changed
- Esc no card solta o teclado; cancelar é `⌘.` ou o ✕.
- As descrições das opções saem sempre inteiras.
- O card para de crescer em 60% da tela e a lista rola.
EOF
caso "entradas numa versão antiga" 1 "CHANGELOG.md [Unreleased] ### Added sem o teclado"

# frases antigas
montar
printf 'Perguntas em sequência (paginadas).\n' >> "$ASK"
caso "ask.md com paginadas" 1 "paginadas"

montar
printf -- '- Clique numa opção e confirme.\n' >> "$ASK"
caso "ask.md com Clique numa opção" 1 "Clique numa opção"

montar
printf 'O topo mostra 1/N.\n' >> "$ASK"
caso "ask.md com 1/N" 1 "frase antiga"

montar
printf '// Esc cancela a pergunta\n' >> "$R/Knobler/AskCard/AskTeclado.swift"
caso "AskCard com Esc cancela" 1 "AskTeclado.swift"

montar
printf 'Esc manda a pergunta de volta.\n' >> "$ASK"
caso "ask.md com Esc manda" 1 "frase antiga"

# docs/ask.md
montar
tira "$ASK" '|'
caso "ask.md sem tabela" 1 "sem a tabela de teclas"

montar
tira "$ASK" '`⌘.`'
caso "tabela sem ⌘." 1 "sem a tecla"

montar
tira "$ASK" '`1`…`9`'
caso "tabela sem números" 1 "sem a linha dos números"

montar
troca "$ASK" '| `esc` | solta o teclado; o card fica |' '| `esc` | cancela a pergunta |'
caso "esc cancelando na tabela" 1 "não diz que esc solta"

montar
troca "$ASK" '| `⌘.` | cancela a pergunta |' '| `⌘.` | fecha o card |'
caso "⌘. sem cancelar na tabela" 1 "não diz que ⌘. cancela"

montar
troca "$ASK" 'O atalho do notch (⌃⌥K por padrão) dá o teclado ao card; apertar de novo
solta.' 'O card aparece sozinho.'
caso "ask.md sem o atalho" 1 "qual atalho dá o teclado"

montar
troca "$ASK" ', e dá para voltar a uma aba respondida' ''
caso "ask.md sem volta nas abas" 1 "abas com volta"

montar
troca "$ASK" 'Responder leva à próxima pendente; sem pendente, a rodada é enviada.' 'Responda uma por vez.'
caso "ask.md sem envio na última pendente" 1 "última pendente"

montar
troca "$ASK" 'O preview da opção sai sempre inteiro.' 'A opção pode ter preview.'
caso "ask.md sem preview inteiro" 1 "preview sai sempre inteiro"

montar
troca "$ASK" 'Se você está digitando no notch, a pergunta espera com o selo "Claude
perguntou" no topo.' 'A pergunta aparece na hora.'
caso "ask.md sem a espera" 1 "Claude perguntou"

montar
tira "$ASK" 'O ✕ cancela'
caso "ask.md sem o ✕ cancelando" 1 "✕ cancela"

montar
tira "$ASK" 'images/ask-multiselect.png'
caso "ask.md sem a imagem multiselect" 1 "images/ask-multiselect.png"

# SKILL.md do snapshot-ui
montar
troca "$SK" '- `TextField` — vira o ícone de "proibido".' '- `TextField` — o rodapé do `AskCardView`, por isso `ask-simple.png` e
  `ask-multiselect.png` cortam antes da barra do campo de texto.'
caso "skill com a lista antiga" 1 "ainda lista o card de pergunta"

montar
troca "$SK" '- `TextField` — vira o ícone de "proibido".' '- `TextField` — o rodapé do `AskCardView`.'
caso "skill com AskCardView na lista" 1 "ainda lista o card de pergunta"

montar
printf '\nO `ask-simple.png` corta antes do campo.\n' >> "$SK"
caso "skill dizendo que ask-simple corta" 1 "cortam"

montar
troca "$SK" ' e `ask-` rodam' ' rodam'
caso "skill sem ask- na janela real" 1 "sem um trecho da janela real"

montar
troca "$SK" ' `whatsapp-` e' ''
caso "skill sem um prefixo do harness" 1 "sem um trecho da janela real"

montar
troca "$SK" 'numa janela real (`NotchWindow` com `NSHostingView`), não no `ImageRenderer`' 'à parte'
caso "skill sem a janela real" 1 "sem um trecho da janela real"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do askdocscheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "askdocscheck ok"
