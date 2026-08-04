//
//  WebhookTemplate.swift
//  Knobler
//
//  Motor de template dos webhooks — árvore do payload (`JSONValue`), resolução
//  de `{{caminho}}` e os três filtros de 014 (`semHifens`, `data`, `quill`).
//
//  É o ESPELHO de `relay/src/template.js`: o relay renderiza de verdade (push e
//  fila), este arquivo só alimenta a prévia do editor. Os dois têm que combinar
//  — `tools/templatecheck.swift` repete os mesmos casos de
//  `relay/test/template.test.js`. Mudou lá, muda aqui.
//
//  Sem SwiftUI de propósito: o gate compila só este arquivo.
//

import Foundation

// MARK: - Modelo da árvore JSON

indirect enum JSONValue {
    case string(String), number(Double), bool(Bool), null
    case array([JSONValue])
    case object([(key: String, value: JSONValue)])

    static func from(_ a: Any) -> JSONValue {
        switch a {
        case let s as String: return .string(s)
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? .bool(n.boolValue) : .number(n.doubleValue)
        case let arr as [Any]: return .array(arr.map(JSONValue.from))
        case let d as [String: Any]:
            return .object(d.sorted { $0.key < $1.key }.map { (key: $0.key, value: .from($0.value)) })
        default: return .null
        }
    }

    /// Parse de um JSON cru; qualquer erro → nil (entrada não confiável).
    static func parse(_ json: String) -> JSONValue? {
        guard let data = json.data(using: .utf8),
              let any = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        else { return nil }
        return .from(any)
    }

    /// Texto de amostra por nó (folha) — mostrado ao lado da chave na árvore.
    var sample: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        // %.0f formata inteiro sem passar por Int(Double) — que dá trap fora do range de Int
        // (payload é entrada não confiável: snowflake/epoch em ns podem exceder ~9.22e18)
        case .number(let d): return d == d.rounded() ? String(format: "%.0f", d) : String(d)
        case .bool(let b): return b ? "true" : "false"
        case .null: return "null"
        case .array(let a): return "[\(a.count)]"
        case .object(let o): return "{\(o.count)}"
        }
    }

    var isLeaf: Bool {
        switch self {
        case .array, .object: return false
        default: return true
        }
    }
}

// MARK: - Filtros (014)

/// Lista FECHADA. Um filtro por token, sem argumentos e sem encadeamento.
/// Todo filtro recebe e devolve texto; inaplicável devolve o valor cru.
enum TemplateFilters {
    static let nomes = ["semHifens", "data", "quill"]

    static func apply(_ nome: String, _ cru: String) -> String {
        switch nome {
        case "semHifens": return cru.replacingOccurrences(of: "-", with: "")
        case "data":      return data(cru)
        case "quill":     return quill(cru)
        default:          return cru          // desconhecido → cru (falha suave)
        }
    }

    /// Epoch em ms (string ou número) → `DD/MM/AAAA HH:MM` na hora local.
    /// Mesmo formato manual do relay — nada de `DateFormatter` com locale.
    private static func data(_ cru: String) -> String {
        guard let ms = Double(cru), ms.isFinite else { return cru }
        let d = Date(timeIntervalSince1970: ms / 1000)
        let c = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: d)
        guard let dia = c.day, let mes = c.month, let ano = c.year,
              let hora = c.hour, let min = c.minute else { return cru }
        let pad = { (n: Int) in String(format: "%02d", n) }
        return "\(pad(dia))/\(pad(mes))/\(ano) \(pad(hora)):\(pad(min))"
    }

    /// Delta do Quill (`{"ops":[{"insert":"…"}]}`) → texto puro.
    private static func quill(_ cru: String) -> String {
        guard let data = cru.data(using: .utf8),
              let doc = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ops = doc["ops"] as? [[String: Any]]
        else { return cru }
        return ops.map { $0["insert"] as? String ?? "" }.joined()
    }
}

// MARK: - Render

/// Substitui cada `{{ caminho }}` (ou `{{ caminho | filtro }}`) pelo valor
/// resolvido no payload; ausente/objeto/array → vazio.
func renderTemplate(_ tpl: String, _ root: JSONValue?) -> String {
    guard let regex = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+?)\\s*\\}\\}") else { return tpl }
    let ns = tpl as NSString
    let matches = regex.matches(in: tpl, range: NSRange(location: 0, length: ns.length))
    var result = tpl
    // substitui de trás pra frente (ranges anteriores não se deslocam)
    for m in matches.reversed() {
        let expr = ns.substring(with: m.range(at: 1))
        // sem maxSplits, igual ao relay: token com dois pipes usa o 1º filtro e
        // ignora o resto (não há encadeamento).
        let partes = expr.split(separator: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let cru = resolve(partes.first ?? "", root)
        // filtro sobre valor vazio não tem o que fazer — devolve vazio
        let valor = (partes.count > 1 && !cru.isEmpty)
            ? TemplateFilters.apply(partes[1], cru) : cru
        result.replaceSubrange(Range(m.range(at: 0), in: result)!, with: valor)
    }
    return result
}

/// Resolve um dot-path (com índices de array) contra a árvore. Ausente → "".
func resolve(_ path: String, _ root: JSONValue?) -> String {
    guard let node = node(at: path, root) else { return "" }
    switch node {
    case .string(let s): return s
    // %.0f evita trap de Int(Double) em número enorme vindo do payload (entrada não confiável)
    case .number(let d): return d == d.rounded() ? String(format: "%.0f", d) : String(d)
    case .bool(let b): return b ? "true" : "false"
    case .null: return ""
    // objeto/array inteiros não têm representação de texto útil no template
    case .array, .object: return ""
    }
}

/// O nó bruto num dot-path — usado por quem precisa distinguir "ausente" de
/// "presente mas vazio" (a assinatura mínima do preset, por exemplo).
func node(at path: String, _ root: JSONValue?) -> JSONValue? {
    guard var node = root else { return nil }
    for comp in path.split(separator: ".", omittingEmptySubsequences: true) {
        let key = String(comp)
        switch node {
        case .object(let pairs):
            guard let hit = pairs.first(where: { $0.key == key })?.value else { return nil }
            node = hit
        case .array(let items):
            guard let idx = Int(key), idx >= 0, idx < items.count else { return nil }
            node = items[idx]
        default:
            return nil
        }
    }
    return node
}
