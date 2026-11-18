//
//  AskTeclado.swift
//  Knobler
//
//  Que tecla vira que comando no card de pergunta, quando a pergunta é a dona
//  do teclado. Função pura: o vigia de teclas do app monta a `AskTecla` do
//  NSEvent e executa o comando que sai daqui. Prova: tools/asktecladocheck.swift.
//

import Foundation

/// Uma tecla apertada, sem NSEvent. `caracteres` é o
/// `charactersIgnoringModifiers`; `outros` = ⌃ ou ⌥.
struct AskTecla: Equatable {
    var codigo: Int
    var caracteres: String
    var shift = false
    var command = false
    var outros = false
    var repeticao = false
}

enum AskComando: Equatable {
    /// Vai direto para o reducer.
    case acao(AskAction)
    /// Leva o cursor ao campo "Outra resposta".
    case focarCampo
    /// Devolve o cursor do campo à lista de opções.
    case voltarALista
    /// Solta o teclado: as teclas voltam ao app da frente, a pergunta fica.
    case soltarTeclado
    /// Manda a pergunta de volta ao terminal (o mesmo do ✕).
    case cancelar
}

enum AskTeclado {
    // Códigos virtuais do macOS. Números e espaço saem de `caracteres`, nunca
    // do código: no AZERTY e no teclado numérico o código é outro.
    static let esc = 53
    static let retorno = 36
    static let enterNumerico = 76
    static let tab = 48
    static let esquerda = 123
    static let direita = 124
    static let baixo = 125
    static let cima = 126

    /// O comando da tecla, ou `nil` quando a tecla não é do card. `campo` diz
    /// se o cursor está no campo de texto (aí quase tudo é do campo).
    static func comando(_ tecla: AskTecla, campo: Bool, estado: AskState) -> AskComando? {
        guard let ativa = estado.active, ativa.questions.indices.contains(estado.page) else { return nil }

        // ⌘. cancela em qualquer lugar; qualquer outro ⌘, ⌃ ou ⌥ não é do card.
        if tecla.command {
            return !tecla.outros && tecla.caracteres == "." ? .cancelar : nil
        }
        if tecla.outros { return nil }

        if campo {
            if tecla.codigo == esc { return .voltarALista }
            if tecla.codigo == tab && tecla.shift { return .voltarALista }
            return nil
        }

        let pergunta = ativa.questions[estado.page]
        switch tecla.codigo {
        case esc:
            return .soltarTeclado
        case tab:
            return tecla.shift ? nil : .focarCampo
        case baixo:
            return .acao(.moveHighlight(by: 1))
        case cima:
            return .acao(.moveHighlight(by: -1))
        case esquerda:
            return estado.page > 0 ? .acao(.goTo(page: estado.page - 1)) : nil
        case direita:
            return estado.page + 1 < ativa.questions.count ? .acao(.goTo(page: estado.page + 1)) : nil
        case retorno, enterNumerico:
            // Segurar o Enter não pode responder a pergunta seguinte.
            guard !tecla.repeticao else { return nil }
            guard pergunta.multiSelect else { return .acao(.choose(index: estado.highlight ?? 0)) }
            let marcadas = pergunta.options.map(\.label).filter { estado.selected.contains($0) }
            return marcadas.isEmpty ? nil : .acao(.submit(labels: marcadas, text: nil))
        default:
            break
        }

        guard !tecla.repeticao else { return nil }
        if tecla.caracteres == " " {
            return pergunta.multiSelect ? .acao(.choose(index: estado.highlight ?? 0)) : nil
        }
        if tecla.caracteres.count == 1, let numero = Int(tecla.caracteres),
           numero >= 1, numero <= pergunta.options.count {
            return .acao(.choose(index: numero - 1))
        }
        return nil
    }
}
