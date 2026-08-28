//
//  shelfordemcheck.swift
//  Gate da ordem da prateleira (ticket 003).
//
//  Três regras juntas: o novo entra na frente, o repetido sobe em vez de
//  duplicar, e o excesso sai pelo fim.
//
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/ShelfOrdem.swift tools/shelfordemcheck.swift \
//    -o /tmp/shelfordemcheck && /tmp/shelfordemcheck
//

import Foundation

private var falhas = 0

private func check(_ condicao: Bool, _ descricao: String) {
    if condicao {
        print("  ok   \(descricao)")
    } else {
        print("  FALHOU \(descricao)")
        falhas += 1
    }
}

private func u(_ p: String) -> URL { URL(fileURLWithPath: p) }

@main
enum ShelfOrdemCheck {
    static func main() {
        print("shelfordemcheck")

        let a = u("/tmp/a.txt"), b = u("/tmp/b.txt"), c = u("/tmp/c.txt")

        let um = ShelfOrdem.inserir(a, em: [], capacidade: 8)
        check(um == [a], "primeiro item entra")

        let dois = ShelfOrdem.inserir(b, em: um, capacidade: 8)
        check(dois == [b, a], "o novo entra na frente")

        let tres = ShelfOrdem.inserir(a, em: ShelfOrdem.inserir(c, em: dois, capacidade: 8),
                                      capacidade: 8)
        check(tres == [a, c, b], "repetido sobe pra primeira posição em vez de duplicar")
        check(tres.count == 3, "repetido não duplica")

        // pasta volta do UserDefaults sem a barra final que o Finder manda
        let pastaComBarra = URL(fileURLWithPath: "/tmp/pasta", isDirectory: true)
        let pastaSemBarra = URL(fileURLWithPath: "/tmp/pasta")
        let pasta = ShelfOrdem.inserir(pastaSemBarra,
                                       em: ShelfOrdem.inserir(pastaComBarra, em: [a], capacidade: 8),
                                       capacidade: 8)
        check(pasta.count == 2, "pasta re-arrastada depois do restart não duplica")
        check(pasta.first?.path == "/tmp/pasta", "e sobe pra frente")

        // enche além da capacidade: o mais antigo sai pelo fim
        var cheia: [URL] = []
        for i in 0..<10 { cheia = ShelfOrdem.inserir(u("/tmp/\(i)"), em: cheia, capacidade: 8) }
        check(cheia.count == 8, "capacidade respeitada")
        check(cheia.first?.path == "/tmp/9", "o último a entrar está na frente")
        check(cheia.last?.path == "/tmp/2", "o excesso saiu pelo fim (os dois mais antigos)")

        if falhas > 0 {
            print("shelfordemcheck: \(falhas) falha(s)")
            exit(1)
        }
        print("shelfordemcheck: ok")
    }
}
