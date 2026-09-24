//
//  tools/corescheck.swift — self-check do histórico de cores do conta-gotas.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/CoresRecentes.swift tools/corescheck.swift -o /tmp/corescheck && /tmp/corescheck
import Foundation

@main
struct CoresCheck {
    static func main() {
        var l: [String] = []
        for i in 0..<10 { l = CoresRecentes.registrar(String(format: "#%06X", i), em: l) }
        precondition(l.count == 8 && l.first == "#000009", "limite: \(l)")
        l = CoresRecentes.registrar("#000005", em: l)
        precondition(l.first == "#000005" && l.filter { $0 == "#000005" }.count == 1, "dedupe: \(l)")
        print("corescheck ok")
    }
}
