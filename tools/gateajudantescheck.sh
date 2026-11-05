#!/usr/bin/env bash
# Prova a etapa 0 do plano do WhatsApp (docs/vesta/plans/2026-11-04-whatsapp-knobler.md):
#   1. tools/check.sh registra whatsappgatescheck e notchfontescheck no bloco
#      "# --- WhatsApp" por bash_teste, antes de `run semnslog`;
#   2. swift_teste/bash_teste dão ao gate o nome do arquivo de teste, e a falha o cita;
#   3. whatsappgatescheck reprova gate do WhatsApp sem entrada, entrada sem arquivo
#      e gate do WhatsApp fora dos ajudantes (rodado num repo falso);
#   4. notchfontescheck reprova fonte listada e ausente, view do WhatsApp fora da
#      lista e erro de typecheck, mostrando a saída do swiftc (repo falso).
# Nada aqui toca o app nem a ponte: tudo roda em pastas de mktemp.
#
# Uso: bash tools/gateajudantescheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."
RAIZ=$(pwd)

FALHAS=0
falha() { echo "FALHOU: $*"; FALHAS=$((FALHAS + 1)); }

T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

SAIDA=""; CODIGO=0; MOSTRADA=0
roda() { SAIDA=$("$@" 2>&1); CODIGO=$?; MOSTRADA=0; }
# a saída do caso sai uma vez só, na primeira falha dele
mostra() { [ "$MOSTRADA" = 1 ] && return; MOSTRADA=1; printf '%s\n' "$SAIDA" | sed 's/^/    | /'; }
espera_codigo() { # <código> <caso>
  [ "$CODIGO" = "$1" ] || { falha "$2: saiu com $CODIGO, esperado $1"; mostra; }
}
espera_texto() { # <texto> <caso>
  grep -qF -- "$1" <<<"$SAIDA" || { falha "$2: faltou '$1' na saída"; mostra; }
}
espera_linha() { # <regex> <caso>
  grep -qE -- "$1" <<<"$SAIDA" || { falha "$2: nenhuma linha casa /$1/ na saída"; mostra; }
}

# --- 1. Registro no tools/check.sh -----------------------------------------
CHECK=tools/check.sh
ini=$(grep -n '^# --- WhatsApp' "$CHECK" | head -1 | cut -d: -f1)
fim=$(grep -n '^# --- fim WhatsApp ---$' "$CHECK" | head -1 | cut -d: -f1)
semnslog=$(grep -n '^run semnslog' "$CHECK" | head -1 | cut -d: -f1)
integracao=$(grep -n '== gates de integração ==' "$CHECK" | head -1 | cut -d: -f1)
if [ -z "$ini" ] || [ -z "$fim" ]; then
  falha "check.sh sem o bloco '# --- WhatsApp' … '# --- fim WhatsApp ---'"
elif [ "$fim" -le "$ini" ]; then
  falha "check.sh: '# --- fim WhatsApp ---' vem antes de '# --- WhatsApp'"
else
  bloco=$(sed -n "${ini},${fim}p" "$CHECK")
  for g in whatsappgatescheck.sh notchfontescheck.sh; do
    grep -qE "^bash_teste tools/$g\$" <<<"$bloco" \
      || falha "check.sh: bloco do WhatsApp sem a linha 'bash_teste tools/$g'"
  done
  [ -n "$semnslog" ] && [ "$fim" -lt "$semnslog" ] \
    || falha "check.sh: o bloco do WhatsApp tem que vir antes de 'run semnslog'"
  [ -n "$integracao" ] && [ "$fim" -lt "$integracao" ] \
    || falha "check.sh: o bloco do WhatsApp tem que ficar entre os self-checks, antes dos gates de integração"
fi

# --- 2. swift_teste / bash_teste: nome do gate = nome do arquivo ----------
# Cópia do check.sh real com o preâmbulo (run, swift_check e os ajudantes) e o
# resumo do fim, mas com uma lista de gates de brinquedo no meio.
pre=$(awk '/^echo "== self-checks Swift =="/{exit} {print}' "$CHECK")
pos=$(awk '/^for s in /{p=1} p{print}' "$CHECK")
if [ "$pre" = "$(cat "$CHECK")" ] || [ -z "$pos" ]; then
  falha "check.sh mudou de forma: não achei 'echo \"== self-checks Swift ==\"' ou 'for s in' (ajuste este teste)"
else
  A="$T/ajudantes"
  mkdir -p "$A/tools" "$A/Knobler"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$A/tools/ajudzzokcheck.sh"
  printf '#!/usr/bin/env bash\necho marcador-ajudzz-falha\nexit 3\n' > "$A/tools/ajudzzfalhacheck.sh"
  # argumentos extras chegam intactos, inclusive com espaço
  cat > "$A/tools/ajudzzargscheck.sh" <<'EOF'
#!/usr/bin/env bash
[ "$#" = 2 ] && [ "$1" = um ] && [ "$2" = "dois tres" ] || { echo "args errados: $#: $*"; exit 1; }
EOF
  echo 'func ajudzzFonte() -> Int { 42 }' > "$A/Knobler/AjudzzFonte.swift"
  cat > "$A/tools/ajudzzswiftcheck.swift" <<'EOF'
@main struct AjudzzSwiftCheck {
  static func main() { precondition(ajudzzFonte() == 42, "fonte não compilada junto") }
}
EOF
  {
    printf '%s\n' "$pre"
    cat <<'EOF'
echo "== gates de brinquedo =="
bash_teste tools/ajudzzokcheck.sh
bash_teste tools/ajudzzargscheck.sh um "dois tres"
bash_teste tools/ajudzzfalhacheck.sh
swift_teste tools/ajudzzswiftcheck.swift Knobler/AjudzzFonte.swift
EOF
    echo
    printf '%s\n' "$pos"
  } > "$A/tools/check.sh"
  roda bash -c "cd / && bash '$A/tools/check.sh'"
  caso="ajudantes do check.sh"
  espera_codigo 1 "$caso"
  espera_linha '^  ajudzzokcheck +ok$' "$caso (bash_teste que passa)"
  espera_linha '^  ajudzzargscheck +ok$' "$caso (bash_teste repassa os argumentos)"
  espera_linha '^  ajudzzswiftcheck +ok$' "$caso (swift_teste compila as fontes com o teste)"
  espera_linha '^  ajudzzfalhacheck +FALHOU$' "$caso (bash_teste que falha)"
  espera_texto 'marcador-ajudzz-falha' "$caso (saída do gate que falhou aparece)"
  espera_texto '❌ 3 ok, 1 falhou: ajudzzfalhacheck' "$caso (resumo cita o nome do arquivo)"
fi

# --- 3. whatsappgatescheck num repo falso ---------------------------------
GATES=tools/whatsappgatescheck.sh
if [ ! -f "$GATES" ]; then
  falha "$GATES não existe"
else
  # cria um repo falso com o script e o check.sh dado em stdin; ecoa a raiz
  repo_gates() {
    local d; d=$(mktemp -d "$T/gates.XXXXXX")   # roda em $(…): contador não sobreviveria
    mkdir -p "$d/tools" "$d/Knobler"
    cp "$RAIZ/$GATES" "$d/tools/whatsappgatescheck.sh"
    echo 'struct X {}' > "$d/Knobler/X.swift"
    { echo '#!/usr/bin/env bash'; cat; } > "$d/tools/check.sh"
    echo "$d"
  }
  roda_gates() { roda bash -c "cd / && bash '$1/tools/whatsappgatescheck.sh'"; }
  BASE='bash_teste tools/whatsappgatescheck.sh'

  d=$(repo_gates <<<"$BASE"); roda_gates "$d"
  espera_codigo 0 "gates: repo só com o próprio gate registrado"

  d=$(repo_gates <<<"# nada aqui"); roda_gates "$d"
  espera_codigo 1 "gates: o próprio whatsappgatescheck.sh sem entrada"
  espera_texto 'FALHOU: tools/whatsappgatescheck.sh sem entrada no check.sh' "gates: o próprio sem entrada"

  # (a) .swift sem entrada
  d=$(repo_gates <<<"$BASE"); touch "$d/tools/whatsappzzcheck.swift"; roda_gates "$d"
  espera_codigo 1 "gates (a)"
  espera_texto 'FALHOU: tools/whatsappzzcheck.swift sem entrada no check.sh' "gates (a)"

  # (a) citado só num comentário não conta
  d=$(repo_gates <<<"$BASE"$'\n''# swift_teste tools/whatsappzzcheck.swift'); touch "$d/tools/whatsappzzcheck.swift"; roda_gates "$d"
  espera_codigo 1 "gates (a) entrada só em comentário"
  espera_texto 'FALHOU: tools/whatsappzzcheck.swift sem entrada no check.sh' "gates (a) entrada só em comentário"

  # (a) .swift registrado com o ajudante de bash não conta
  d=$(repo_gates <<<"$BASE"$'\n''bash_teste tools/whatsappzzcheck.swift'); touch "$d/tools/whatsappzzcheck.swift"; roda_gates "$d"
  espera_codigo 1 "gates (a) .swift com bash_teste"
  espera_texto 'FALHOU: tools/whatsappzzcheck.swift sem entrada no check.sh' "gates (a) .swift com bash_teste"

  # (b) com swift_teste passa
  d=$(repo_gates <<<"$BASE"$'\n''swift_teste tools/whatsappzzcheck.swift Knobler/X.swift'); touch "$d/tools/whatsappzzcheck.swift"; roda_gates "$d"
  espera_codigo 0 "gates (b)"

  # (b) linha continuada com \ também passa
  d=$(repo_gates <<<"$BASE"$'\n''swift_teste tools/whatsappzzcheck.swift \'$'\n''  Knobler/X.swift'); touch "$d/tools/whatsappzzcheck.swift"; roda_gates "$d"
  espera_codigo 0 "gates (b) linha continuada"

  # (c) entrada sem arquivo
  d=$(repo_gates <<<"$BASE"$'\n''swift_teste tools/whatsappsumiucheck.swift Knobler/X.swift'); roda_gates "$d"
  espera_codigo 1 "gates (c)"
  espera_texto 'FALHOU: check.sh cita tools/whatsappsumiucheck.swift, que não existe' "gates (c)"

  d=$(repo_gates <<<"$BASE"$'\n''bash_teste tools/whatsappsumiucheck.sh'); roda_gates "$d"
  espera_codigo 1 "gates (c) .sh"
  espera_texto 'FALHOU: check.sh cita tools/whatsappsumiucheck.sh, que não existe' "gates (c) .sh"

  # (d) gate do WhatsApp por swift_check, mesmo com a entrada certa ao lado
  d=$(repo_gates <<<"$BASE"$'\n''swift_teste tools/whatsappzzcheck.swift Knobler/X.swift'$'\n''swift_check whatsappzzcheck Knobler/X.swift tools/whatsappzzcheck.swift')
  touch "$d/tools/whatsappzzcheck.swift"; roda_gates "$d"
  espera_codigo 1 "gates (d) swift_check"
  espera_texto 'FALHOU: gate do WhatsApp fora dos ajudantes' "gates (d) swift_check"

  d=$(repo_gates <<<"$BASE"$'\n''run whatsappyycheck bash -c true'); roda_gates "$d"
  espera_codigo 1 "gates (d) run"
  espera_texto 'FALHOU: gate do WhatsApp fora dos ajudantes' "gates (d) run"

  # (e) o mesmo para .sh
  d=$(repo_gates <<<"$BASE"); touch "$d/tools/whatsappyycheck.sh"; roda_gates "$d"
  espera_codigo 1 "gates (e) .sh sem entrada"
  espera_texto 'FALHOU: tools/whatsappyycheck.sh sem entrada no check.sh' "gates (e) .sh sem entrada"

  d=$(repo_gates <<<"$BASE"$'\n''bash_teste tools/whatsappyycheck.sh'); touch "$d/tools/whatsappyycheck.sh"; roda_gates "$d"
  espera_codigo 0 "gates (e) .sh com bash_teste"

  d=$(repo_gates <<<"$BASE"$'\n''swift_teste tools/whatsappyycheck.sh'); touch "$d/tools/whatsappyycheck.sh"; roda_gates "$d"
  espera_codigo 1 "gates (e) .sh com swift_teste"
  espera_texto 'FALHOU: tools/whatsappyycheck.sh sem entrada no check.sh' "gates (e) .sh com swift_teste"

  # gates que não são do WhatsApp ficam livres
  d=$(repo_gates <<<"$BASE"$'\n''swift_check outrozzcheck Knobler/X.swift tools/outrozzcheck.swift'$'\n''run outrozz bash -c true')
  touch "$d/tools/outrozzcheck.swift" "$d/tools/semregistrocheck.swift"; roda_gates "$d"
  espera_codigo 0 "gates: gates de fora do WhatsApp são ignorados"

  # vários problemas: um FALHOU por problema
  d=$(repo_gates <<<"$BASE"$'\n''swift_teste tools/whatsappsumiucheck.swift'$'\n''run whatsappyycheck bash -c true')
  touch "$d/tools/whatsappzzcheck.swift"; roda_gates "$d"
  espera_codigo 1 "gates: vários problemas"
  espera_texto 'FALHOU: tools/whatsappzzcheck.swift sem entrada no check.sh' "gates: vários problemas (a)"
  espera_texto 'FALHOU: check.sh cita tools/whatsappsumiucheck.swift, que não existe' "gates: vários problemas (c)"
  espera_texto 'FALHOU: gate do WhatsApp fora dos ajudantes' "gates: vários problemas (d)"

  # e no repo de verdade passa
  roda bash "$GATES"
  espera_codigo 0 "gates: tools/check.sh real"
fi

# --- 4. notchfontescheck num repo falso -----------------------------------
FONTESCHECK=tools/notchfontescheck.sh
if [ ! -f "$FONTESCHECK" ]; then
  falha "$FONTESCHECK não existe"
else
  # Repo mínimo: o header declara uma função que a NotchWindow usa e o main.swift
  # cita as duas fontes. Sem -import-objc-header, sem NotchWindow.swift ou sem
  # main.swift o typecheck não fecha; e como a função do header não tem corpo,
  # um build com link (em vez de -typecheck) também cai.
  repo_fontes() { # stdin = notchview-fontes.txt
    local d; d=$(mktemp -d "$T/fontes.XXXXXX")
    mkdir -p "$d/tools" "$d/Knobler" "$d/Vendor/MonitorControl"
    cp "$RAIZ/$FONTESCHECK" "$d/tools/notchfontescheck.sh"
    echo 'int ajudzz_do_header(void);' > "$d/Vendor/MonitorControl/MonitorControl.h"
    echo 'struct JanelaZZ { let n = ajudzz_do_header() }' > "$d/Knobler/NotchWindow.swift"
    echo 'struct FonteZZ { let x = 1 }' > "$d/Knobler/A.swift"
    echo 'print(FonteZZ().x, JanelaZZ().n)' > "$d/tools/main.swift"
    { echo '# Fontes que a NotchView arrasta (cópia de teste).'; cat; } > "$d/tools/notchview-fontes.txt"
    echo "$d"
  }
  roda_fontes() { roda bash -c "cd / && bash '$1/tools/notchfontescheck.sh'"; }

  d=$(repo_fontes <<<'Knobler/A.swift'); roda_fontes "$d"
  espera_codigo 0 "fontes: tudo certo, sem pasta Knobler/WhatsApp"

  d=$(repo_fontes <<<'Knobler/A.swift'$'\n''Knobler/WhatsApp/ConversaView.swift')
  mkdir -p "$d/Knobler/WhatsApp"
  echo 'struct ConversaViewZZ {}' > "$d/Knobler/WhatsApp/ConversaView.swift"
  echo 'struct ClienteZZ {}' > "$d/Knobler/WhatsApp/Cliente.swift"   # não é View: fica de fora sem problema
  roda_fontes "$d"
  espera_codigo 0 "fontes: view do WhatsApp listada"

  d=$(repo_fontes <<<'Knobler/A.swift'$'\n''Knobler/Sumiu.swift'); roda_fontes "$d"
  espera_codigo 1 "fontes: listada e ausente"
  espera_texto 'FALHOU: fonte listada e ausente: Knobler/Sumiu.swift' "fontes: listada e ausente"

  d=$(repo_fontes <<<'Knobler/A.swift'$'\n''Knobler/WhatsApp/ConversaView.swift')
  mkdir -p "$d/Knobler/WhatsApp"
  echo 'struct ConversaViewZZ {}' > "$d/Knobler/WhatsApp/ConversaView.swift"
  echo 'struct BolhaViewZZ {}' > "$d/Knobler/WhatsApp/BolhaView.swift"
  roda_fontes "$d"
  espera_codigo 1 "fontes: view do WhatsApp fora da lista"
  espera_texto 'FALHOU: view do WhatsApp fora do notchview-fontes.txt: Knobler/WhatsApp/BolhaView.swift' "fontes: view do WhatsApp fora da lista"

  d=$(repo_fontes <<<'Knobler/A.swift')
  echo 'struct FonteZZ { let x: Int = "ajudzz_tipo_errado" }' > "$d/Knobler/A.swift"
  roda_fontes "$d"
  espera_codigo 1 "fontes: erro de typecheck numa fonte listada"
  espera_texto 'A.swift:' "fontes: saída do swiftc aparece (arquivo)"
  espera_texto 'error:' "fontes: saída do swiftc aparece (erro)"

  d=$(repo_fontes <<<'Knobler/A.swift')
  echo 'struct JanelaZZ { let n: String = ajudzz_do_header() }' > "$d/Knobler/NotchWindow.swift"
  roda_fontes "$d"
  espera_codigo 1 "fontes: erro de typecheck na NotchWindow.swift"
  espera_texto 'NotchWindow.swift:' "fontes: erro na NotchWindow.swift aparece"
fi

if [ "$FALHAS" -gt 0 ]; then
  echo "gateajudantescheck: $FALHAS falha(s)"
  exit 1
fi
echo "gateajudantescheck: ok"
