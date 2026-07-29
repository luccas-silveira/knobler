//
//  NotchGesture.swift
//  Knobler
//
//  A parte pura do gesto de scroll sobre o notch, separada do monitor de
//  eventos pra poder ser testada sem NSEvent.
//

import Foundation

enum ScrollTarget: Equatable { case closed, expanded }

enum NotchGesture {
    /// Pausa que separa dois gestos num mouse de rodinha: eventos a menos de
    /// 0,3 s um do outro são o MESMO gesto (é assim que o puxão longo acumula);
    /// parou mais que isso, o próximo evento começa gesto novo.
    ///
    /// ponytail: relógio no lugar de fase. A rodinha não emite `.began` nem
    /// `.ended`, então não há como saber onde um gesto acaba — rastrear isso
    /// por dispositivo custaria muito mais e o usuário não notaria a diferença.
    /// Teto conhecido: um puxão MUITO lento de rodinha, com mais de 0,3 s entre
    /// dois cliques do detente, se parte em dois gestos. Numa rodinha real os
    /// detentes de uma mesma girada chegam bem abaixo disso.
    static let gestureGap: TimeInterval = 0.3

    /// Folga invisível de hover embaixo do card aberto — a `NotchView` a aplica
    /// como `.padding(.bottom,)` e a zona do gesto a soma na altura. Mora aqui
    /// pra que as duas leiam a MESMA constante: o que o usuário lê como "o card"
    /// termina nela, não na altura desenhada, e zona menor que a folga deixa uma
    /// tira que responde ao hover mas não ao scroll.
    static let folgaDeHover: CGFloat = 16

    /// Largura desenhada do card aberto. Mora aqui, e não como literal na
    /// `NotchView`, porque a zona do gesto precisa da MESMA constante — a
    /// `NotchView` a lê no `expandedSize`.
    static let larguraDoCard: CGFloat = 430

    /// Largura da zona do gesto com o notch fechado: bem mais larga que o notch
    /// físico de propósito, pra que dois dedos na moldura ainda acertem.
    static let larguraFechada: CGFloat = 400

    /// A faixa horizontal que escuta o gesto. Aberta, é a largura do card mais a
    /// folga de hover dos DOIS lados — mesmo motivo do eixo vertical: zona mais
    /// estreita que o card deixa uma tira que responde ao hover e não ao scroll.
    static func zoneWidth(expanded: Bool) -> CGFloat {
        expanded ? larguraDoCard + 2 * folgaDeHover : larguraFechada
    }

    /// O cursor está dentro dessa faixa? A zona é centrada no meio da tela,
    /// como o notch.
    static func naZonaHorizontal(mouseX: CGFloat, screenMidX: CGFloat,
                                 expanded: Bool) -> Bool {
        abs(mouseX - screenMidX) <= zoneWidth(expanded: expanded) / 2
    }

    /// Folga acima e abaixo do notch fechado. Sem ela o alvo seria a moldura
    /// exata — dois dedos sobre o notch nunca acertariam.
    static let folgaDoNotch: CGFloat = 10

    /// O cursor está na faixa vertical que escuta o gesto?
    ///
    /// Aberto, a zona é a altura publicada pelo VM mais a folga de hover: cada
    /// seção declara a sua altura, então a zona anda junto sozinha. Era uma
    /// tabela de literais (`420 / 200`) que ficava a 2 pt de estourar no card da
    /// nota e estouraria de vez com as seções altas.
    ///
    /// `alturaAtual` pode chegar zerada, antes da view publicar a primeira: a
    /// zona encolhe pra folga, o que ainda cobre o topo — degenerar pra negativo
    /// mataria o gesto em vez de só apertá-lo.
    static func inZone(mouseY: CGFloat, screenMaxY: CGFloat, expanded: Bool,
                       alturaAtual: CGFloat, notchHeight: CGFloat) -> Bool {
        let zoneHeight = expanded ? alturaAtual + folgaDeHover
                                  : notchHeight + folgaDoNotch
        return mouseY >= screenMaxY - zoneHeight
    }

    /// Um gesto está começando? O acumulador e a flag da lista rolável zeram aqui, e
    /// sem isso os dois nunca zeram fora do trackpad.
    ///
    /// - `began`: o trackpad diz `.began`. É o único caso que o código antigo
    ///   reconhecia — e mouse de rodinha **não** emite fase nenhuma, então o
    ///   acumulador crescia pra sempre (o usuário trocava de seção sem querer e
    ///   só saía rolando centenas de pontos de volta) e a flag da lista rolável
    ///   ficava presa em `false`, deixando a lista impossível de rolar.
    /// - `previousInZone == false`: gesto que começou fora da zona e entrou
    ///   arrastando — o `.began` dele foi descartado antes desta checagem, então
    ///   ele herdaria o acumulado e a flag do gesto anterior.
    /// - tempo desde o último evento: a rodinha, de novo. Sem fase, só a pausa
    ///   distingue um gesto do seguinte. **Só vale pra evento sem fase
    ///   nenhuma** (`hasPhase == false`): no trackpad os dedos podem parar
    ///   parados na superfície por meio segundo — o macOS não manda evento
    ///   enquanto isso — e o puxão continua no mesmo gesto, com `.changed`.
    ///   Se o relógio valesse ali, o acumulado do "numa passada só" zerava no
    ///   meio do puxão e o gesto se partiria em dois.
    ///
    /// Inércia nunca começa gesto: ela vem DEPOIS dos dedos saírem.
    static func isGestureStart(began: Bool, momentum: Bool,
                               sinceLastEvent: TimeInterval,
                               previousInZone: Bool,
                               hasPhase: Bool) -> Bool {
        if momentum { return false }
        if began { return true }
        if !previousInZone { return true }
        if hasPhase { return false }
        return sinceLastEvent > gestureGap
    }

    /// Dedos pra baixo (deltaY positivo, natural scrolling): 24 pt abre o card.
    /// Pra cima fecha.
    ///
    /// O eixo horizontal entra só como guarda de diagonal: um swipe quase
    /// horizontal (pular faixa, trocar de tela) não pode abrir nem fechar o
    /// card de raspão. É a mesma razão 1,5 que o monitor usava antes.
    ///
    /// ponytail: alvo é função do acumulado, não uma máquina de estados. Sai
    /// mais barato que o scrollActed que existia aqui e o recuo dentro do
    /// mesmo gesto passa a funcionar de graça.
    ///
    /// Com o histórico em foco esta função não é consultada: o monitor entrega
    /// o evento à lista pra ela rolar de verdade.
    static func verticalTarget(accumY: CGFloat, accumX: CGFloat) -> ScrollTarget? {
        guard abs(accumY) > abs(accumX) * 1.5 else { return nil }
        if accumY > 24 { return .expanded }
        if accumY < -24 { return .closed }
        return nil
    }
}
