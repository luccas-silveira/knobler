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

    /// Junta `novos` na entrada `alvo`, sem tirá-la do lugar (ticket 007).
    ///
    /// Diferente do `inserir`, que sempre cria entrada nova na frente: aqui o
    /// usuário apontou onde a pilha se forma, então a posição do alvo é a
    /// resposta. Os arquivos entram no fim da pilha, e o mesmo dedupe do
    /// `inserir` vale — arquivo que vem de outra entrada sai de lá, entrada que
    /// esvazia some. Soltar a entrada sobre ela mesma não muda nada.
    ///
    /// Alvo que não está mais na prateleira devolve tudo intocado.
    static func empilhar(_ novos: [URL], em alvo: ShelfEntry,
                         entradas: [ShelfEntry]) -> [ShelfEntry] {
        guard entradas.contains(where: { $0.id == alvo.id }) else { return entradas }
        var vistos = Set(alvo.urls.map(\.path))
        let entrando = novos.filter { vistos.insert($0.path).inserted }
        guard !entrando.isEmpty else { return entradas }
        let juntos = ShelfEntry(alvo.urls + entrando)
        return entradas.compactMap { entrada -> ShelfEntry? in
            if entrada.id == alvo.id { return juntos }
            let sobrou = entrada.urls.filter { !vistos.contains($0.path) }
            return sobrou.isEmpty ? nil : ShelfEntry(sobrou)
        }
    }

    /// Abre a pilha na linha: os N arquivos viram N itens soltos no lugar dela
    /// (ticket 007).
    ///
    /// Uma pilha de 20 numa prateleira de 8 não cabe: o excesso cai pelo fim,
    /// que é a mesma regra do 003. Entrada que não é pilha devolve tudo intocado.
    static func desempilhar(_ alvo: ShelfEntry, em entradas: [ShelfEntry],
                            capacidade: Int) -> [ShelfEntry] {
        guard alvo.isPilha, let i = entradas.firstIndex(where: { $0.id == alvo.id })
        else { return entradas }
        var novas = entradas
        novas.replaceSubrange(i...i, with: alvo.urls.map { ShelfEntry([$0]) })
        return Array(novas.prefix(capacidade))
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

    /// A entrada sai da prateleira depois de um arraste? (ticket 005)
    ///
    /// `aceitou` é o `operation` de volta em `draggingSession(_:endedAt:_:)`
    /// contendo `.copy` — a medição 001 viu 7 aceites em `.copy` e 2 recusas em
    /// `.none`, sem divergência. A Lixeira devolve `.delete` e o item fica: é o
    /// lado seguro do erro.
    ///
    /// `dentroDoNotch` marca o arraste que terminou na própria prateleira (o
    /// empilhamento do 007), que também devolve `.copy` — sem essa separação a
    /// saída apagaria o item que acabou de ser empilhado.
    ///
    /// Pilha sai igual a item solto (ticket 006): o arraste leva os N arquivos
    /// juntos pro pasteboard, então tirar a entrada inteira não abandona nada.
    static func saiAoArrastar(aceitou: Bool, dentroDoNotch: Bool,
                              habilitado: Bool) -> Bool {
        habilitado && aceitou && !dentroDoNotch
    }

}

/// Sinal de que o arraste em curso foi solto DENTRO da prateleira.
///
/// `ShelfDropDelegate.performDrop` liga, `startDrag` limpa no começo de cada
/// arraste e o fim da sessão consome. É um aperto de mão e não geometria porque
/// o painel do notch tem 700pt de largura e vai do topo da tela até o Dock: um
/// Finder no meio da tela cairia dentro do frame e passaria por drop interno.
/// Tudo roda na main thread, e `performDrop` vem antes do fim da sessão.
enum ShelfArrasteInterno {
    static var pendente = false

    /// Lê e zera de uma vez: um arraste que terminou fora não pode herdar a
    /// marca de um anterior.
    static func consumir() -> Bool {
        defer { pendente = false }
        return pendente
    }
}
