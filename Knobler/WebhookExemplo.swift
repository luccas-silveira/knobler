//
//  WebhookExemplo.swift
//  Knobler
//
//  Colar JSON de exemplo no editor de mapeamento (008): um clique lendo o
//  clipboard, sem campo de texto. Aqui mora só a lógica pura — leitura do
//  texto, parse, trecho do que veio quando não é JSON, e a precedência
//  "payload real vence o exemplo". A UI (botão, faixa, aviso) fica em
//  `MappingEditorView`/`WebhookAssistantView`.
//
//  O exemplo é sempre local: nunca sobe pro relay, então `lastPayloadAt` e
//  `payloadCount` seguem significando POST de verdade.
//

import Foundation

/// De onde veio a árvore que está na tela do editor.
enum FonteDaArvore {
    case nenhuma
    case exemplo                /// JSON colado do clipboard
    case real                   /// último payload capturado pelo relay
    case realTrocouExemplo      /// chegou payload de verdade por cima de um exemplo

    /// Faixa persistente acima da árvore; `nil` = sem faixa.
    var faixa: String? {
        switch self {
        case .nenhuma, .real: return nil
        case .exemplo: return "Exemplo colado — nada chegou neste perfil ainda"
        case .realTrocouExemplo: return "Chegou um payload de verdade — o exemplo foi trocado"
        }
    }

    /// Só o exemplo pode ser descartado à mão; o real não.
    var podeDescartar: Bool { self == .exemplo }

    /// Payload real chegou: vence sempre, e avisa quando derrubou um exemplo.
    var comPayloadReal: FonteDaArvore { self == .exemplo ? .realTrocouExemplo : .real }
}

enum ResultadoDeColagem {
    case arvore(JSONValue)
    /// Não é JSON: o trecho é o começo do que estava copiado, pro usuário
    /// reconhecer o erro clássico (copiou a página, não o corpo).
    case invalido(trecho: String)
    case vazio
}

enum ExemploColado {
    static let limiteDoTrecho = 80

    /// Avalia o que está no clipboard. `nil` = clipboard sem texto.
    static func avaliar(_ texto: String?) -> ResultadoDeColagem {
        let cru = (texto ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cru.isEmpty else { return .vazio }
        // objeto ou array: fragmento solto ("abc", 42) é JSON válido mas não vira árvore útil
        guard cru.hasPrefix("{") || cru.hasPrefix("["), let v = JSONValue.parse(cru) else {
            return .invalido(trecho: trecho(cru))
        }
        return .arvore(v)
    }

    /// Primeiros `limiteDoTrecho` caracteres, com quebras e espaços colapsados
    /// (o clipboard errado costuma ser HTML indentado — sem isso o aviso vira parágrafo).
    static func trecho(_ s: String, limite: Int = limiteDoTrecho) -> String {
        let plano = s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return plano.count <= limite ? plano : String(plano.prefix(limite)) + "…"
    }

    static func mensagemDeErro(_ trecho: String) -> String {
        trecho.isEmpty
            ? "Não há nada copiado para colar."
            : "O que está copiado não é um JSON válido: \(trecho)"
    }
}
