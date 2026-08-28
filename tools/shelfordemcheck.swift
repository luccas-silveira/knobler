//
//  shelfordemcheck.swift
//  Gate do modelo e da ordem da prateleira (tickets 003, 004 e 005).
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

        // nome de arquivo aceita quebra de linha: a identidade não pode juntar
        // os caminhos num string só, senão "a\nb" colide com a pilha de a e b
        check(ShelfEntry([u("/tmp/a\nb")]).id != ShelfEntry([u("/tmp/a"), u("/tmp/b")]).id,
              "arquivo com quebra de linha no nome não colide com a pilha equivalente")

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

        check(forma(ShelfOrdem.decodificar([["/tmp/a", "/tmp/b"], ["/tmp/a"]],
                                           capacidade: 8, existe: tudoExiste))
                == [["/tmp/a", "/tmp/b"]],
              "repetido escrito à mão na chave entra uma vez só na leitura")

        let demais = (0..<30).map { ["/tmp/\($0)"] }
        check(ShelfOrdem.decodificar(demais, capacidade: 8, existe: tudoExiste).count == 8,
              "a leitura também corta na capacidade (um defaults write à mão pode escrever 30)")

        // ticket 007 — empilhar e desempilhar à mão
        let linha = [ShelfEntry([u("/tmp/a")]), ShelfEntry([u("/tmp/b")]),
                     ShelfEntry([u("/tmp/c")])]
        let sobreB = ShelfOrdem.empilhar([u("/tmp/a")], em: linha[1], entradas: linha)
        check(forma(sobreB) == [["/tmp/b", "/tmp/a"], ["/tmp/c"]],
              "soltar A sobre B junta os dois na posição de B, e a entrada de A some")

        let naPilha = ShelfOrdem.empilhar([u("/tmp/c")], em: sobreB[0], entradas: sobreB)
        check(forma(naPilha) == [["/tmp/b", "/tmp/a", "/tmp/c"]],
              "item solto sobre pilha entra no fim da pilha")

        check(forma(ShelfOrdem.empilhar([u("/tmp/b")], em: linha[1], entradas: linha))
                == forma(linha),
              "soltar a entrada sobre ela mesma não muda nada")

        check(forma(ShelfOrdem.empilhar([u("/tmp/a")], em: ShelfEntry([u("/tmp/z")]),
                                        entradas: linha)) == forma(linha),
              "alvo que não está mais na prateleira devolve tudo intocado")

        check(forma(ShelfOrdem.desempilhar(naPilha[0], em: naPilha, capacidade: 8))
                == [["/tmp/b"], ["/tmp/a"], ["/tmp/c"]],
              "desempilhar devolve os arquivos à linha, na posição da pilha")

        check(forma(ShelfOrdem.desempilhar(linha[0], em: linha, capacidade: 8))
                == forma(linha),
              "desempilhar item solto não faz nada")

        let vinte = ShelfEntry((0..<20).map { u("/tmp/p\($0)") })
        check(ShelfOrdem.desempilhar(vinte, em: [vinte], capacidade: 8).count == 8,
              "pilha maior que a prateleira: o excesso cai pelo fim (regra do 003)")

        // ticket 008 — tirar um arquivo de dentro da pilha, e a pilha aberta
        let tres = ShelfEntry([u("/tmp/x"), u("/tmp/y"), u("/tmp/z")])
        let comPilha = [ShelfEntry([u("/tmp/solto")]), tres]

        check(forma(ShelfOrdem.remover(u("/tmp/y"), de: tres, em: comPilha))
                == [["/tmp/solto"], ["/tmp/x", "/tmp/z"]],
              "tirar do meio da pilha preserva a posição da entrada na linha")

        let doisSobram = ShelfOrdem.remover(u("/tmp/y"), de: tres, em: comPilha)
        let umSobra = ShelfOrdem.remover(u("/tmp/x"), de: doisSobram[1], em: doisSobram)
        check(umSobra[1].isPilha == false, "pilha que sobra com um deixa de ser pilha")

        check(forma(ShelfOrdem.remover(u("/tmp/solto"), de: comPilha[0], em: comPilha))
                == [["/tmp/x", "/tmp/y", "/tmp/z"]],
              "entrada que esvazia some da linha")

        check(forma(ShelfOrdem.remover(u("/tmp/nada"), de: tres, em: comPilha))
                == forma(comPilha),
              "url que não está na entrada devolve tudo intocado")

        check(forma(ShelfOrdem.remover(u("/tmp/x"), de: ShelfEntry([u("/tmp/fora")]),
                                       em: comPilha)) == forma(comPilha),
              "alvo que não está na prateleira devolve tudo intocado")

        // a pilha aberta segue a troca de identidade que tirar um arquivo causa
        check(ShelfOrdem.pilhaAberta(tres, em: doisSobram)?.urls.count == 2,
              "a pilha aberta segue a entrada mesmo com a identidade trocada")
        check(ShelfOrdem.pilhaAberta(tres, em: ShelfOrdem.remover(u("/tmp/x"), de: tres,
                                                                 em: comPilha)) != nil,
              "tirar a CAPA não fecha a pilha: o resto dela continua lá")
        check(ShelfOrdem.pilhaAberta(tres, em: umSobra) == nil,
              "quando sobra um arquivo só, a pilha aberta fecha")
        check(ShelfOrdem.pilhaAberta(tres, em: [comPilha[0]]) == nil,
              "entrada que sumiu da prateleira fecha a pilha aberta")
        check(ShelfOrdem.pilhaAberta(nil, em: comPilha) == nil, "nil continua nil")

        // e as duas juntas: é a asserção que amarra o ticket
        var abertas: ShelfEntry? = tres
        var linhaViva = comPilha
        linhaViva = ShelfOrdem.remover(u("/tmp/z"), de: abertas!, em: linhaViva)
        abertas = ShelfOrdem.pilhaAberta(abertas, em: linhaViva)
        check(abertas?.urls.count == 2, "abriu com 3, tirou 1, segue aberta com 2")
        linhaViva = ShelfOrdem.remover(u("/tmp/y"), de: abertas!, em: linhaViva)
        abertas = ShelfOrdem.pilhaAberta(abertas, em: linhaViva)
        check(abertas == nil, "tirou mais um, sobrou um: a pilha fecha sozinha")

        // paginação da grade
        let vinteURLs = (0..<20).map { u("/tmp/g\($0)") }
        let dez = Array(vinteURLs.prefix(10))
        check(ShelfOrdem.pagina(de: dez, porPagina: 10, indice: 0).count == 10,
              "o que cabe na página inteira não abre espaço pro botão Mais")
        check(ShelfOrdem.paginas(de: dez, porPagina: 10) == 1, "e é uma página só")
        check(ShelfOrdem.pagina(de: vinteURLs, porPagina: 10, indice: 0).count == 9,
              "com sobra, a última célula vira Mais e a página mostra nove")
        check(ShelfOrdem.paginas(de: vinteURLs, porPagina: 10) == 3, "20 em nove dá três páginas")
        check(ShelfOrdem.pagina(de: vinteURLs, porPagina: 10, indice: 2).count == 2,
              "a última página traz o resto")
        let varridos = (0..<3).flatMap { ShelfOrdem.pagina(de: vinteURLs, porPagina: 10, indice: $0) }
        check(varridos.map(\.path) == vinteURLs.map(\.path),
              "varrer as páginas devolve a pilha inteira, na ordem e sem repetir")
        check(ShelfOrdem.pagina(de: vinteURLs, porPagina: 10, indice: 9).isEmpty,
              "índice além do fim devolve vazio em vez de estourar")

        // ticket 005 — quando o item sai da prateleira ao ser arrastado
        func sai(_ aceitou: Bool, _ dentro: Bool, _ on: Bool) -> Bool {
            ShelfOrdem.saiAoArrastar(aceitou: aceitou, dentroDoNotch: dentro, habilitado: on)
        }
        check(sai(true, false, true), "aceite fora do notch tira o item solto")
        check(!sai(false, false, true), "recusa (soltar no vazio) mantém o item")
        check(!sai(true, true, true),
              "aceite DENTRO do notch é empilhamento, não saída: o item fica")
        check(sai(true, false, true),
              "pilha sai igual: o arraste leva os N arquivos juntos (ticket 006)")
        check(!sai(true, false, false), "com a chave de Ajustes desligada, nada sai")

        // o aperto de mão que separa arraste interno de externo
        ShelfArrasteInterno.pendente = false
        check(!ShelfArrasteInterno.consumir(), "sem marca, o arraste conta como externo")
        ShelfArrasteInterno.pendente = true
        check(ShelfArrasteInterno.consumir(), "com a marca do performDrop, conta como interno")
        check(!ShelfArrasteInterno.consumir(),
              "e consumir zera: o arraste seguinte não herda a marca")
        // um arquivo vindo do Finder liga a marca e não tem sessão pra consumir;
        // `startDrag` limpa antes de começar, senão a saída nunca aconteceria
        ShelfArrasteInterno.pendente = true
        ShelfArrasteInterno.pendente = false          // o que o startDrag faz
        check(!ShelfArrasteInterno.consumir(),
              "marca órfã de um drop de fora não contamina o próximo arraste")

        // ticket 007 — o drop do painel ignora o arraste que saiu da prateleira
        ShelfArrasteInterno.origemInterna = false
        check(!ShelfArrasteInterno.origemInterna, "drop vindo de fora não tem origem interna")
        ShelfArrasteInterno.origemInterna = true      // o que o startDrag faz
        check(ShelfArrasteInterno.origemInterna,
              "arraste que saiu da miniatura não vira entrada nova no painel")
        ShelfArrasteInterno.origemInterna = false     // o que o fim da sessão faz
        check(!ShelfArrasteInterno.origemInterna,
              "e o fim da sessão desliga: o próximo drop de fora entra normal")
    }
}
