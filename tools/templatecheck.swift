//
//  templatecheck.swift
//  Espelho explícito de `relay/test/template.test.js` — o motor de prévia do app
//  tem que render igual ao relay, senão a prévia mente.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookTemplate.swift tools/templatecheck.swift \
//    -o /tmp/templatecheck && /tmp/templatecheck
//

import Foundation

var falhas = 0
func eq(_ got: String, _ want: String, _ nome: String) {
    if got == want { return }
    FileHandle.standardError.write("✗ \(nome): esperado \"\(want)\", veio \"\(got)\"\n".data(using: .utf8)!)
    falhas += 1
}

@main enum Check {
    static func main() {
        let p = JSONValue.parse("""
        {"title":"Deploy","repo":{"name":"knobler"},
         "commits":[{"msg":"a"},{"msg":"b"}],"ok":true,"n":3}
        """)

        // ---- casos base (idênticos aos do relay) ----
        eq(resolve("repo.name", p), "knobler", "resolve dot-path")
        eq(resolve("commits.1.msg", p), "b", "resolve índice de array")
        eq(resolve("nao.existe", p), "", "resolve ausente")

        eq(renderTemplate("{{repo.name}}: {{commits.0.msg}}", p), "knobler: a", "texto + variáveis")
        eq(renderTemplate("Olá {{title}} ({{n}})", p), "Olá Deploy (3)", "texto livre")

        eq(renderTemplate("x{{nao.existe}}y", p), "xy", "ausente vira vazio")
        eq(renderTemplate("{{repo}}", p), "", "objeto vira vazio")
        eq(renderTemplate("{{commits}}", p), "", "array vira vazio")
        eq(renderTemplate("sem variavel", p), "sem variavel", "texto puro passa")

        eq(renderTemplate("{{ok}}/{{n}}", p), "true/3", "bool e número viram string")
        eq(renderTemplate("{{  repo.name  }}", p), "knobler", "espaços tolerados")

        // ---- filtros (014) ----
        let epoch = 1754320000000.0
        let f = JSONValue.parse("""
        {"id":"1a2b3c4d-5e6f-7788-99aa-bbccddeeff00",
         "date":"1754320000000","dateNum":1754320000000,
         "after":"{\\"ops\\":[{\\"insert\\":\\"linha um\\\\n\\"},{\\"insert\\":\\"linha dois\\"}]}",
         "texto":"nada a ver","obj":{"a":1}}
        """)
        let idCru = "1a2b3c4d-5e6f-7788-99aa-bbccddeeff00"

        eq(renderTemplate("https://www.notion.so/{{id | semHifens}}", f),
           "https://www.notion.so/1a2b3c4d5e6f778899aabbccddeeff00", "semHifens")
        eq(renderTemplate("{{texto|semHifens}}", f), "nada a ver", "semHifens sem hífen")

        // mesmo formato manual do relay: DD/MM/AAAA HH:MM na hora local
        let c = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute],
                                                from: Date(timeIntervalSince1970: epoch / 1000))
        let pad = { (n: Int) in String(format: "%02d", n) }
        let esperado = "\(pad(c.day!))/\(pad(c.month!))/\(c.year!) \(pad(c.hour!)):\(pad(c.minute!))"
        eq(renderTemplate("{{date | data}}", f), esperado, "data de string")
        eq(renderTemplate("{{dateNum | data}}", f), esperado, "data de número")

        eq(renderTemplate("{{after | quill}}", f), "linha um\nlinha dois", "quill")

        eq(renderTemplate("{{texto | jamaisExistiu}}", f), "nada a ver", "filtro desconhecido")
        eq(renderTemplate("{{id | SEMHIFENS}}", f), idCru, "lista fechada é sensível a caixa")

        eq(renderTemplate("{{texto | data}}", f), "nada a ver", "data inaplicável")
        eq(renderTemplate("{{texto | quill}}", f), "nada a ver", "quill inaplicável")
        eq(renderTemplate("{{id | quill}}", f), idCru, "quill em não-JSON")
        eq(renderTemplate("{{obj | semHifens}}", f), "", "objeto continua vazio")
        eq(renderTemplate("{{nao.existe | data}}", f), "", "ausente com filtro continua vazio")

        // ---- específicos do app ----
        eq(renderTemplate("{{title}}", nil), "", "sem payload nenhum, tudo vazia")
        // dois tokens no mesmo campo: a URL do GHL de workflow depende disso
        let ghl = JSONValue.parse(#"{"contact_id":"abc","location":{"id":"loc1"}}"#)
        eq(renderTemplate("https://app.gohighlevel.com/v2/location/{{location.id}}/contacts/detail/{{contact_id}}", ghl),
           "https://app.gohighlevel.com/v2/location/loc1/contacts/detail/abc", "dois tokens no mesmo campo")

        if falhas > 0 {
            FileHandle.standardError.write("templatecheck: \(falhas) falha(s)\n".data(using: .utf8)!)
            exit(1)
        }
        print("templatecheck: ok")
    }
}
