//
//  TextoDaTela.swift
//  Knobler
//
//  A parte pura do Texto da tela: converter a seleção em pixels da foto do
//  monitor, ler o texto com o Vision e montar o resumo do aviso. Sem AppKit de
//  propósito — o textodatelacheck compila isto isolado.
//

import CoreGraphics
import Foundation
import Vision

enum TextoDaTela {
    /// Seleção em pontos globais do AppKit (origem embaixo-esquerda do
    /// principal) → retângulo em pixels da foto de `tela`, origem no topo.
    static func recortePixels(selecao: CGRect, tela: CGRect, escala: CGFloat) -> CGRect {
        CGRect(x: (selecao.minX - tela.minX) * escala,
               y: (tela.maxY - selecao.maxY) * escala,
               width: selecao.width * escala,
               height: selecao.height * escala).integral
    }

    /// Clique sem arrasto ou fiapo de seleção conta como cancelar.
    static func selecaoValida(_ r: CGRect) -> Bool {
        r.width >= 4 && r.height >= 4
    }

    /// Linhas na ordem que o Vision devolve (já é a de leitura).
    /// ponytail: sem reordenação por coluna; ordenar por midY/minX se texto em
    /// colunas vier embaralhado.
    static func linhas(em imagem: CGImage) throws -> [String] {
        let pedido = VNRecognizeTextRequest()
        pedido.recognitionLevel = .accurate
        pedido.usesLanguageCorrection = true
        pedido.recognitionLanguages = ["pt-BR", "en-US"]
        try VNImageRequestHandler(cgImage: imagem, options: [:]).perform([pedido])
        return (pedido.results ?? []).compactMap { $0.topCandidates(1).first?.string }
    }

    /// Primeira linha não vazia, cortada com "…" pra caber no card.
    static func resumo(_ texto: String, limite: Int = 60) -> String {
        let linha = texto.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return linha.count > limite ? String(linha.prefix(limite - 1)) + "…" : linha
    }
}
