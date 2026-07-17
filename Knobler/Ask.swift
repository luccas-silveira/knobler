//
//  Ask.swift
//  Knobler
//
//  Pergunta interativa do Claude Code (AskUserQuestion) exibida como card
//  no notch. O hook PreToolUse publica via POST /ask; o card responde e o
//  hook devolve a resposta ao Claude. Modelo espelha o payload da tool.
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
}

/// Resposta de UMA pergunta: labels clicados e/ou texto livre digitado/ditado.
struct AskAnswer: Equatable {
    var labels: [String]
    var text: String?
}
