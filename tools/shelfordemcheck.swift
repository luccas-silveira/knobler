//
//  shelfordemcheck.swift
//  Gate do modelo e da ordem da prateleira (tickets 003 e 004).
//
//  Cobre as três regras de ordem (o novo entra na frente, o repetido sobe em
//  vez de duplicar, o excesso sai pelo fim), o dedupe entre entradas, e o
//  round-trip da persistência junto da migração do formato plano.
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

/// Os caminhos de cada entrada, que é o que as asserções comparam.
private func forma(_ entradas: [ShelfEntry]) -> [[String]] {
    entradas.map { $0.urls.map(\.path) }
}

private let tudoExiste: (String) -> Bool = { _ in true }

@main
enum ShelfOrdemCheck {
    static func main() {
        print("shelfordemcheck")
        ordem()
        pilhas()
        persistencia()

        if falhas > 0 {
            print("shelfordemcheck: \(falhas) falha(s)")
            exit(1)
        }
        print("shelfordemcheck: ok")
    }

    /// As regras do 003, na forma nova.
    static func ordem() {
        let a = u("/tmp/a.txt"), b = u("/tmp/b.txt"), c = u("/tmp/c.txt")

        let um = ShelfOrdem.inserir([a], em: [], capacidade: 8)
        check(forma(um) == [["/tmp/a.txt"]], "primeiro item entra")

        let dois = ShelfOrdem.inserir([b], em: um, capacidade: 8)
        check(forma(dois) == [["/tmp/b.txt"], ["/tmp/a.txt"]], "o novo entra na frente")

        let tres = ShelfOrdem.inserir([a], em: ShelfOrdem.inserir([c], em: dois, capacidade: 8),
                                      capacidade: 8)
        check(forma(tres) == [["/tmp/a.txt"], ["/tmp/c.txt"], ["/tmp/b.txt"]],
              "repetido sobe pra primeira posição em vez de duplicar")

        // pasta volta do UserDefaults sem a barra final que o Finder manda
        let comBarra = URL(fileURLWithPath: "/tmp/pasta", isDirectory: true)
        let semBarra = URL(fileURLWithPath: "/tmp/pasta")
        let pasta = ShelfOrdem.inserir([semBarra],
                                       em: ShelfOrdem.inserir([comBarra], em: [ShelfEntry([a])],
                                                              capacidade: 8),
                                       capacidade: 8)
        check(pasta.count == 2, "pasta re-arrastada depois do restart não duplica")
        check(pasta.first?.capa.path == "/tmp/pasta", "e sobe pra frente")

        // enche além da capacidade: o mais antigo sai pelo fim
        var cheia: [ShelfEntry] = []
        for i in 0..<10 { cheia = ShelfOrdem.inserir([u("/tmp/\(i)")], em: cheia, capacidade: 8) }
        check(cheia.count == 8, "capacidade respeitada")
        check(cheia.first?.capa.path == "/tmp/9", "o último a entrar está na frente")
        check(cheia.last?.capa.path == "/tmp/2", "o excesso saiu pelo fim (os dois mais antigos)")

        check(ShelfOrdem.inserir([], em: dois, capacidade: 8) == dois,
              "drop sem nenhum arquivo não mexe na prateleira")
    }

    /// O modelo do 004: a vaga que é pilha, e o dedupe entre entradas.
    static func pilhas() {
        let solto = ShelfEntry([u("/tmp/um")])
        check(!solto.isPilha, "entrada de um arquivo não é pilha")
        check(ShelfEntry([u("/tmp/um"), u("/tmp/dois")]).isPilha, "entrada de dois é pilha")

        // capacidade conta ENTRADAS, não arquivos
        var vagas: [ShelfEntry] = []
        for i in 0..<8 {
            vagas = ShelfOrdem.inserir([u("/tmp/\(i)-a"), u("/tmp/\(i)-b"), u("/tmp/\(i)-c")],
                                       em: vagas, capacidade: 8)
        }
        check(vagas.count == 8, "oito pilhas de três ocupam as oito vagas")
        check(vagas.flatMap(\.urls).count == 24, "e carregam 24 arquivos")
        let nona = ShelfOrdem.inserir([u("/tmp/nova")], em: vagas, capacidade: 8)
        check(nona.count == 8 && nona.last?.capa.path == "/tmp/1-a",
              "a nona entrada derruba a última")

        // dedupe entre entradas: o arquivo sai da pilha em que estava
        let p = u("/tmp/p"), x = u("/tmp/x"), q = u("/tmp/q"), r = u("/tmp/r")
        let arrancado = ShelfOrdem.inserir([x], em: [ShelfEntry([p, x, q]), ShelfEntry([r])],
                                           capacidade: 8)
        check(forma(arrancado) == [["/tmp/x"], ["/tmp/p", "/tmp/q"], ["/tmp/r"]],
              "re-soltar um arquivo de dentro da pilha tira ele de lá")

        let sobrouUm = ShelfOrdem.inserir([x], em: [ShelfEntry([p, x])], capacidade: 8)
        check(sobrouUm.count == 2 && !sobrouUm[1].isPilha,
              "pilha que sobra com um arquivo deixa de ser pilha")

        let esvaziou = ShelfOrdem.inserir([x], em: [ShelfEntry([x])], capacidade: 8)
        check(forma(esvaziou) == [["/tmp/x"]], "entrada que esvazia some em vez de ficar vazia")

        let noDrop = ShelfOrdem.inserir([p, p, q], em: [], capacidade: 8)
        check(forma(noDrop) == [["/tmp/p", "/tmp/q"]], "repetido dentro do próprio drop entra uma vez")
    }

    static func persistencia() {
        let entradas = [ShelfEntry([u("/tmp/a"), u("/tmp/b")]), ShelfEntry([u("/tmp/c")])]
        let codificado = ShelfOrdem.codificar(entradas)
        check(codificado == [["/tmp/a", "/tmp/b"], ["/tmp/c"]], "codifica como array de arrays")
        check(ShelfOrdem.decodificar(codificado, capacidade: 8, existe: tudoExiste) == entradas,
              "round-trip devolve as mesmas entradas, na mesma ordem e agrupamento")

        // formato plano do 003 e anteriores: vira entrada de um arquivo, invertido
        let migrado = ShelfOrdem.decodificar(["/tmp/velho", "/tmp/meio", "/tmp/novo"],
                                             capacidade: 8, existe: tudoExiste)
        check(forma(migrado) == [["/tmp/novo"], ["/tmp/meio"], ["/tmp/velho"]],
              "o array plano legado migra invertido: o mais novo vai pra frente")
        check(migrado.allSatisfy { !$0.isPilha }, "e cada caminho vira uma entrada de um arquivo")

        let vivo: (String) -> Bool = { $0 != "/tmp/morto" }
        check(forma(ShelfOrdem.decodificar([["/tmp/a", "/tmp/morto"]], capacidade: 8, existe: vivo))
                == [["/tmp/a"]],
              "caminho que sumiu do disco é filtrado da pilha")
        check(ShelfOrdem.decodificar([["/tmp/a", "/tmp/morto"]], capacidade: 8, existe: vivo)
                .first?.isPilha == false,
              "e a pilha que sobra com um arquivo deixa de ser pilha")
        check(ShelfOrdem.decodificar([["/tmp/morto"], ["/tmp/a"]], capacidade: 8, existe: vivo)
                .count == 1,
              "entrada que fica sem nenhum arquivo vivo some")

        check(ShelfOrdem.decodificar(nil, capacidade: 8, existe: tudoExiste).isEmpty,
              "chave ausente dá prateleira vazia")
        check(ShelfOrdem.decodificar([], capacidade: 8, existe: tudoExiste).isEmpty,
              "array vazio dá prateleira vazia")
        check(ShelfOrdem.decodificar(["a", ["b"]] as [Any], capacidade: 8, existe: tudoExiste)
                .isEmpty,
              "lixo misto dá prateleira vazia em vez de crash")

        let demais = (0..<30).map { ["/tmp/\($0)"] }
        check(ShelfOrdem.decodificar(demais, capacidade: 8, existe: tudoExiste).count == 8,
              "a leitura também corta na capacidade (um defaults write à mão pode escrever 30)")
    }
}
