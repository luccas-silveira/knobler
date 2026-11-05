#!/usr/bin/env bash
# Gate da etapa 16 do WhatsApp: o ditado escrevendo no campo do WhatsApp,
# ligado nos arquivos que só o app compila.
#
# O ./tools/check.sh não compila o app (Dictation.swift importa FluidAudio e
# KnoblerApp.swift só compila com o app); o whatsappditadocheck prova a
# escolha do destino e o receberDitado, não que o controller e o AppDelegate
# os usam. Confere:
#   - `enum DictationDestination` é declarado em Knobler/DictationDestination.swift
#     e em nenhum outro arquivo de Knobler/ (saiu de Knobler/Dictation.swift);
#   - Knobler/Dictation.swift tem `case .some(.whatsapp(let chave)):` e
#     `self.transcriptSink?(trimmed, .whatsapp(chave: chave))`, e, quando o
#     sink recusa (`!= true`), copia o texto (`Self.copy(trimmed)`) dentro do
#     mesmo `case`, como o `.ask`;
#   - Knobler/KnoblerApp.swift tem `DictationDestination.escolher(askAtivo:`,
#     `campoWhatsApp: WhatsAppStore.shared.campoEmUso?.texto`,
#     `WhatsAppStore.shared.receberDitado(` e segue entregando o Ask
#     (`.appendText(id: id, text: text)`).
# Linha de comentário (`//`) não conta como ligação.
# Cada falta imprime `FALHOU: <o quê>` e o gate sai 1. Antes da checagem real,
# um autoteste num repo falso prova que a verificação reprova.
#
# Uso: bash tools/whatsappditadoligacaocheck.sh
set -uo pipefail
cd "$(dirname "$0")/.."

CASO_WA='case .some(.whatsapp(let chave)):'
SINK_WA='self.transcriptSink?(trimmed, .whatsapp(chave: chave))'
COPIA='Self.copy(trimmed)'
ESCOLHER='DictationDestination.escolher(askAtivo:'
CAMPO='campoWhatsApp: WhatsAppStore.shared.campoEmUso?.texto'
RECEBER='WhatsAppStore.shared.receberDitado('
ASK='.appendText(id: id, text: text)'
DECL='^[[:space:]]*([a-z]+[[:space:]]+)*enum[[:space:]]+DictationDestination([^A-Za-z0-9_]|$)'

# linhas_codigo <arquivo> <texto fixo>: "número:conteúdo" de cada linha de
# código (não comentário) que contém o texto.
linhas_codigo() {
  grep -nF -- "$2" "$1" 2>/dev/null | grep -vE '^[0-9]+:[[:space:]]*//'
}

tem() { [ -n "$(linhas_codigo "$1" "$2" | head -1)" ]; }

# declaram <pasta Knobler>: arquivos (relativos à pasta) que declaram o enum.
declaram() {
  local k="$1" f
  while IFS= read -r f; do
    printf '%s\n' "${f#"$k"/}"
  done < <(grep -rlE --include='*.swift' -- "$DECL" "$k" 2>/dev/null | sort)
}

# bloco_whatsapp <arquivo>: do `case .some(.whatsapp(let chave)):` até antes
# do próximo `case`/`default:` (ou do fim do arquivo).
bloco_whatsapp() {
  awk -v alvo="$CASO_WA" '
    dentro && /^[[:space:]]*(case[[:space:]]|default:)/ { exit }
    dentro { print }
    !dentro && index($0, alvo) && $0 !~ /^[[:space:]]*\/\// { dentro = 1; print }
  ' "$1"
}

# verificar <raiz>
verificar() {
  local r="$1" erro=0
  local dit="$r/Knobler/Dictation.swift"
  local dest="$r/Knobler/DictationDestination.swift"
  local app="$r/Knobler/KnoblerApp.swift"
  local f lista bloco

  for f in "$dit" "$dest" "$app"; do
    if [ ! -f "$f" ]; then
      echo "FALHOU: ${f#"$r"/} não existe"
      erro=1
    fi
  done

  lista=$(declaram "$r/Knobler")
  if [ "$lista" != "DictationDestination.swift" ]; then
    echo "FALHOU: 'enum DictationDestination' tem que ser declarado só em Knobler/DictationDestination.swift; declarado em: ${lista:-nenhum arquivo}" | tr '\n' ' '
    echo
    erro=1
  fi

  if [ -f "$dit" ]; then
    for f in "$CASO_WA" "$SINK_WA"; do
      if ! tem "$dit" "$f"; then
        echo "FALHOU: Knobler/Dictation.swift sem '$f'"
        erro=1
      fi
    done
    if tem "$dit" "$CASO_WA"; then
      bloco=$(bloco_whatsapp "$dit" | grep -vE '^[[:space:]]*//')
      if ! printf '%s\n' "$bloco" | grep -F -- "$SINK_WA" | grep -qF -- '!= true'; then
        echo "FALHOU: Knobler/Dictation.swift: no case .whatsapp, '$SINK_WA' sem '!= true' (recusa do campo não é tratada)"
        erro=1
      fi
      if ! printf '%s\n' "$bloco" | grep -qF -- "$COPIA"; then
        echo "FALHOU: Knobler/Dictation.swift: o case .whatsapp não copia o texto ('$COPIA') quando o campo recusa"
        erro=1
      fi
    fi
  fi

  if [ -f "$app" ]; then
    for f in "$ESCOLHER" "$CAMPO" "$RECEBER" "$ASK"; do
      if ! tem "$app" "$f"; then
        echo "FALHOU: Knobler/KnoblerApp.swift sem '$f'"
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
  mkdir -p "$T/r/Knobler/WhatsApp"
  cat > "$T/r/Knobler/DictationDestination.swift" <<'EOF'
import Foundation

enum DictationDestination: Equatable {
    case ask(id: String)
    case whatsapp(chave: String)
    case application(pid: pid_t)

    static func escolher(askAtivo: String?, campoWhatsApp: String?, pidDaFrente: pid_t?) -> DictationDestination? {
        if let askAtivo { return .ask(id: askAtivo) }
        if let campoWhatsApp { return .whatsapp(chave: campoWhatsApp) }
        return pidDaFrente.map { .application(pid: $0) }
    }
}
EOF
  cat > "$T/r/Knobler/Dictation.swift" <<'EOF'
import FluidAudio

// MARK: - Controller

/// Conformidade da peça.
final class DictationController {
    var destinationProvider: (() -> DictationDestination?)?
    var transcriptSink: ((String, DictationDestination) -> Bool)?

    func finish() {
        Task { @MainActor in
            do {
                switch destination {
                case .some(.ask(let id)):
                    if self.transcriptSink?(trimmed, .ask(id: id)) != true {
                        Self.copy(trimmed)
                        self.flash(.error("Pergunta mudou — texto copiado"))
                    }
                case .some(.whatsapp(let chave)):
                    if self.transcriptSink?(trimmed, .whatsapp(chave: chave)) != true {
                        Self.copy(trimmed)
                        self.flash(.error("Campo mudou — texto copiado"))
                    }
                case .some(.application(let pid)):
                    if !Self.insert(trimmed, expectedPID: pid) {
                        self.flash(.error("App mudou — texto copiado"))
                    }
                case .none:
                    Self.copy(trimmed)
                    self.flash(.error("Sem destino — texto copiado"))
                }
            } catch {
                self.flash(.error("Falha na transcrição"))
            }
        }
    }
}
EOF
  cat > "$T/r/Knobler/KnoblerApp.swift" <<'EOF'
        plugins.ditadoEfeitos = DitadoEfeitos(nascer: { [weak self] in
            guard let self else { return nil }
            let d = DictationController()
            d.destinationProvider = { [weak self] in
                DictationDestination.escolher(askAtivo: self?.askStore?.state.active?.id,
                                              campoWhatsApp: WhatsAppStore.shared.campoEmUso?.texto,
                                              pidDaFrente: NSWorkspace.shared.frontmostApplication?.processIdentifier)
            }
            d.transcriptSink = { [weak self] text, destination in
                switch destination {
                case .ask(let id):
                    guard self?.askStore?.state.active?.id == id else { return false }
                    self?.askStore?.send(.appendText(id: id, text: text))
                    return true
                case .whatsapp(let chave):
                    return WhatsAppStore.shared.receberDitado(text, chave: chave)
                case .application:
                    return false
                }
            }
            d.start()
            return d
        })
EOF
  cat > "$T/r/Knobler/WhatsApp/WhatsAppStore.swift" <<'EOF'
@MainActor
final class WhatsAppStore: ObservableObject {
    @Published var campoEmUso: WAChave?
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

DIT="$T/r/Knobler/Dictation.swift"
DEST="$T/r/Knobler/DictationDestination.swift"
APP="$T/r/Knobler/KnoblerApp.swift"

montar
caso "ligação certa" 0 ""

montar
# comentário citando o enum no Dictation não conta como declaração
sed -i '' 's|^// MARK: - Controller|// MARK: - Controller\
// enum DictationDestination mora em DictationDestination.swift|' "$DIT"
caso "comentário citando o enum" 0 ""

montar
# o "if" numa linha só também vale
cat > "$T/r/Knobler/Dictation.swift" <<'EOF'
final class DictationController {
    func finish() {
        switch destination {
        case .some(.ask(let id)):
            if self.transcriptSink?(trimmed, .ask(id: id)) != true { Self.copy(trimmed) }
        case .some(.whatsapp(let chave)):
            if self.transcriptSink?(trimmed, .whatsapp(chave: chave)) != true { Self.copy(trimmed); self.flash(.error("Campo mudou — texto copiado")) }
        case .some(.application(let pid)):
            _ = Self.insert(trimmed, expectedPID: pid)
        case .none:
            Self.copy(trimmed)
        }
    }
}
EOF
caso "if numa linha só" 0 ""

montar
# o estado de hoje: o enum ainda no Dictation, sem arquivo próprio
rm "$DEST"
cat >> "$DIT" <<'EOF'

enum DictationDestination: Equatable {
    case ask(id: String)
    case application(pid: pid_t)
}
EOF
caso "enum ainda no Dictation, sem arquivo próprio" 1 "Knobler/DictationDestination.swift não existe"

montar
cat >> "$DIT" <<'EOF'

enum DictationDestination: Equatable {
    case ask(id: String)
    case whatsapp(chave: String)
    case application(pid: pid_t)
}
EOF
caso "enum declarado nos dois" 1 "declarado em: Dictation.swift DictationDestination.swift"

montar
sed -i '' 's|^enum DictationDestination: Equatable {|struct NaoEOEnum {|' "$DEST"
cat >> "$DIT" <<'EOF'

public enum DictationDestination: Equatable { case ask(id: String) }
EOF
caso "enum só no Dictation (com modificador)" 1 "declarado em: Dictation.swift"

montar
sed -i '' 's|^enum DictationDestination: Equatable {|struct NaoEOEnum {|' "$DEST"
caso "enum em lugar nenhum" 1 "declarado em: nenhum arquivo"

montar
sed -i '' 's|^enum DictationDestination: Equatable {|struct NaoEOEnum {|' "$DEST"
cat > "$T/r/Knobler/WhatsApp/Destino.swift" <<'EOF'
enum DictationDestination: Equatable { case ask(id: String) }
EOF
caso "enum em outro arquivo" 1 "declarado em: WhatsApp/Destino.swift"

montar
sed -i '' 's|case .some(.whatsapp(let chave)):|case .some(.whatsapp(let k)):|' "$DIT"
caso "Dictation sem o case .whatsapp" 1 "sem '$CASO_WA'"

montar
sed -i '' 's|^                case .some(.whatsapp(let chave)):|                // case .some(.whatsapp(let chave)):|' "$DIT"
caso "case .whatsapp só em comentário" 1 "sem '$CASO_WA'"

montar
sed -i '' 's|self.transcriptSink?(trimmed, .whatsapp(chave: chave))|self.transcriptSink?(trimmed, .ask(id: chave))|' "$DIT"
caso "Dictation sem entregar .whatsapp ao sink" 1 "sem '$SINK_WA'"

montar
# entrega ao sink mas ignora a recusa: texto se perde
cat > "$T/r/Knobler/Dictation.swift" <<'EOF'
final class DictationController {
    func finish() {
        switch destination {
        case .some(.ask(let id)):
            if self.transcriptSink?(trimmed, .ask(id: id)) != true {
                Self.copy(trimmed)
            }
        case .some(.whatsapp(let chave)):
            _ = self.transcriptSink?(trimmed, .whatsapp(chave: chave))
        case .some(.application(let pid)):
            _ = Self.insert(trimmed, expectedPID: pid)
        case .none:
            Self.copy(trimmed)
        }
    }
}
EOF
caso "recusa do campo ignorada" 1 "sem '!= true'"

montar
# testa a recusa mas não copia (o Self.copy do .none, mais abaixo, não conta)
cat > "$T/r/Knobler/Dictation.swift" <<'EOF'
final class DictationController {
    func finish() {
        switch destination {
        case .some(.ask(let id)):
            if self.transcriptSink?(trimmed, .ask(id: id)) != true {
                Self.copy(trimmed)
            }
        case .some(.whatsapp(let chave)):
            if self.transcriptSink?(trimmed, .whatsapp(chave: chave)) != true {
                // Self.copy(trimmed)
                self.flash(.error("Campo mudou"))
            }
        case .some(.application(let pid)):
            _ = Self.insert(trimmed, expectedPID: pid)
        case .none:
            Self.copy(trimmed)
        }
    }
}
EOF
caso "recusa do campo sem copiar" 1 "não copia o texto"

montar
sed -i '' 's|DictationDestination.escolher(askAtivo: |DictationDestination.escolher(ask: |' "$APP"
caso "AppDelegate sem escolher(askAtivo:" 1 "sem '$ESCOLHER'"

montar
sed -i '' 's|campoWhatsApp: WhatsAppStore.shared.campoEmUso?.texto,|campoWhatsApp: nil,|' "$APP"
caso "AppDelegate sem o campo em uso" 1 "sem '$CAMPO'"

montar
sed -i '' 's|return WhatsAppStore.shared.receberDitado(text, chave: chave)|return false|' "$APP"
caso "AppDelegate sem receberDitado" 1 "sem '$RECEBER'"

montar
sed -i '' 's|^                    return WhatsAppStore.shared.receberDitado(|                    // return WhatsAppStore.shared.receberDitado(|' "$APP"
caso "receberDitado só em comentário" 1 "sem '$RECEBER'"

montar
sed -i '' '/appendText(id: id, text: text)/d' "$APP"
caso "AppDelegate parou de entregar o Ask" 1 "sem '$ASK'"

montar
rm "$DIT"
caso "Dictation ausente" 1 "Knobler/Dictation.swift não existe"

montar
rm "$APP"
caso "KnoblerApp ausente" 1 "Knobler/KnoblerApp.swift não existe"

if [ "$AUTO" -ne 0 ]; then
  echo "FALHOU: autoteste do whatsappditadoligacaocheck"
  exit 1
fi

# --- checagem real -----------------------------------------------------------
verificar . || exit 1
echo "whatsappditadoligacaocheck ok"
