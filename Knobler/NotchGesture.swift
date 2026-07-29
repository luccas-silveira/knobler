//
//  NotchGesture.swift
//  Knobler
//
//  A parte pura do gesto de scroll sobre o notch, separada do monitor de
//  eventos pra poder ser testada sem NSEvent.
//

import Foundation

enum ScrollTarget: Equatable { case closed, expanded, history }

enum NotchGesture {
    /// Pausa que separa dois gestos num mouse de rodinha: eventos a menos de
    /// 0,3 s um do outro são o MESMO gesto (é assim que o puxão longo acumula);
    /// parou mais que isso, o próximo evento começa gesto novo.
    ///
    /// ponytail: relógio no lugar de fase. A rodinha não emite `.began` nem
    /// `.ended`, então não há como saber onde um gesto acaba — rastrear isso
    /// por dispositivo custaria muito mais e o usuário não notaria a diferença.
    static let gestureGap: TimeInterval = 0.3

    /// Um gesto está começando? O acumulador e a flag da cortina zeram aqui, e
    /// sem isso os dois nunca zeram fora do trackpad.
    ///
    /// - `began`: o trackpad diz `.began`. É o único caso que o código antigo
    ///   reconhecia — e mouse de rodinha **não** emite fase nenhuma, então o
    ///   acumulador crescia pra sempre (o usuário caía na cortina sem querer e
    ///   só saía rolando centenas de pontos de volta) e a flag da cortina
    ///   ficava presa em `false`, deixando a lista impossível de rolar.
    /// - `previousInZone == false`: gesto que começou fora da zona e entrou
    ///   arrastando — o `.began` dele foi descartado antes desta checagem, então
    ///   ele herdaria o acumulado e a flag do gesto anterior.
    /// - tempo desde o último evento: a rodinha, de novo. Sem fase, só a pausa
    ///   distingue um gesto do seguinte.
    ///
    /// Inércia nunca começa gesto: ela vem DEPOIS dos dedos saírem.
    static func isGestureStart(began: Bool, momentum: Bool,
                               sinceLastEvent: TimeInterval,
                               previousInZone: Bool) -> Bool {
        if momentum { return false }
        if began { return true }
        if !previousInZone { return true }
        return sinceLastEvent > gestureGap
    }

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
