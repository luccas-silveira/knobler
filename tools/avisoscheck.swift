//
//  avisoscheck.swift — gate do canal de avisos do desenvolvedor.
//
//  Cobre o filtro puro (`DevAvisos.aplicaveis`) e valida o `avisos.json` do
//  próprio repo: um aviso com typo vira CI vermelha em vez de card errado na
//  base inteira. Publicar aviso é irreversível (o app já baixou; corrigir
//  significa publicar outro id), então o gate é a única rede de proteção.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/Updater.swift Knobler/DevAvisos.swift tools/avisoscheck.swift \
//    -o /tmp/avisoscheck && /tmp/avisoscheck
//

import Foundation

private func feed(_ avisos: String, schema: Int = 1) -> Data {
    Data(#"{"versaoSchema":\#(schema),"avisos":[\#(avisos)]}"#.utf8)
}

private let simples = #"{"id":"a","titulo":"Oi","corpo":"Corpo"}"#

private var falhas: [String] = []
private func check(_ nome: String, _ ok: Bool) {
    if !ok { falhas.append(nome) }
}

@main
struct AvisosCheck {
    static func main() {
        let versao = "0.19.0"

        // --- básico ---------------------------------------------------------
        check("aviso simples passa",
              DevAvisos.aplicaveis(json: feed(simples), versaoInstalada: versao,
                                   vistos: [], ligado: true).map(\.id) == ["a"])

        check("schema desconhecido descarta o arquivo inteiro",
              DevAvisos.aplicaveis(json: feed(simples, schema: 2), versaoInstalada: versao,
                                   vistos: [], ligado: true).isEmpty)

        check("JSON malformado não derruba nada",
              DevAvisos.aplicaveis(json: Data("{nada".utf8), versaoInstalada: versao,
                                   vistos: [], ligado: true).isEmpty)

        check("id já visto não reaparece",
              DevAvisos.aplicaveis(json: feed(simples), versaoInstalada: versao,
                                   vistos: ["a"], ligado: true).isEmpty)

        check("id duplicado no arquivo entra uma vez só",
              DevAvisos.aplicaveis(json: feed("\(simples),\(simples)"), versaoInstalada: versao,
                                   vistos: [], ligado: true).count == 1)

        check("título vazio é descartado",
              DevAvisos.aplicaveis(json: feed(#"{"id":"a","titulo":"  ","corpo":"c"}"#),
                                   versaoInstalada: versao, vistos: [], ligado: true).isEmpty)

        // --- toggle x crítico ------------------------------------------------
        check("toggle off silencia aviso normal",
              DevAvisos.aplicaveis(json: feed(simples), versaoInstalada: versao,
                                   vistos: [], ligado: false).isEmpty)

        let critico = #"{"id":"c","titulo":"Falha","corpo":"x","prioridade":"critica"}"#
        check("toggle off NÃO silencia crítico",
              DevAvisos.aplicaveis(json: feed(critico), versaoInstalada: versao,
                                   vistos: [], ligado: false).first?.critico == true)

        check("prioridade desconhecida não vira crítico",
              DevAvisos.aplicaveis(json: feed(#"{"id":"c","titulo":"t","corpo":"x","prioridade":"URGENTE"}"#),
                                   versaoInstalada: versao, vistos: [], ligado: false).isEmpty)

        // --- faixa de versão --------------------------------------------------
        check("sem faixa vale pra todos",
              DevAvisos.dentroDaFaixa(instalada: "0.19.0", min: nil, max: nil))
        check("min inclusivo", DevAvisos.dentroDaFaixa(instalada: "0.19.0", min: "0.19.0", max: nil))
        check("max inclusivo", DevAvisos.dentroDaFaixa(instalada: "0.19.0", min: nil, max: "0.19.0"))
        check("abaixo do min não recebe",
              !DevAvisos.dentroDaFaixa(instalada: "0.18.0", min: "0.19.0", max: nil))
        check("acima do max não recebe",
              !DevAvisos.dentroDaFaixa(instalada: "0.20.0", min: nil, max: "0.19.0"))
        check("0.10.0 > 0.9.0 (comparação numérica, não de string)",
              DevAvisos.dentroDaFaixa(instalada: "0.10.0", min: "0.9.0", max: nil))
        // isNewer devolve false pra lixo: sem validar o formato, um typo na
        // faixa viraria aviso pra toda a base.
        check("faixa malformada não vale pra ninguém",
              !DevAvisos.dentroDaFaixa(instalada: "0.19.0", min: "0.19", max: nil))
        check("versão instalada malformada não recebe faixa",
              !DevAvisos.dentroDaFaixa(instalada: "sei-la", min: "0.19.0", max: nil))

        // --- tetos -------------------------------------------------------------
        let onze = (1...11).map { #"{"id":"a\#($0)","titulo":"t","corpo":"c"}"# }.joined(separator: ",")
        check("11 avisos viram 10",
              DevAvisos.aplicaveis(json: feed(onze), versaoInstalada: versao,
                                   vistos: [], ligado: true).count == DevAvisos.maxAvisos)

        let longo = String(repeating: "a", count: 500)
        let grande = DevAvisos.aplicaveis(
            json: feed(#"{"id":"a","titulo":"\#(longo)","corpo":"\#(longo)"}"#),
            versaoInstalada: versao, vistos: [], ligado: true).first
        check("título longo trunca sem sumir", grande?.titulo.count == DevAvisos.maxTitulo)
        check("corpo longo trunca sem sumir", grande?.corpo.count == DevAvisos.maxCorpo)

        var gordo = Data(#"{"versaoSchema":1,"avisos":[],"lixo":""#.utf8)
        gordo.append(Data(String(repeating: "x", count: DevAvisos.maxBytes).utf8))
        gordo.append(Data(#""}"#.utf8))
        check("arquivo acima do teto de bytes é descartado",
              DevAvisos.aplicaveis(json: gordo, versaoInstalada: versao,
                                   vistos: [], ligado: true).isEmpty)

        // --- ações --------------------------------------------------------------
        func acao(_ url: String) -> [AvisoAcao] {
            DevAvisos.saneadas([AvisoAcao(titulo: "Abrir", url: url)])
        }
        check("https passa", acao("https://knobler.app/x").count == 1)
        check("http é rejeitado", acao("http://knobler.app").isEmpty)
        check("file:// é rejeitado", acao("file:///etc/passwd").isEmpty)
        check("javascript: é rejeitado", acao("javascript:alert(1)").isEmpty)
        check("app scheme é rejeitado", acao("knobler://x").isEmpty)
        check("https sem host é rejeitado", acao("https://").isEmpty)
        check("ação sem título é rejeitada",
              DevAvisos.saneadas([AvisoAcao(titulo: " ", url: "https://a.com")]).isEmpty)
        check("máximo de 2 botões",
              DevAvisos.saneadas((1...5).map { AvisoAcao(titulo: "b\($0)", url: "https://a.com") })
                .count == DevAvisos.maxAcoes)

        // --- vistos ---------------------------------------------------------------
        check("vistos não duplica id",
              DevAvisos.vistosAtualizados(["a"], novos: ["a", "b"]) == ["a", "b"])
        let muitos = (1...DevAvisos.maxVistos).map { "v\($0)" }
        let podados = DevAvisos.vistosAtualizados(muitos, novos: ["novo"])
        check("vistos poda os mais antigos",
              podados.count == DevAvisos.maxVistos && podados.last == "novo"
                && podados.first == "v2")

        // --- o avisos.json de verdade ------------------------------------------------
        // O gate roda da raiz do repo (check.sh faz cd). Arquivo ausente é ok:
        // significa "nenhum aviso publicado".
        let caminho = URL(fileURLWithPath: "avisos.json")
        if let dados = try? Data(contentsOf: caminho) {
            check("avisos.json cabe no teto de bytes", dados.count <= DevAvisos.maxBytes)
            // versão 0.0.0 e toggle ligado: aceita qualquer faixa que comece do zero.
            // O que importa é o arquivo ser parseável e não perder aviso por typo.
            let objeto = (try? JSONSerialization.jsonObject(with: dados)) as? [String: Any]
            let bruto = (objeto?["avisos"] as? [[String: Any]]) ?? []
            check("avisos.json declara versaoSchema atual",
                  (objeto?["versaoSchema"] as? Int) == DevAvisos.versaoSchema)
            check("avisos.json não passa do teto de avisos", bruto.count <= DevAvisos.maxAvisos)

            var ids = Set<String>()
            for item in bruto {
                let id = (item["id"] as? String) ?? ""
                check("avisos.json: id não vazio", !id.isEmpty)
                check("avisos.json: id \(id) único", ids.insert(id).inserted)
                check("avisos.json: \(id) tem título", ((item["titulo"] as? String) ?? "").isEmpty == false)
                check("avisos.json: \(id) tem corpo", ((item["corpo"] as? String) ?? "").isEmpty == false)
                if let p = item["prioridade"] as? String {
                    check("avisos.json: \(id) prioridade válida", p == "normal" || p == "critica")
                }
                for chave in ["minVersao", "maxVersao"] where item[chave] != nil {
                    let v = (item[chave] as? String) ?? ""
                    check("avisos.json: \(id) \(chave) é X.Y.Z", versionComponents(v) != nil)
                }
                if let mín = item["minVersao"] as? String, let máx = item["maxVersao"] as? String {
                    check("avisos.json: \(id) minVersao ≤ maxVersao", !isNewer(mín, than: máx))
                }
                let acoes = (item["acoes"] as? [[String: Any]]) ?? []
                check("avisos.json: \(id) no máx \(DevAvisos.maxAcoes) ações",
                      acoes.count <= DevAvisos.maxAcoes)
                for a in acoes {
                    let url = (a["url"] as? String) ?? ""
                    check("avisos.json: \(id) ação em https", url.hasPrefix("https://"))
                    check("avisos.json: \(id) ação com título",
                          ((a["titulo"] as? String) ?? "").isEmpty == false)
                }
                // truncar é silencioso em runtime: aqui a gente prefere gritar
                check("avisos.json: \(id) título cabe sem truncar",
                      ((item["titulo"] as? String) ?? "").count <= DevAvisos.maxTitulo)
                check("avisos.json: \(id) corpo cabe sem truncar",
                      ((item["corpo"] as? String) ?? "").count <= DevAvisos.maxCorpo)
            }
        }

        if falhas.isEmpty {
            print("avisoscheck ok")
        } else {
            falhas.forEach { FileHandle.standardError.write(Data("FALHOU: \($0)\n".utf8)) }
            exit(1)
        }
    }
}
