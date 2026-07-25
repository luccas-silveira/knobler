//
//  AskModels.swift
//  Knobler
//
//  Modelos do payload de perguntas interativas do Claude Code.
//

import Foundation

struct AskOption: Equatable {
    var label: String
    var description: String
    /// Mockup ASCII exibido no painel direito do card (layout split).
    var preview: String?
}

struct AskQuestion: Equatable {
    var question: String
    /// Chip curto ("Abordagem", "Layout"…) mostrado antes do título.
    var header: String
    var multiSelect: Bool
    var options: [AskOption]
}

struct AskRequest: Equatable {
    var id: String
    /// Uma chamada da tool traz 1–4 perguntas; o card pagina entre elas.
    var questions: [AskQuestion]
    var receivedAt: Date
    /// Quem pergunta (pasta do projeto da sessão do Claude Code) — várias sessões abertas
    /// precisam ser distinguíveis no card.
    var source: String? = nil
}

/// Resposta de UMA pergunta: labels clicados e/ou texto livre digitado/ditado.
struct AskAnswer: Equatable {
    var labels: [String]
    var text: String?
}
