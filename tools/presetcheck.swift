//
//  presetcheck.swift
//  Guarda as invariantes dos presets de webhook — o preset é literal Swift, então
//  o que quebra aqui é conteúdo errado, não código: caminho citado que não existe
//  no exemplo embutido (o mapa sugerido sairia vazio no card), assinatura que não
//  bate com o próprio exemplo, ou duas assinaturas que se confundem.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookTemplate.swift Knobler/WebhookPresets.swift tools/presetcheck.swift \
//    -o /tmp/presetcheck && /tmp/presetcheck
//

import Foundation

var falhas = 0
func check(_ ok: Bool, _ msg: @autoclosure () -> String) {
    guard !ok else { return }
    FileHandle.standardError.write("✗ \(msg())\n".data(using: .utf8)!)
    falhas += 1
}

/// Todos os `{{caminho}}` de um template, já sem o filtro.
func caminhos(_ tpl: String) -> [String] {
    let re = try! NSRegularExpression(pattern: "\\{\\{\\s*([^}]+?)\\s*\\}\\}")
    let ns = tpl as NSString
    return re.matches(in: tpl, range: NSRange(location: 0, length: ns.length)).map {
        ns.substring(with: $0.range(at: 1))
            .split(separator: "|")[0].trimmingCharacters(in: .whitespaces)
    }
}

func filtros(_ tpl: String) -> [String] {
    let re = try! NSRegularExpression(pattern: "\\{\\{\\s*([^}]+?)\\s*\\}\\}")
    let ns = tpl as NSString
    return re.matches(in: tpl, range: NSRange(location: 0, length: ns.length)).compactMap {
        let partes = ns.substring(with: $0.range(at: 1)).split(separator: "|")
        return partes.count > 1 ? partes[1].trimmingCharacters(in: .whitespaces) : nil
    }
}

@main enum Check {
    static func main() {
        let todos = WebhookPresets.todos
        check(todos.count == 4, "esperava 4 presets (Notion espera o ticket 022), veio \(todos.count)")
        check(Set(todos.map(\.id)).count == todos.count, "ids de preset repetidos")

        var arvores: [String: JSONValue] = [:]

        for p in todos {
            let ctx = "preset \(p.id)"
            check(p.versao >= 1, "\(ctx): versão tem que ser >= 1")
            check(!p.servico.isEmpty && !p.caminho.isEmpty, "\(ctx): serviço/caminho vazio")
            check(!p.instrucao.isEmpty, "\(ctx): sem instrução — o passo Serviço fica mudo")
            check(!p.assinatura.isEmpty, "\(ctx): sem assinatura mínima")
            check(p.assinatura.count <= 2, "\(ctx): assinatura com \(p.assinatura.count) chaves — 006 pede 1 ou 2")

            guard let arvore = JSONValue.parse(p.exemplo) else {
                check(false, "\(ctx): exemplo embutido não é JSON válido"); continue
            }
            arvores[p.id] = arvore

            // a assinatura tem que reconhecer o próprio exemplo
            for chave in p.assinatura {
                check(node(at: chave, arvore) != nil,
                      "\(ctx): assinatura cita \(chave), que não existe no exemplo embutido")
            }

            check(Set(p.dicas.map(\.campo)).count == p.dicas.count, "\(ctx): duas dicas pro mesmo campo")
            check(p.dicas.contains { $0.campo == .title }, "\(ctx): sem dica de título")

            for d in p.dicas {
                check(!d.explicacao.isEmpty, "\(ctx)/\(d.campo.rawValue): dica sem explicação")
                for f in filtros(d.template) {
                    check(TemplateFilters.nomes.contains(f),
                          "\(ctx)/\(d.campo.rawValue): filtro \"\(f)\" fora da lista fechada de 014")
                }
                guard p.mapaAplicavelSemPayload else { continue }
                // mapa aplicável antes do primeiro POST = caminho literal, então
                // ele tem que existir no exemplo e render não-vazio.
                for c in caminhos(d.template) {
                    check(node(at: c, arvore) != nil,
                          "\(ctx)/\(d.campo.rawValue): caminho \(c) não existe no exemplo embutido")
                }
                check(!renderTemplate(d.template, arvore).isEmpty,
                      "\(ctx)/\(d.campo.rawValue): o mapa sugerido renderiza vazio no próprio exemplo")
            }
        }

        // Assinaturas não podem colidir: o exemplo de um caminho não pode ser
        // reconhecido por outro (senão o assistente sugere o preset errado).
        for p in todos {
            guard let arvore = arvores[p.id] else { continue }
            let reconhecido = WebhookPresets.reconhece(arvore)?.id
            check(reconhecido == p.id,
                  "preset \(p.id): o próprio exemplo é reconhecido como \(reconhecido ?? "nenhum")")
        }

        // Payload que não é de ninguém não pode casar por acidente.
        check(WebhookPresets.reconhece(JSONValue.parse(#"{"foo":1}"#)) == nil,
              "payload genérico casou com algum preset")
        check(WebhookPresets.reconhece(nil) == nil, "payload ausente casou com algum preset")

        if falhas > 0 {
            FileHandle.standardError.write("presetcheck: \(falhas) falha(s)\n".data(using: .utf8)!)
            exit(1)
        }
        print("presetcheck: ok (\(todos.count) presets)")
    }
}
