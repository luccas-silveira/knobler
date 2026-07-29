//
//  NotchGesture.swift
//  Knobler
//
//  A parte pura do gesto de scroll sobre o notch, separada do monitor de
//  eventos pra poder ser testada sem NSEvent.
//

import CoreGraphics

enum ScrollTarget: Equatable { case closed, expanded, history }

enum NotchGesture {
    /// Dedos pra baixo (deltaY positivo, natural scrolling): 24 pt abre o card,
    /// 120 pt — mesma passada, sem soltar — puxa o histórico. Pra cima fecha.
    ///
    /// O eixo horizontal entra só como guarda de diagonal: um swipe quase
    /// horizontal (pular faixa, trocar de tela) não pode abrir nem fechar o
    /// card de raspão. É a mesma razão 1,5 que o monitor usava antes.
    ///
    /// ponytail: alvo é função do acumulado, não uma máquina de estados. Sai
    /// mais barato que o scrollActed que existia aqui e o recuo dentro do
    /// mesmo gesto passa a funcionar de graça.
    ///
    /// Com o histórico já aberto esta função não é consultada: o monitor
    /// entrega o evento à lista pra ela rolar de verdade.
    static func verticalTarget(accumY: CGFloat, accumX: CGFloat) -> ScrollTarget? {
        guard abs(accumY) > abs(accumX) * 1.5 else { return nil }
        if accumY > 120 { return .history }
        if accumY > 24 { return .expanded }
        if accumY < -24 { return .closed }
        return nil
    }
}
