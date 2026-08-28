//
//  ShelfOrdem.swift
//  Knobler
//
//  O modelo e a ordem da prateleira, isolados do resto pra caber num gate: uma
//  entrada é um arquivo solto ou uma pilha (ticket 004), o índice 0 é o mais
//  novo e o excesso sai pelo fim (ticket 003).
//
//  Sem AppKit/SwiftUI de propósito — é o que permite rodar isto no
//  shelfordemcheck sem subir o app.
//

import Foundation

/// Uma vaga da prateleira: um arquivo solto ou uma pilha. A capacidade 8 conta
/// ENTRADAS — uma pilha de 20 fotos ocupa uma vaga.
struct ShelfEntry: Equatable, Identifiable {
    /// Nunca vazia. O índice 0 é a cara da entrada: a miniatura que a linha mostra.
    let urls: [URL]

    init(_ urls: [URL]) { self.urls = urls }

    var isPilha: Bool { urls.count > 1 }
    var capa: URL { urls[0] }

    /// Identidade derivada do conteúdo, NÃO persistida — a grade já era
    /// `id: \.self` sobre a URL, então identidade por conteúdo é o que já valia.
    ///
    /// É a lista de caminhos, e não os caminhos juntados por um separador:
    /// nome de arquivo aceita quebra de linha, e um arquivo chamado "a\nb"
    /// colidiria com a pilha de "a" e "b".
    var id: [String] { urls.map(\.path) }
}

enum ShelfOrdem {
    /// Põe `novos` como UMA entrada na frente da fila.
    ///
    /// Dedupe entre entradas: cada arquivo aparece uma vez só na prateleira. Um
    /// arquivo que estava dentro de uma pilha sai dela e vem pra entrada nova —
    /// re-arrastar é sinal de que ele voltou a ser usado, e ele deixa de ser
    /// candidato a cair pela borda. A pilha fica com os restantes; entrada que
    /// esvazia some, e pilha que sobra com um arquivo vira item solto sozinha,
    /// porque `isPilha` é `count > 1`.
    ///
    /// A comparação é por `path` porque o mesmo item volta do UserDefaults sem
    /// a barra final que o Finder manda numa pasta — por `URL` crua, a pasta
    /// re-arrastada depois de um restart entraria duplicada.
    static func inserir(_ novos: [URL], em entradas: [ShelfEntry],
                        capacidade: Int) -> [ShelfEntry] {
        var vistos = Set<String>()
        // preserva a ordem do drop e mata repetido dentro do próprio drop
        let entrando = novos.filter { vistos.insert($0.path).inserted }
        guard !entrando.isEmpty else { return entradas }
        let restantes = entradas.compactMap { entrada -> ShelfEntry? in
            let sobrou = entrada.urls.filter { !vistos.contains($0.path) }
            return sobrou.isEmpty ? nil : ShelfEntry(sobrou)
        }
        return Array(([ShelfEntry(entrando)] + restantes).prefix(capacidade))
    }

    /// O que vai pro UserDefaults: array de arrays de caminho, que o plist
    /// suporta nativamente. Não é JSON de propósito — a receita de captura da
    /// prateleira nos docs popula a chave com `defaults write`, e um blob JSON
    /// tornaria isso bem pior de manter.
    static func codificar(_ entradas: [ShelfEntry]) -> [[String]] {
        entradas.map { $0.urls.map(\.path) }
    }

    /// Lê o que o UserDefaults devolver, nos dois formatos.
    ///
    /// `[[String]]` é o formato de hoje. `[String]` é o legado (ticket 003 e
    /// anteriores) e vem INVERTIDO: nenhuma release contém a inversão de ordem
    /// do 003, então todo `shelfItems` gravado em máquina de usuário está na
    /// ordem antiga, mais velho primeiro, e inverter o põe na semântica do 003
    /// sem ninguém ver a prateleira com a idade trocada.
    ///
    /// `existe` é injetável só pro gate rodar sem tocar o disco.
    static func decodificar(_ salvo: Any?, capacidade: Int,
                            existe: (String) -> Bool = {
                                FileManager.default.fileExists(atPath: $0)
                            }) -> [ShelfEntry] {
        let cru: [[String]]
        if let novo = salvo as? [[String]] { cru = novo }
        else if let legado = salvo as? [String] { cru = legado.reversed().map { [$0] } }
        else { cru = [] }                       // chave ausente ou lixo
        // O mesmo invariante do `inserir`: um arquivo aparece uma vez só. Aqui
        // ele é necessário porque a chave também é escrita à mão, por
        // `defaults write`, na receita de captura da prateleira.
        var vistos = Set<String>()
        let vivos = cru.map { $0.filter { existe($0) && vistos.insert($0).inserted } }
                       .filter { !$0.isEmpty }
        return Array(vivos.map { ShelfEntry($0.map(URL.init(fileURLWithPath:))) }
                          .prefix(capacidade))
    }
}
