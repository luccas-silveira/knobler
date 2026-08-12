//
//  IlhaVisualizador.swift
//  Knobler
//
//  Medidas e curvas do indicador de reprodução da Dynamic Island. Os valores
//  marcados "Apple" saem da decompilação de MediaControls.framework; os
//  marcados "calibração" não têm fonte e foram acertados por comparação
//  visual. Fonte de tudo:
//  docs/superpowers/research/2026-08-12-fechado-dynamic-island-research.md
//
//  Sem view nenhuma de propósito: `tools/ilhacheck.swift` compila só este
//  arquivo, e uma view aqui arrastaria a árvore inteira pra dentro do check.
//

import SwiftUI

enum IlhaVisualizador {

    // MARK: - Medidas do indicador (Apple)

    /// `+[MRUWaveformData amplitudeCount]` devolve 6.
    static let barras = 6
    /// Acessório trailing da ilha compacta.
    static let area = CGSize(width: 22, height: 22)
    /// Quanto a barra engorda no pico (`xScaleMultiplier`).
    static let engordaNoPico: CGFloat = 0.66

    /// `slot` do `layoutSubviews`: a fatia que cabe a cada barra.
    static func passo(_ largura: CGFloat) -> CGFloat {
        largura / CGFloat(barras)
    }

    /// Metade do passo — o vão entre barras é igual à largura da barra.
    static func larguraDaBarra(_ largura: CGFloat) -> CGFloat {
        passo(largura) / 2
    }

    /// Centro horizontal da barra `indice`. A view usa um HStack centralizado,
    /// que reproduz estes centros; a função existe para o check provar isso.
    static func centro(_ indice: Int, largura: CGFloat) -> CGFloat {
        larguraDaBarra(largura) + CGFloat(indice) * passo(largura)
    }

    /// O piso é a própria largura da barra: silêncio vira ponto redondo, nunca
    /// um traço fino e nunca o sumiço da barra. É o detalhe que separa a cópia
    /// boa da ruim.
    static func altura(amplitude: CGFloat, area: CGSize) -> CGFloat {
        max(limitada(amplitude) * area.height, larguraDaBarra(area.width))
    }

    static func largura(amplitude: CGFloat, area: CGSize) -> CGFloat {
        larguraDaBarra(area.width) + engordaNoPico * limitada(amplitude)
    }

    private static func limitada(_ amplitude: CGFloat) -> CGFloat {
        min(max(amplitude, 0), 1)
    }

    // MARK: - Capa (Apple)

    static let capaLado: CGFloat = 22
    static let capaRaio: CGFloat = 5.5
    /// Pausado, a capa escurece — `setDimsWhenPaused:`.
    static let capaOpacidadePausada: CGFloat = 0.5
    static let capaDuracaoDim: TimeInterval = 0.2
    /// Sem capa: cinza fixo do iPhone, com cross-fade de meio segundo.
    static let cinzaSemCapa = NSColor(white: 0.392156863, alpha: 1)
    static let duracaoSemCapa: TimeInterval = 0.5

    // MARK: - Bandas (calibração)

    /// Sete bordas em bins de FFT (~47Hz/bin a 48kHz) para seis bandas. A Apple
    /// usa seis bandas, mas as bordas dela não foram extraídas: estas são a
    /// mesma faixa de antes (47Hz–12kHz) redividida em progressão geométrica de
    /// razão ~2,5 no lugar de ~3.
    static let bordasDeBanda = [1, 3, 6, 16, 41, 102, 256]

    // MARK: - Animação de reserva (Apple, com uma escolha nossa)

    /// Ciclo do `BouncyBars.caar`: doze quadros-chave uniformes, ~0,2418 s cada.
    static let cicloDaReserva: TimeInterval = 2.66

    /// As cinco sequências do asset, em fração da altura. O último valor repete
    /// o primeiro: é o que fecha o laço sem emenda.
    static let sequenciasDaReserva: [[CGFloat]] = [
        [0.490, 0.510, 0.429, 0.789, 0.655, 0.310,
         0.473, 0.510, 0.532, 0.688, 0.709, 0.490],
        [0.770, 0.480, 0.770, 0.552, 0.451, 0.461,
         0.881, 0.700, 0.907, 0.534, 0.519, 0.770],
        [0.600, 0.680, 0.580, 0.829, 0.680, 0.790,
         0.614, 0.880, 0.571, 0.829, 0.620, 0.600],
        [0.330, 0.589, 0.680, 0.469, 0.937, 0.599,
         0.717, 0.520, 0.688, 0.440, 0.730, 0.330],
        [0.400, 0.240, 0.489, 0.570, 0.421, 0.339,
         0.250, 0.720, 0.290, 0.588, 0.501, 0.400],
    ]

    /// Que sequência toca em cada barra. A tabela da Apple tem cinco e o
    /// indicador tem seis barras: a sexta repete a terceira defasada em meio
    /// ciclo. Escolha nossa, sem fonte.
    static let ordemDaReserva: [(sequencia: Int, defasagem: Double)] = [
        (0, 0), (1, 0), (2, 0), (3, 0), (4, 0), (2, 0.5),
    ]

    /// Amplitudes das seis barras no instante dado.
    static func reserva(em tempo: TimeInterval) -> [CGFloat] {
        ordemDaReserva.map { item in
            var fase = (tempo / cicloDaReserva + item.defasagem)
                .truncatingRemainder(dividingBy: 1)
            if fase < 0 { fase += 1 }
            return amostra(sequenciasDaReserva[item.sequencia], fase: fase)
        }
    }

    /// Catmull-Rom fechado nos quadros-chave — a Apple interpola em cúbica, e
    /// linear deixaria uma quina visível a cada 0,24 s. Pode passar de 0…1 no
    /// exagero da curva; quem limita é `altura(amplitude:area:)`.
    static func amostra(_ sequencia: [CGFloat], fase: Double) -> CGFloat {
        let intervalos = sequencia.count - 1        // 11: o último repete o primeiro
        let posicao = fase * Double(intervalos)
        let quadro = Int(posicao.rounded(.down)) % intervalos
        let t = CGFloat(posicao - posicao.rounded(.down))
        func ponto(_ indice: Int) -> CGFloat {
            sequencia[((indice % intervalos) + intervalos) % intervalos]
        }
        let p0 = ponto(quadro - 1), p1 = ponto(quadro)
        let p2 = ponto(quadro + 1), p3 = ponto(quadro + 2)
        return 0.5 * (2 * p1
            + (-p0 + p2) * t
            + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t
            + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
    }
}
