//
//  AskCardModelo.swift
//  Knobler
//
//  O que o card de pergunta decide sem desenhar nada: o sufixo de recomendada,
//  o resumo da aba respondida, a legenda de teclas do rodapé, o teto de altura
//  e o tamanho do preview. Só Foundation e CoreGraphics, pra compilar no gate ao lado de
//  AskModels.swift.
//

import CoreGraphics
import Foundation

enum AskRotulo {
    private static let sufixos = ["(Recomendado)", "(Recommended)"]

    /// Separa o sufixo que o Claude põe na opção recomendada. Só vale no fim
    /// do rótulo; no começo ou no meio ele é texto comum.
    static func separar(_ label: String) -> (texto: String, recomendada: Bool) {
        let limpo = label.trimmingCharacters(in: .whitespacesAndNewlines)
        for sufixo in sufixos {
            if let achado = limpo.range(of: sufixo, options: [.caseInsensitive, .anchored, .backwards]) {
                let antes = limpo[..<achado.lowerBound].trimmingCharacters(in: .whitespacesAndNewlines)
                return (antes, true)
            }
        }
        return (limpo, false)
    }
}

enum AskResumo {
    /// Texto curto que a aba de uma pergunta já respondida mostra.
    static func texto(_ answer: AskAnswer?) -> String {
        guard let answer else { return "" }
        let livre = (answer.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !livre.isEmpty { return livre }
        switch answer.labels.count {
        case 0: return ""
        case 1: return AskRotulo.separar(answer.labels[0]).texto
        default: return "\(answer.labels.count) marcadas"
        }
    }
}

struct AskLegendaItem: Equatable {
    /// Vazio quando o item é só uma dica, sem tecla desenhada.
    var teclas: [String]
    var texto: String
}

enum AskLegenda {
    /// Itens do rodapé. O campo de texto vence tudo: quem está digitando vê as
    /// teclas do campo, com ou sem o teclado na lista.
    static func itens(teclado: Bool, campo: Bool, multipla: Bool, abas: Bool, atalho: String?) -> [AskLegendaItem] {
        if campo {
            return [
                AskLegendaItem(teclas: ["⏎"], texto: "enviar"),
                AskLegendaItem(teclas: ["esc"], texto: "voltar à lista"),
                AskLegendaItem(teclas: [], texto: "⌥ direita dita"),
            ]
        }
        guard teclado else {
            guard let atalho else { return [] }
            return [AskLegendaItem(teclas: [atalho], texto: "responder pelo teclado")]
        }
        var itens = [AskLegendaItem(teclas: ["↑", "↓"], texto: "escolher")]
        if multipla {
            itens.append(AskLegendaItem(teclas: ["espaço"], texto: "marcar"))
            itens.append(AskLegendaItem(teclas: ["⏎"], texto: "confirmar"))
        } else {
            itens.append(AskLegendaItem(teclas: ["⏎"], texto: "responder"))
        }
        if abas {
            itens.append(AskLegendaItem(teclas: ["←", "→"], texto: "pergunta"))
        }
        itens.append(AskLegendaItem(teclas: ["esc"], texto: "soltar"))
        return itens
    }
}

/// Teto de 60% da tela: até onde o card cresce e quanto dele sobra para a
/// lista de opções, que é a única parte que rola.
enum AskTeto {
    /// Abaixo disto a lista não encolhe, mesmo com o card acima do teto.
    static let minimoDaLista: CGFloat = 96

    /// Altura máxima do card: 60% do disponível, menos o topo (o notch) e os
    /// 18 de padding que o `NotchView` põe em volta dele.
    static func doCard(disponivel: CGFloat, topo: CGFloat) -> CGFloat {
        0.6 * disponivel - (topo + 18)
    }

    /// Altura da área rolável da lista, ou `nil` quando ela cabe inteira.
    /// `card` e `listaAtual` são da mesma medida: a diferença é o que não é
    /// lista (topo, pergunta, preview embaixo, campo, legenda) e não muda com
    /// a rolagem, então a conta dá o mesmo valor antes e depois de rolar.
    static func daLista(natural: CGFloat, card: CGFloat, listaAtual: CGFloat, tetoDoCard: CGFloat) -> CGFloat? {
        guard natural > 0, card > 0 else { return nil }
        let sobra = card - listaAtual
        let teto = max(minimoDaLista, tetoDoCard - sobra)
        return natural > teto ? teto : nil
    }
}

struct AskPreviewLayout: Equatable {
    /// `true` = preview ao lado da lista; `false` = embaixo dela.
    var lado: Bool
    var fonte: CGFloat
    var larguraDoCard: CGFloat
    var quadro: CGSize
    /// Nem com a letra no piso o preview coube: o quadro rola.
    var rola: Bool

    static let larguraMinima: CGFloat = 460
    /// Os 20 de cada lado que o `NotchView` tira.
    static let margem: CGFloat = 40
    static let lista: CGFloat = 236
    static let vao: CGFloat = 10
    /// Padding horizontal do quadro.
    static let dentro: CGFloat = 20
    /// Padding vertical do quadro.
    static let vertical: CGFloat = 16
    static let entreLinhas: CGFloat = 2
    static let base: CGFloat = 11
    static let piso: CGFloat = 8

    /// Folga das comparações de "cabe": a letra que faz caber exato sai de
    /// uma divisão e volta com erro de ponto flutuante.
    private static let folga: CGFloat = 0.001

    /// Altura de uma linha do preview na letra `fonte`, já com o espaço entre
    /// linhas. A altura do quadro e quem desenha as linhas usam esta conta.
    static func passo(linha: CGFloat, fonte: CGFloat) -> CGFloat {
        linha * fonte / base + entreLinhas
    }

    /// `avanco` e `linha` são a largura de um caractere e a altura de uma
    /// linha da fonte monoespaçada a 11 pt; escalam linearmente com a letra.
    static func calcular(
        previews: [String],
        avanco: CGFloat,
        linha: CGFloat,
        larguraMaxima: CGFloat,
        alturaMaxima: CGFloat
    ) -> AskPreviewLayout? {
        guard !previews.isEmpty else { return nil }

        // ponytail: conta `Character`, então caractere de largura dupla (CJK,
        // emoji) sai mais largo que o previsto; o piso com rolagem cobre.
        var colunas = 0
        var linhas = 0
        for preview in previews {
            let partes = preview.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            linhas = max(linhas, partes.count)
            colunas = max(colunas, partes.map(\.count).max() ?? 0)
        }

        let texto = CGFloat(colunas) * avanco
        let lado = lista + vao + texto + dentro + margem <= larguraMaxima

        var fonte = base
        if !lado {
            fonte = min(base, max(piso, base * (larguraMaxima - margem - dentro) / texto))
        }

        func altura(_ fonte: CGFloat) -> CGFloat {
            CGFloat(linhas) * passo(linha: linha, fonte: fonte) + vertical
        }
        if altura(fonte) > alturaMaxima {
            // `entreLinhas` e `vertical` não escalam: a letra sai da equação
            // da altura, não da proporção simples.
            let cabe = base * ((alturaMaxima - vertical) / CGFloat(linhas) - entreLinhas) / linha
            fonte = min(fonte, max(piso, cabe))
        }

        let quadro = CGSize(width: texto * (fonte / base) + dentro, height: altura(fonte))
        let larguraDoCard: CGFloat
        let ocupado: CGFloat
        if lado {
            ocupado = lista + vao + quadro.width + margem
            larguraDoCard = max(larguraMinima, ocupado.rounded(.up))
        } else {
            ocupado = quadro.width + margem
            larguraDoCard = min(larguraMaxima, max(larguraMinima, ocupado.rounded(.up)))
        }
        let rola = ocupado > larguraMaxima + folga || quadro.height > alturaMaxima + folga

        return AskPreviewLayout(lado: lado, fonte: fonte, larguraDoCard: larguraDoCard, quadro: quadro, rola: rola)
    }
}
