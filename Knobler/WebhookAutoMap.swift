//
//  WebhookAutoMap.swift
//  Knobler
//
//  Auto-mapeamento de campos (decisão 005): quando a árvore do payload aparece e
//  o campo está VAZIO, chuta o template. Preset primeiro (a dica de forma de 006
//  casada contra a árvore, entregue inteira — prefixo fixo, caminho e filtro de
//  014), heurística de nome de chave como fallback, campo a campo.
//
//  Regras duras: campo preenchido nunca é sobrescrito; só folha string ou número
//  vira valor; array desce sempre pelo índice 0; profundidade máxima 4; ícone
//  nunca é chutado (nem existe em `TemplateField`).
//
//  Sem SwiftUI de propósito: o gate (`tools/automapcheck.swift`) compila só este
//  arquivo, o `WebhookTemplate.swift` e o `WebhookPresets.swift`.
//

import Foundation

enum AutoMap {

    // MARK: - Listas fechadas de nome de chave (005 + capturas 010/012)

    /// A ordem É a ordem de preferência dentro da mesma profundidade:
    /// `title` ganha de `name`, `textcontent` ganha de `content` (que é Quill
    /// escapado na Automação do ClickUp).
    static let chaves: [TemplateField: [String]] = [
        .title: ["title", "name", "subject", "taskname", "summary", "event", "fullname", "firstname"],
        .body:  ["body", "text", "message", "description", "textcontent", "content", "comment"],
        .url:   ["url", "link", "permalink", "htmlurl"],
        .id:    ["id", "taskid", "eventid", "webhookid", "messageid", "contactid"],
    ]

    static let profundidadeMaxima = 4

    /// minúscula, sem `_`, `-` e `.` — `full_name` e `fullName` viram `fullname`.
    static func normaliza(_ chave: String) -> String {
        chave.lowercased().filter { $0 != "_" && $0 != "-" && $0 != "." }
    }

    // MARK: - Varredura em largura

    struct Folha {
        let path: String
        let chave: String
        let valor: String
        let profundidade: Int
    }

    /// Folhas string/número em ordem de largura (mais raso primeiro). Bool e null
    /// ficam de fora: não são texto de card. Objeto e array nunca são folha — o
    /// `render()` do relay já devolve vazio pra eles.
    static func folhas(_ root: JSONValue?) -> [Folha] {
        guard let root else { return [] }
        var out: [Folha] = []
        var fila: [(no: JSONValue, path: String, chave: String, d: Int)] = [(root, "", "", 0)]
        var i = 0
        while i < fila.count {
            let (no, path, chave, d) = fila[i]
            i += 1
            let junta = { (comp: String) in path.isEmpty ? comp : path + "." + comp }
            switch no {
            case .object(let pares):
                guard d < profundidadeMaxima else { continue }
                for par in pares { fila.append((par.value, junta(par.key), par.key, d + 1)) }
            case .array(let itens):
                // só o índice 0: é o que os payloads reais exigem
                // (`history_items[0]`, `title[0].plain_text`) e evita inventar
                // critério de escolha entre elementos.
                guard d < profundidadeMaxima, let primeiro = itens.first else { continue }
                // índice não é nome de chave — a folha herda a chave do pai
                fila.append((primeiro, junta("0"), chave, d + 1))
            case .string(let s):
                out.append(Folha(path: path, chave: chave, valor: s, profundidade: d))
            case .number(let n):
                // %.0f, igual ao resolve(): Int(Double) daria trap em número enorme
                let s = n == n.rounded() ? String(format: "%.0f", n) : String(n)
                out.append(Folha(path: path, chave: chave, valor: s, profundidade: d))
            case .bool, .null:
                continue
            }
        }
        return out
    }

    // MARK: - Modo sem preset: heurística por nome de chave

    static func heuristica(_ root: JSONValue?) -> [TemplateField: String] {
        let todas = folhas(root)
        var out: [TemplateField: String] = [:]
        for (campo, lista) in chaves {
            var melhor: (profundidade: Int, ordem: Int, path: String)?
            for f in todas {
                guard let ordem = lista.firstIndex(of: normaliza(f.chave)) else { continue }
                // URL só vale se o valor for URL de verdade
                if campo == .url && !f.valor.hasPrefix("http") { continue }
                if let m = melhor, (m.profundidade, m.ordem) <= (f.profundidade, ordem) { continue }
                melhor = (f.profundidade, ordem, f.path)
            }
            if let melhor { out[campo] = "{{\(melhor.path)}}" }
        }
        return out
    }

    // MARK: - Modo com preset: a dica de forma casada contra a árvore

    /// Os caminhos de um template, já sem o filtro de 014.
    static func caminhos(_ tpl: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: "\\{\\{\\s*([^}]+?)\\s*\\}\\}") else { return [] }
        let ns = tpl as NSString
        return re.matches(in: tpl, range: NSRange(location: 0, length: ns.length)).map {
            ns.substring(with: $0.range(at: 1))
                .split(separator: "|")[0].trimmingCharacters(in: .whitespaces)
        }
    }

    /// A dica casa quando TODOS os seus caminhos existem na árvore como folha —
    /// inclusive o caso de dois tokens no mesmo campo (a URL do GHL de workflow).
    ///
    /// ponytail: casa caminho LITERAL. As dicas com buraco
    /// (`properties.<sua propriedade>.title[0].plain_text`) só existem no preset
    /// do Notion, que está travado em 011/022 — quando ele entrar, é aqui que a
    /// forma passa a andar a árvore procurando a ocorrência mais rasa.
    static func casa(_ template: String, _ root: JSONValue?) -> Bool {
        let cs = caminhos(template)
        return !cs.isEmpty && cs.allSatisfy { node(at: $0, root)?.isLeaf == true }
    }

    // MARK: - O chute

    /// Sugestão para os campos de `vazios`, e só pra eles. Preset primeiro,
    /// heurística no que sobrou. Dicionário vazio = nada casou (o editor convida
    /// a clicar na árvore).
    static func sugerir(arvore: JSONValue?,
                        preset: WebhookPreset?,
                        vazios: Set<TemplateField>) -> [TemplateField: String] {
        guard arvore != nil, !vazios.isEmpty else { return [:] }
        var out: [TemplateField: String] = [:]
        if let preset {
            for dica in preset.dicas where vazios.contains(dica.campo) {
                if casa(dica.template, arvore) { out[dica.campo] = dica.template }
            }
        }
        for (campo, tpl) in heuristica(arvore) where vazios.contains(campo) && out[campo] == nil {
            out[campo] = tpl
        }
        return out
    }
}
