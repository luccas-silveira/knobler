//
//  exemplocheck.swift
//  Colar JSON de exemplo (008): o botão é um clique só, então a lógica que
//  decide "isto é árvore / isto é lixo copiado" e a precedência
//  "payload real vence o exemplo" precisam de gate — o editor é HSplitView e
//  não renderiza no harness de snapshot.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookTemplate.swift Knobler/WebhookExemplo.swift tools/exemplocheck.swift \
//    -o /tmp/exemplocheck && /tmp/exemplocheck
//

import Foundation

var falhas = 0
func check(_ ok: Bool, _ msg: @autoclosure () -> String) {
    guard !ok else { return }
    FileHandle.standardError.write("✗ \(msg())\n".data(using: .utf8)!)
    falhas += 1
}

private func arvore(_ r: ResultadoDeColagem) -> JSONValue? {
    if case .arvore(let v) = r { return v }
    return nil
}

private func trechoDe(_ r: ResultadoDeColagem) -> String? {
    if case .invalido(let t) = r { return t }
    return nil
}

private func ehVazio(_ r: ResultadoDeColagem) -> Bool {
    if case .vazio = r { return true }
    return false
}

@main enum Gate {
    static func main() {
        // --- o que vira árvore ---
        let obj = arvore(ExemploColado.avaliar(#"{"task":{"name":"Revisar"}}"#))
        check(resolve("task.name", obj) == "Revisar", "objeto colado vira árvore navegável")
        check(arvore(ExemploColado.avaliar("  \n [1,2] ")) != nil,
              "array colado vale, e espaço em volta não atrapalha")

        // --- o que não vira ---
        check(ehVazio(ExemploColado.avaliar(nil)), "clipboard sem texto = vazio")
        check(ehVazio(ExemploColado.avaliar("   \n ")), "só espaço em branco = vazio")
        check(trechoDe(ExemploColado.avaliar("<html><body>Webhook")) != nil,
              "HTML copiado por engano é inválido, não árvore")
        check(trechoDe(ExemploColado.avaliar(#"{"task": }"#)) != nil, "JSON quebrado é inválido")
        check(trechoDe(ExemploColado.avaliar("42")) != nil,
              "fragmento JSON solto não vira árvore — só objeto ou array")

        // --- trecho do que foi lido (o aviso inline) ---
        check(ExemploColado.trecho("<html>\n  <body>") == "<html> <body>",
              "quebras e indentação colapsam num espaço só")
        let longo = ExemploColado.trecho(String(repeating: "x", count: 200))
        check(longo.count == ExemploColado.limiteDoTrecho + 1 && longo.hasSuffix("…"),
              "corta em \(ExemploColado.limiteDoTrecho) caracteres mais reticências")
        check(ExemploColado.trecho("curto") == "curto", "texto curto sai inteiro, sem reticências")
        check(ExemploColado.mensagemDeErro("<html>").contains("<html>"),
              "a mensagem mostra o que foi lido")
        check(ExemploColado.mensagemDeErro("") != ExemploColado.mensagemDeErro("x"),
              "clipboard vazio tem mensagem própria")

        // --- precedência: o real vence o exemplo, e a faixa conta isso ---
        check(FonteDaArvore.exemplo.comPayloadReal == .realTrocouExemplo,
              "payload real por cima de exemplo avisa que trocou")
        check(FonteDaArvore.nenhuma.comPayloadReal == .real, "sem exemplo, o real entra calado")
        check(FonteDaArvore.realTrocouExemplo.comPayloadReal == .real,
              "segundo payload real limpa o aviso de troca")
        check(FonteDaArvore.nenhuma.faixa == nil && FonteDaArvore.real.faixa == nil,
              "árvore real (ou nenhuma) não tem faixa")
        check(FonteDaArvore.exemplo.faixa != nil && FonteDaArvore.realTrocouExemplo.faixa != nil,
              "exemplo e troca têm faixa persistente")
        check(FonteDaArvore.exemplo.podeDescartar, "exemplo dá pra descartar")
        check(!FonteDaArvore.real.podeDescartar && !FonteDaArvore.realTrocouExemplo.podeDescartar,
              "payload real não se descarta pela faixa")

        if falhas > 0 {
            FileHandle.standardError.write("\(falhas) falha(s)\n".data(using: .utf8)!)
            exit(1)
        }
        print("exemplocheck ok")
    }
}
