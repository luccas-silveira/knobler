//
//  ShelfOrdem.swift
//  Knobler
//
//  A regra de ordem da prateleira, isolada do resto pra caber num gate: o
//  índice 0 é o mais novo, o excesso sai pelo fim (ticket 003).
//
//  ponytail: quem já tinha `shelfItems` gravado vê a prateleira com a idade
//  trocada no primeiro lançamento depois da atualização — são no máximo 8
//  itens, some no primeiro arraste. Não vale uma chave de migração.
//

import Foundation

enum ShelfOrdem {
    /// Põe `url` na frente da fila. Se ele já estava lá, sobe pra primeira
    /// posição em vez de duplicar: re-arrastar é sinal de que o arquivo voltou
    /// a ser usado, e ele deixa de ser candidato a cair pela borda.
    ///
    /// A comparação é por `path` porque o mesmo item volta do UserDefaults sem
    /// a barra final que o Finder manda numa pasta — por `URL` crua, a pasta
    /// re-arrastada depois de um restart entraria duplicada.
    static func inserir(_ url: URL, em itens: [URL], capacidade: Int) -> [URL] {
        var novos = itens.filter { $0.path != url.path }
        novos.insert(url, at: 0)
        return Array(novos.prefix(capacidade))
    }
}
