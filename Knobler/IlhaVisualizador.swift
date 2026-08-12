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
}
