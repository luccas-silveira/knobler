#!/usr/bin/env bash
# Gate da etapa 27 do WhatsApp: a documentação da integração.
#
# Confere o que quem lê a doc vê:
#   - docs/whatsapp.md existe, tem as seções `## O que é`, `## Pré-requisitos`,
#     `## Chave e porta`, `## Instalar a peça`, `## Parear uma conta`,
#     `## Estados` e `## Testes` (linha de título exata) e cita
#     `docs/whatsapp-ponte.md`;
#   - docs/ROADMAP.md não tem mais "WhatsApp Web", tem um item (bullet, com as
#     linhas de continuação) do "WhatsApp pela ponte local" que aponta pra
#     `docs/whatsapp.md` e mantém a regra do ditado (cita "ditado" e
#     "selecionado", decisão A16);
#   - docs/IDEIAS.md não tem mais "login headless" nem "WhatsApp Web" e aponta
#     pra `docs/whatsapp.md`;
#   - docs/architecture.md tem, na tabela de estado (a que começa em
#     `| Estado | Dono atual | Consumidores |`), uma linha com
#     `WhatsAppStore.shared`;
#   - CHANGELOG.md: o WhatsApp aparece numa linha só, a do lançamento. A linha
#     de lançamento cita WhatsApp e diz "integração opcional", "ponte local" e
#     "invisível"; existe exatamente UMA no arquivo inteiro, é um item `- ` sob
#     `### Added` e mora no `## [Unreleased]` ou no bloco da versão em que saiu
#     (o release move o bloco, e o gate não pode quebrar por isso). O bloco
#     dela não tem outra linha citando WhatsApp, e nenhum bloco acima dele
#     cita: o `[Unreleased]`, depois do lançamento, e as versões mais novas.
#     Versão anterior à do lançamento não conta. O `## [Unreleased]` tem que
#     existir;
#   - nenhum arquivo de Knobler/Novidades/ cita WhatsApp (A4/A48).
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappdocscheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

SECOES='O que é|Pré-requisitos|Chave e porta|Instalar a peça|Parear uma conta|Estados|Testes'
CABECALHO_ESTADO='| Estado | Dono atual | Consumidores |'

# itens <arquivo>: um bullet `- ` por linha, com as linhas de continuação
# (indentadas) coladas e o espaço normalizado.
itens() {
  awk '
    /^- /            { if (i != "") print i; i = $0; next }
    /^[[:space:]]+[^[:space:]]/ { if (i != "") { sub(/^[[:space:]]+/, ""); i = i " " $0 }; next }
                     { if (i != "") print i; i = "" }
    END              { if (i != "") print i }
  ' "$1" 2>/dev/null
}

# citacoes <CHANGELOG>: uma linha por linha do arquivo que cita WhatsApp, como
# `<nº do bloco>\t<bloco>\t<seção>\t<linha>`. Bloco é cada `## [nome]` (o 1 é
# o primeiro, de cima pra baixo; 0 é o que vem antes dele) e seção é a última
# `### ` do bloco antes da linha.
citacoes() {
  awk '
    /^## \[/ { n++; b = $0; sub(/^## \[/, "", b); sub(/\].*$/, "", b); s = "" }
    /^### /  { s = $0 }
    tolower($0) ~ /whatsapp/ { printf "%d\t%s\t%s\t%s\n", n, b, s, $0 }
  ' "$1" 2>/dev/null
}

# conta: quantas linhas não vazias chegam pela entrada
conta() { grep -c . || true; }

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local doc="$r/docs/whatsapp.md"
  local rm="$r/docs/ROADMAP.md"
  local ideias="$r/docs/IDEIAS.md"
  local arq="$r/docs/architecture.md"
  local cl="$r/CHANGELOG.md"
  local nov="$r/Knobler/Novidades"
  local f s item bloco n cit lanc b_n b_nome secao linha acima

  for f in "$doc" "$rm" "$ideias" "$arq" "$cl"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  # --- docs/whatsapp.md -------------------------------------------------------
  if [ -f "$doc" ]; then
    local IFS_ANT="$IFS"; IFS='|'
    for s in $SECOES; do
      if ! grep -qxF -- "## $s" "$doc"; then
        echo "FALHOU: docs/whatsapp.md sem a seção '## $s'"
        erro=1
      fi
    done
    IFS="$IFS_ANT"
    if ! grep -qF -- 'docs/whatsapp-ponte.md' "$doc"; then
      echo "FALHOU: docs/whatsapp.md não cita docs/whatsapp-ponte.md"
      erro=1
    fi
  fi

  # --- docs/ROADMAP.md --------------------------------------------------------
  if [ -f "$rm" ]; then
    if grep -qiF -- 'WhatsApp Web' "$rm"; then
      echo "FALHOU: docs/ROADMAP.md ainda tem 'WhatsApp Web'"
      erro=1
    fi
    item=$(itens "$rm" | grep -iF -- 'WhatsApp pela ponte local' | head -1)
    if [ -z "$item" ]; then
      echo "FALHOU: docs/ROADMAP.md sem item do 'WhatsApp pela ponte local'"
      erro=1
    else
      if ! printf '%s\n' "$item" | grep -qF -- 'docs/whatsapp.md'; then
        echo "FALHOU: item do WhatsApp no docs/ROADMAP.md não aponta pra docs/whatsapp.md"
        erro=1
      fi
      if ! printf '%s\n' "$item" | grep -qiF -- 'ditado' \
        || ! printf '%s\n' "$item" | grep -qiF -- 'selecionado'; then
        echo "FALHOU: item do WhatsApp no docs/ROADMAP.md perdeu a regra do ditado (só no campo selecionado)"
        erro=1
      fi
    fi
  fi

  # --- docs/IDEIAS.md ---------------------------------------------------------
  if [ -f "$ideias" ]; then
    if grep -qiF -- 'login headless' "$ideias"; then
      echo "FALHOU: docs/IDEIAS.md ainda tem 'login headless'"
      erro=1
    fi
    if grep -qiF -- 'WhatsApp Web' "$ideias"; then
      echo "FALHOU: docs/IDEIAS.md ainda tem 'WhatsApp Web'"
      erro=1
    fi
    if ! grep -qF -- 'docs/whatsapp.md' "$ideias"; then
      echo "FALHOU: docs/IDEIAS.md não aponta pra docs/whatsapp.md"
      erro=1
    fi
  fi

  # --- docs/architecture.md ---------------------------------------------------
  if [ -f "$arq" ]; then
    if ! grep -qF -- "$CABECALHO_ESTADO" "$arq"; then
      echo "FALHOU: docs/architecture.md sem a tabela de estado ('$CABECALHO_ESTADO')"
      erro=1
    else
      # só as linhas contíguas da tabela que começa no cabeçalho
      bloco=$(awk -v h="$CABECALHO_ESTADO" '
        index($0, h) == 1 { f = 1; next }
        f && /^\|/ { print; next }
        f { exit }
      ' "$arq")
      if ! printf '%s\n' "$bloco" | grep -qF -- 'WhatsAppStore.shared'; then
        echo "FALHOU: tabela de estado do docs/architecture.md sem linha com WhatsAppStore.shared"
        erro=1
      fi
    fi
  fi

  # --- CHANGELOG.md -----------------------------------------------------------
  if [ -f "$cl" ]; then
    if ! grep -q '^## \[Unreleased\]' "$cl"; then
      echo "FALHOU: CHANGELOG.md sem '## [Unreleased]'"
      erro=1
    else
      cit=$(citacoes "$cl")
      # a linha de lançamento: cita WhatsApp e diz as três coisas
      lanc=$(printf '%s\n' "$cit" | grep -iF -- 'integração opcional' \
        | grep -iF -- 'ponte local' | grep -iF -- 'invisível')
      n=$(printf '%s\n' "$lanc" | conta)
      if [ "$n" -eq 0 ]; then
        echo "FALHOU: CHANGELOG.md sem a linha de lançamento do WhatsApp (item '- ' sob '### Added' que diz 'integração opcional', 'ponte local' e 'invisível')"
        erro=1
      elif [ "$n" -gt 1 ]; then
        echo "FALHOU: CHANGELOG.md tem $n linhas de lançamento do WhatsApp (tem que ser exatamente 1), nos blocos:$(printf '%s\n' "$lanc" | cut -f2 | sed 's/.*/ [&]/' | tr -d '\n')"
        erro=1
      else
        b_n=$(printf '%s\n' "$lanc" | cut -f1)
        b_nome=$(printf '%s\n' "$lanc" | cut -f2)
        secao=$(printf '%s\n' "$lanc" | cut -f3)
        linha=$(printf '%s\n' "$lanc" | cut -f4-)
        if ! printf '%s\n' "$linha" | grep -q '^- '; then
          echo "FALHOU: linha de lançamento do WhatsApp no CHANGELOG.md não é um item '- '"
          erro=1
        fi
        if [ "$secao" != "### Added" ]; then
          echo "FALHOU: linha de lançamento do WhatsApp no CHANGELOG.md fora de '### Added' (está sob '${secao:-nenhuma}', bloco [$b_nome])"
          erro=1
        fi
        # o bloco do lançamento só cita WhatsApp na linha do lançamento
        n=$(printf '%s\n' "$cit" | awk -F'\t' -v b="$b_n" '$1 == b' | conta)
        if [ "$n" -ne 1 ]; then
          echo "FALHOU: CHANGELOG.md, bloco [$b_nome] tem $n linha(s) citando WhatsApp (tem que ser só a do lançamento)"
          erro=1
        fi
        # nada acima dele cita: o [Unreleased] depois do lançamento e as
        # versões mais novas. As versões de baixo (mais velhas) não contam.
        acima=$(printf '%s\n' "$cit" | awk -F'\t' -v b="$b_n" '$1 < b { print ($2 == "" ? "antes do primeiro bloco" : "bloco [" $2 "]") }' \
          | sort | uniq -c | sed -E 's/^ *([0-9]+) (.*)$/\2 (\1 linha(s))/')
        if [ -n "$acima" ]; then
          printf '%s\n' "$acima" | while read -r s; do
            echo "FALHOU: CHANGELOG.md cita WhatsApp depois do lançamento, que está em [$b_nome]: $s. O WhatsApp aparece numa linha só, a do lançamento"
          done
          erro=1
        fi
      fi
    fi
  fi

  # --- Knobler/Novidades/ -----------------------------------------------------
  if [ -d "$nov" ]; then
    f=$(grep -ril -- 'whatsapp' "$nov" 2>/dev/null | head -5)
    if [ -n "$f" ]; then
      printf '%s\n' "$f" | while read -r s; do
        echo "FALHOU: ${s#"$r"/} cita WhatsApp (a página de novidades não fala dele)"
      done
      erro=1
    fi
  fi

  return "$erro"
}

# --- autoteste ---------------------------------------------------------------
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

DOC="$T/r/docs/whatsapp.md"
RM="$T/r/docs/ROADMAP.md"
ID="$T/r/docs/IDEIAS.md"
ARQ="$T/r/docs/architecture.md"
CL="$T/r/CHANGELOG.md"
NOV="$T/r/Knobler/Novidades"

# repo falso com a doc certa; cada caso estraga uma coisa
montar() {
  rm -rf "$T/r"
  mkdir -p "$T/r/docs" "$NOV"
  cat > "$DOC" <<'EOF'
# WhatsApp no notch

Contrato da ponte: `docs/whatsapp-ponte.md`.

## O que é

Duas contas, só do dono.

## Pré-requisitos

Ponte rodando como `com.whatsapp-mcp.bridge`.

## Chave e porta

`~/Library/Application Support/whatsapp-bridge/api-key`, porta 8099.

## Instalar a peça

Vitrine.

## Parear uma conta

QR no notch.

## Estados

Conectado, sem ponte.

## Testes

`./tools/check.sh`.
EOF
  cat > "$RM" <<'EOF'
## Itens soltos

- **Notificações com ações** — travado.
- **WhatsApp pela ponte local** — feito; ver `docs/whatsapp.md`. O ditado
  continua escrevendo só no campo selecionado (o campo do notch conta).
- **Profiling de memória** — isolado.
EOF
  cat > "$ID" <<'EOF'
## Integrações Externas

- **WhatsApp pela ponte local** — feito; ver `docs/whatsapp.md`.
EOF
  cat > "$ARQ" <<'EOF'
## Estado

| Estado | Dono atual | Consumidores |
|---|---|---|
| Preferências | `AppSettings` | serviços |
| Contas, conversas, mensagens e rascunhos do WhatsApp | `WhatsAppStore.shared` — um por app | seção WhatsApp |

Outra tabela:

| Coisa | Onde |
|---|---|
| x | y |
EOF
  cat > "$CL" <<'EOF'
# Changelog

## [Unreleased]

### Added
- Integração opcional com uma ponte local de WhatsApp, invisível sem ela.

### Changed
- Outra coisa.

## [0.36.0] - 2026-09-29

### Added
- Coisa antiga que cita WhatsApp de passagem.
EOF
  cat > "$NOV/0.37.0.html" <<'EOF'
<h1>Novidades</h1><p>Capturas de tela.</p>
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
caso "doc certa (WhatsApp em versão antiga do CHANGELOG não conta)" 0 ""

# docs/whatsapp.md
montar
rm "$DOC"
caso "whatsapp.md ausente" 1 "docs/whatsapp.md não existe"

IFS_ANT="$IFS"; IFS='|'
for s in $SECOES; do
  IFS="$IFS_ANT"
  montar
  grep -vxF -- "## $s" "$DOC" > "$DOC.novo"; mv "$DOC.novo" "$DOC"
  caso "whatsapp.md sem ## $s" 1 "sem a seção '## $s'"
  IFS='|'
done
IFS="$IFS_ANT"

montar
sed -i '' 's|^## Chave e porta$|### Chave e porta|' "$DOC"
caso "seção em nível errado" 1 "sem a seção '## Chave e porta'"

montar
sed -i '' 's|^## Estados$|## Estados e erros|' "$DOC"
caso "título de seção diferente" 1 "sem a seção '## Estados'"

montar
sed -i '' 's|docs/whatsapp-ponte.md|o contrato|' "$DOC"
caso "whatsapp.md sem citar o contrato" 1 "não cita docs/whatsapp-ponte.md"

# docs/ROADMAP.md
montar
printf -- '- **WhatsApp Web** — descartado.\n' >> "$RM"
caso "ROADMAP ainda com WhatsApp Web" 1 "ROADMAP.md ainda tem 'WhatsApp Web'"

montar
sed -i '' 's|WhatsApp pela ponte local|WhatsApp|' "$RM"
caso "ROADMAP sem item da ponte local" 1 "sem item do 'WhatsApp pela ponte local'"

montar
sed -i '' 's|ver `docs/whatsapp.md`|ver a doc|' "$RM"
caso "ROADMAP sem apontar a doc" 1 "não aponta pra docs/whatsapp.md"

montar
cat > "$RM" <<'EOF'
## Itens soltos

- **WhatsApp pela ponte local** — feito; ver `docs/whatsapp.md`.
- **Ditado** — escreve só no campo selecionado.
EOF
caso "ROADMAP sem a regra do ditado no item" 1 "perdeu a regra do ditado"

# docs/IDEIAS.md
montar
printf -- '- **Envio**: parse da URL, login headless.\n' >> "$ID"
caso "IDEIAS ainda com login headless" 1 "IDEIAS.md ainda tem 'login headless'"

montar
printf -- '- **WhatsApp Web**: enviar.\n' >> "$ID"
caso "IDEIAS ainda com WhatsApp Web" 1 "IDEIAS.md ainda tem 'WhatsApp Web'"

montar
sed -i '' 's|ver `docs/whatsapp.md`|feito|' "$ID"
caso "IDEIAS sem apontar a doc" 1 "IDEIAS.md não aponta pra docs/whatsapp.md"

# docs/architecture.md
montar
grep -vF 'WhatsAppStore.shared' "$ARQ" > "$ARQ.novo"; mv "$ARQ.novo" "$ARQ"
caso "arquitetura sem WhatsAppStore.shared" 1 "sem linha com WhatsAppStore.shared"

montar
grep -vF 'WhatsAppStore.shared' "$ARQ" > "$ARQ.novo"; mv "$ARQ.novo" "$ARQ"
printf '| WhatsApp | `WhatsAppStore.shared` |\n' >> "$ARQ"
caso "WhatsAppStore.shared em outra tabela" 1 "sem linha com WhatsAppStore.shared"

montar
grep -vF 'WhatsAppStore.shared' "$ARQ" > "$ARQ.novo"; mv "$ARQ.novo" "$ARQ"
printf '\nO estado do WhatsApp mora em `WhatsAppStore.shared`.\n' >> "$ARQ"
caso "WhatsAppStore.shared só em prosa" 1 "sem linha com WhatsAppStore.shared"

# CHANGELOG.md
LANCAMENTO='- Integração opcional com uma ponte local de WhatsApp, invisível sem ela.'

# changelog_lancado <miolo do Unreleased>: o lançamento já saiu na 0.37.0 (é o
# que o release faz com o bloco) e uma versão velha cita WhatsApp de passagem.
changelog_lancado() {
  {
    printf '# Changelog\n\n## [Unreleased]\n'
    [ -n "${1:-}" ] && printf '\n%s\n' "$1"
    printf '\n## [0.37.0] - 2026-11-10\n\n### Added\n%s\n\n### Changed\n- Outra coisa.\n' "$LANCAMENTO"
    printf '\n## [0.36.0] - 2026-09-29\n\n### Fixed\n- Coisa antiga que cita WhatsApp de passagem,\n  e de novo o WhatsApp na linha de baixo.\n'
  } > "$CL"
}

# o montar deixa o lançamento ainda no [Unreleased]: é o caso "doc certa" lá em cima

montar
changelog_lancado
caso "lançamento já numa versão, Unreleased vazio" 0 ""

montar
changelog_lancado '### Fixed
- Trocar de conversa no notch abre sempre na mensagem mais recente.'
caso "lançamento já numa versão, Unreleased com Fixed que não cita WhatsApp" 0 ""

montar
changelog_lancado '### Fixed
- A conversa do WhatsApp abre na mensagem mais recente.'
caso "Unreleased citando WhatsApp depois do lançamento" 1 "depois do lançamento, que está em [0.37.0]: bloco [Unreleased] (1 linha(s))"

montar
changelog_lancado "### Added
$LANCAMENTO"
caso "linha de lançamento repetida no Unreleased e na versão" 1 "tem 2 linhas de lançamento do WhatsApp"

montar
changelog_lancado
sed -i '' 's|^## \[0.37.0\] - 2026-11-10$|## [0.38.0] - 2026-11-20\
\
### Fixed\
- O card do WhatsApp não corta mais a foto.\
\
## [0.37.0] - 2026-11-10|' "$CL"
caso "versão mais nova que a do lançamento citando WhatsApp" 1 "depois do lançamento, que está em [0.37.0]: bloco [0.38.0] (1 linha(s))"

montar
changelog_lancado
sed -i '' 's|^- Outra coisa\.$|- Seção WhatsApp no notch com duas colunas.|' "$CL"
caso "bloco da versão do lançamento com outra linha do WhatsApp" 1 "bloco [0.37.0] tem 2 linha(s) citando WhatsApp"

montar
changelog_lancado
sed -i '' 's|^### Added$|### Changed|' "$CL"
caso "lançamento numa versão, fora de ### Added" 1 "fora de '### Added'"

montar
changelog_lancado
grep -vxF -- "$LANCAMENTO" "$CL" > "$CL.novo"; mv "$CL.novo" "$CL"
caso "sem linha de lançamento em lugar nenhum (a citação da versão velha não vale)" 1 "sem a linha de lançamento do WhatsApp"

montar
grep -viF 'whatsapp' "$CL" > "$CL.novo"; mv "$CL.novo" "$CL"
caso "CHANGELOG sem linha nenhuma do WhatsApp" 1 "sem a linha de lançamento do WhatsApp"

montar
sed -i '' 's|^### Changed$|### Changed\
- Seção WhatsApp no notch com duas colunas.|' "$CL"
caso "Unreleased do lançamento com duas linhas do WhatsApp" 1 "bloco [Unreleased] tem 2 linha(s) citando WhatsApp"

montar
sed -i '' 's|^### Changed$|### Changed\
- Integração opcional com uma ponte local de WhatsApp, invisível sem ela, de novo.|' "$CL"
caso "linha de lançamento repetida no mesmo bloco" 1 "tem 2 linhas de lançamento do WhatsApp"

montar
sed -i '' 's|^- Integração opcional com uma ponte local de WhatsApp, invisível sem ela.$|- WhatsApp no notch.|' "$CL"
caso "linha sem integração opcional" 1 "sem a linha de lançamento do WhatsApp"

montar
sed -i '' 's|, invisível sem ela||' "$CL"
caso "linha sem invisível" 1 "sem a linha de lançamento do WhatsApp"

montar
sed -i '' 's|ponte local de WhatsApp|ponte de WhatsApp|' "$CL"
caso "linha sem ponte local" 1 "sem a linha de lançamento do WhatsApp"

montar
cat > "$CL" <<'EOF'
# Changelog

## [Unreleased]

### Changed
- Integração opcional com uma ponte local de WhatsApp, invisível sem ela.

## [0.36.0] - 2026-09-29
EOF
caso "linha fora de ### Added" 1 "fora de '### Added'"

montar
sed -i '' 's|^- Integração opcional|Integração opcional|' "$CL"
caso "linha que não é item" 1 "não é um item '- '"

montar
sed -i '' 's|^## \[Unreleased\]$|## [0.37.0] - 2026-11-06|' "$CL"
caso "CHANGELOG sem Unreleased" 1 "sem '## [Unreleased]'"

# Knobler/Novidades/
montar
printf '<p>Agora com WhatsApp no notch.</p>\n' > "$NOV/0.37.0.html"
caso "novidades citando WhatsApp" 1 "cita WhatsApp"

montar
printf 'let v = ["0.37.0"] // whatsapp\n' > "$NOV/NovidadesCatalogo.swift"
caso "qualquer arquivo de Novidades citando whatsapp" 1 "cita WhatsApp"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappdocscheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappdocscheck ok"
