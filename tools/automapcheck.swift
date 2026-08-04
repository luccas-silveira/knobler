//
//  automapcheck.swift
//  Guarda as regras do auto-mapeamento (005): busca por largura, só folhas
//  string/número, array pelo índice 0, profundidade máxima 4, ícone nunca
//  chutado, campo preenchido nunca sobrescrito, e o preset vencendo a heurística
//  quando a dica casa contra a árvore.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookTemplate.swift Knobler/WebhookPresets.swift Knobler/WebhookAutoMap.swift \
//    tools/automapcheck.swift -o /tmp/automapcheck && /tmp/automapcheck
//

import Foundation

var falhas = 0
func check(_ ok: Bool, _ msg: @autoclosure () -> String) {
    guard !ok else { return }
    FileHandle.standardError.write("✗ \(msg())\n".data(using: .utf8)!)
    falhas += 1
}

func arvore(_ json: String) -> JSONValue {
    guard let v = JSONValue.parse(json) else { fatalError("JSON do teste inválido") }
    return v
}

@main enum Check {
  static func main() {
    let todos: Set<TemplateField> = Set(TemplateField.allCases)

    // MARK: - Heurística: nomes de chave

    let simples = arvore("""
    { "name": "Tarefa X", "description": "corpo do card",
      "url": "https://example.com/t/1", "id": "abc123" }
    """)
    let h1 = AutoMap.sugerir(arvore: simples, preset: nil, vazios: todos)
    check(h1[.title] == "{{name}}", "título por `name`: \(h1[.title] ?? "nil")")
    check(h1[.body] == "{{description}}", "corpo por `description`: \(h1[.body] ?? "nil")")
    check(h1[.url] == "{{url}}", "URL por `url`: \(h1[.url] ?? "nil")")
    check(h1[.id] == "{{id}}", "id por `id`: \(h1[.id] ?? "nil")")

    // normalização: full_name/fullName casam com `fullname`
    let ghl = arvore("""
    { "full_name": "Knobler Captura012", "contact_id": "gxGfB9wxEy3anxbHB4nT",
      "location": { "id": "t9Ww7bY1xJJ6ThFHZVPC" } }
    """)
    let h2 = AutoMap.sugerir(arvore: ghl, preset: nil, vazios: todos)
    check(h2[.title] == "{{full_name}}", "normalização `full_name`: \(h2[.title] ?? "nil")")
    // `contact_id` (raso demais? não: está na raiz) vence `location.id`, que é mais fundo
    check(h2[.id] == "{{contact_id}}", "id mais raso: \(h2[.id] ?? "nil")")

    // ordem da lista desempata na mesma profundidade: title > name, textcontent > content
    let ordem = arvore("""
    { "name": "N", "title": "T", "content": "{\\"ops\\":[]}", "text_content": "limpo" }
    """)
    let h3 = AutoMap.sugerir(arvore: ordem, preset: nil, vazios: todos)
    check(h3[.title] == "{{title}}", "`title` ganha de `name`: \(h3[.title] ?? "nil")")
    check(h3[.body] == "{{text_content}}", "`text_content` ganha de `content`: \(h3[.body] ?? "nil")")

    // URL exige valor começando com http
    let urlFalsa = arvore("{ \"url\": \"nao-e-url\", \"link\": \"https://ok/1\" }")
    let h4 = AutoMap.sugerir(arvore: urlFalsa, preset: nil, vazios: todos)
    check(h4[.url] == "{{link}}", "URL só com valor http: \(h4[.url] ?? "nil")")

    // bool/null/objeto/array nunca viram valor de campo
    let naoFolhas = arvore("{ \"title\": true, \"body\": null, \"url\": {}, \"id\": [] }")
    check(AutoMap.sugerir(arvore: naoFolhas, preset: nil, vazios: todos).isEmpty,
          "bool/null/objeto/array não podem virar campo")

    // array desce só pelo índice 0
    let arr = arvore("""
    { "history_items": [ { "comment": { "text_content": "primeiro" } },
                         { "comment": { "text_content": "segundo" } } ] }
    """)
    let h5 = AutoMap.sugerir(arvore: arr, preset: nil, vazios: todos)
    check(h5[.body] == "{{history_items.0.comment.text_content}}",
          "array pelo índice 0: \(h5[.body] ?? "nil")")

    // profundidade máxima 4
    let fundo = arvore("{ \"a\": { \"b\": { \"c\": { \"d\": { \"title\": \"fundo demais\" } } } } }")
    check(AutoMap.sugerir(arvore: fundo, preset: nil, vazios: todos)[.title] == nil,
          "profundidade 5 não deve ser chutada")
    let limite = arvore("{ \"a\": { \"b\": { \"c\": { \"title\": \"no limite\" } } } }")
    check(AutoMap.sugerir(arvore: limite, preset: nil, vazios: todos)[.title] == "{{a.b.c.title}}",
          "profundidade 4 deve ser chutada")

    // ícone nunca é chutado — não existe como campo mapeável
    check(!TemplateField.allCases.contains { $0.rawValue == "icon" },
          "TemplateField não pode ter ícone (005: ícone nunca é chutado)")

    // MARK: - Campo preenchido nunca é sobrescrito

    let parcial = AutoMap.sugerir(arvore: simples, preset: nil, vazios: [.body, .id])
    check(parcial[.title] == nil && parcial[.url] == nil, "campo fora de `vazios` não pode ser sugerido")
    check(parcial[.body] != nil && parcial[.id] != nil, "campo vazio deveria ter sugestão")
    check(AutoMap.sugerir(arvore: simples, preset: nil, vazios: []).isEmpty,
          "nenhum campo vazio = nenhuma sugestão")
    check(AutoMap.sugerir(arvore: nil, preset: nil, vazios: todos).isEmpty,
          "sem árvore = nenhuma sugestão")

    // MARK: - Nada casa

    let nada = arvore("{ \"foo\": \"bar\", \"baz\": 1 }")
    check(AutoMap.sugerir(arvore: nada, preset: nil, vazios: todos).isEmpty,
          "payload irreconhecível deve sair vazio (sem erro)")

    // MARK: - Preset vence a heurística quando a dica casa

    for preset in WebhookPresets.todos {
        let ex = arvore(preset.exemplo)
        let s = AutoMap.sugerir(arvore: ex, preset: preset, vazios: todos)
        for dica in preset.dicas {
            check(s[dica.campo] == dica.template,
                  "\(preset.id): \(dica.campo.rawValue) deveria vir do preset — veio \(s[dica.campo] ?? "nil")")
        }
    }

    // dica que NÃO casa cai na heurística, não bloqueia o campo
    let soTitulo = arvore("{ \"name\": \"Só isto\" }")
    let mix = AutoMap.sugerir(arvore: soTitulo, preset: WebhookPresets.clickupAutomacao, vazios: todos)
    check(mix[.title] == "{{name}}",
          "dica que não casa deve cair na heurística: \(mix[.title] ?? "nil")")
    check(mix[.url] == nil, "dica que não casa e sem heurística deixa o campo vazio")

    // dois tokens no mesmo campo: a URL do GHL de workflow só casa com os dois
    check(AutoMap.casa("https://x/{{location.id}}/c/{{contact_id}}", ghl),
          "template de dois tokens deveria casar")
    check(!AutoMap.casa("https://x/{{location.id}}/c/{{nao_existe}}", ghl),
          "template com um token ausente não pode casar")

    if falhas == 0 { print("automapcheck ok") }
    exit(falhas == 0 ? 0 : 1)

  }
}
