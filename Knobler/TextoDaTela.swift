//
//  TextoDaTela.swift
//  Knobler
//
//  A parte pura do Texto da tela: ler o texto com o Vision e montar o resumo
//  do aviso. Sem AppKit de propósito — o textodatelacheck compila isto isolado.
//

import CoreGraphics
import Foundation
import ImageIO
import Vision

enum TextoDaTela {
    /// Abre a captura do screencapture já em memória: o CGImage de uma URL
    /// decodifica preguiçoso e, com o arquivo apagado, o Vision lia vazio.
    static func imagem(de arquivo: URL) -> CGImage? {
        guard let dados = try? Data(contentsOf: arquivo),
              let fonte = CGImageSourceCreateWithData(dados as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(fonte, 0, nil)
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
