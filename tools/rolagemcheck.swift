// Gate da rolagem sobre o notch: rolar não abre nem fecha o card. O vertical
// vai sempre pro conteúdo (ou pra janela de trás, com o notch fechado); o
// horizontal continua andando uma seção ou trocando de faixa, e continua
// engolido na zona.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/NotchGesture.swift tools/rolagemcheck.swift \
//     -o /tmp/rolagemcheck && /tmp/rolagemcheck
//
// Tudo puro: nenhum NSEvent, nenhuma janela.
//
// Contrato que o teste fixa (o `handleScroll` só aplica o resultado):
//
//   NotchGesture.acao(deltaX:deltaY:accumX:accumY:inercia:expandido:temMidia:jaAgiu:)
//       -> AcaoDoScroll   (Equatable)
//
//   - deltaX/deltaY: o `scrollingDelta` DESTE evento — é ele que diz se o
//     evento é majoritariamente vertical.
//   - accumX/accumY: o acumulado do gesto, já com este evento somado (a
//     inércia não soma).
//   - inercia: o evento tem `momentumPhase`.
//   - expandido: o card está aberto. temMidia: há mídia tocando.
//   - jaAgiu: o gesto já trocou seção/faixa uma vez.
//
//   casos: .repassar, .engolir, .trocarSecao(avancando:), .trocarFaixa(proxima:)
//   — e nenhum caso que abra ou feche o card.

import Foundation
import CoreGraphics

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/rolagemcheck.swift:\(linha))")
        exit(1)
    }
}

@main
enum RolagemCheck {
    static func main() {
        testVerticalSempreRepassa()
        testVerticalComCardAberto()
        testVerticalComNotchFechado()
        testHorizontalAndaSecao()
        testHorizontalTrocaFaixa()
        testHorizontalContinuaEngolido()
        testGestoVerticalNaoTrocaSecao()
        print("rolagemcheck ok")
    }

    static let verticais: [CGFloat] = [-900, -130, -30, -25, -24, -10, -1, 1, 10, 24, 25, 30, 130, 900]

    /// Varredura: qualquer evento majoritariamente vertical, com qualquer
    /// acumulado (pra cima, pra baixo, ruído ou puxão gigante), em qualquer
    /// estado do notch, é repassado. Repassar não abre nem fecha nada — é o
    /// fim do gesto vertical. Pega a implementação que ainda abre com o puxão
    /// pra baixo, que fecha com o puxão pra cima, ou que engole o vertical em
    /// algum canto da tabela.
    static func testVerticalSempreRepassa() {
        for y in verticais {
            for expandido in [false, true] {
                for temMidia in [false, true] {
                    for jaAgiu in [false, true] {
                        for inercia in [false, true] {
                            let r = NotchGesture.acao(
                                deltaX: 0, deltaY: y,
                                accumX: 0, accumY: y,
                                inercia: inercia, expandido: expandido,
                                temMidia: temMidia, jaAgiu: jaAgiu)
                            exigir(r == .repassar,
                                   "vertical \(y) (expandido=\(expandido) mídia=\(temMidia) agiu=\(jaAgiu) inércia=\(inercia)) virou \(r), devia repassar")
                        }
                    }
                }
            }
        }
    }

    /// Card aberto rolando uma lista (WhatsApp, histórico, agenda, lembretes,
    /// link): o evento vertical passa adiante, com um pouco de deriva lateral,
    /// com acumulado grande e inclusive na inércia que chega depois dos dedos
    /// saírem. Pega quem só repassa quando há "lista em foco" ou quem engole a
    /// inércia como fazia antes.
    static func testVerticalComCardAberto() {
        // dedos: rolar a lista pra baixo e pra cima, com deriva lateral
        exigir(NotchGesture.acao(deltaX: 2, deltaY: 12, accumX: 6, accumY: 80,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false) == .repassar,
               "card aberto: rolar pra baixo devia ir pra lista")
        exigir(NotchGesture.acao(deltaX: -3, deltaY: -15, accumX: -8, accumY: -200,
                                 inercia: false, expandido: true, temMidia: true, jaAgiu: false) == .repassar,
               "card aberto: rolar pra cima devia ir pra lista, não fechar o card")
        // inércia vertical: o acumulado não muda (inércia não soma) e mesmo
        // assim o evento é do conteúdo
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 40, accumX: 0, accumY: 120,
                                 inercia: true, expandido: true, temMidia: false, jaAgiu: false) == .repassar,
               "card aberto: inércia vertical devia ir pra lista")
        exigir(NotchGesture.acao(deltaX: 1, deltaY: -40, accumX: 0, accumY: -120,
                                 inercia: true, expandido: true, temMidia: false, jaAgiu: false) == .repassar,
               "card aberto: inércia vertical pra cima devia ir pra lista")
    }

    /// Notch fechado: rolar na zona não abre o card e o evento segue pra
    /// janela de trás (a página do navegador embaixo do notch rola). Pega quem
    /// ainda abre com 25 pt pra baixo, ou quem engole o vertical "pra não
    /// rolar a janela de trás".
    static func testVerticalComNotchFechado() {
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 30, accumX: 0, accumY: 30,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false) == .repassar,
               "notch fechado: 30 pt pra baixo devia passar adiante, sem abrir")
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 6, accumX: 0, accumY: 900,
                                 inercia: false, expandido: false, temMidia: false, jaAgiu: false) == .repassar,
               "notch fechado: puxão gigante devia passar adiante, sem abrir")
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 50, accumX: 0, accumY: 300,
                                 inercia: true, expandido: false, temMidia: false, jaAgiu: false) == .repassar,
               "notch fechado: inércia vertical devia passar adiante")
    }

    /// Card aberto: acumulado lateral acima de 50 anda uma seção, uma vez por
    /// gesto, com o sentido pelo sinal (dedos pra esquerda = acumulado
    /// negativo = avança). O limite é aberto: 50 ainda não age.
    static func testHorizontalAndaSecao() {
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false)
                   == .trocarSecao(avancando: true),
               "card aberto: -60 lateral devia avançar uma seção")
        exigir(NotchGesture.acao(deltaX: 20, deltaY: 0, accumX: 60, accumY: 0,
                                 inercia: false, expandido: true, temMidia: true, jaAgiu: false)
                   == .trocarSecao(avancando: false),
               "card aberto: +60 lateral devia voltar uma seção (com mídia também)")
        exigir(NotchGesture.acao(deltaX: -10, deltaY: 0, accumX: -51, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false)
                   == .trocarSecao(avancando: true),
               "card aberto: 51 lateral já devia agir")
        // diagonal puxada pro lado continua sendo horizontal, como hoje
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 4, accumX: -60, accumY: 30,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false)
                   == .trocarSecao(avancando: true),
               "card aberto: diagonal majoritariamente lateral devia andar a seção")
    }

    /// Notch fechado com mídia: o lateral troca de faixa (pra esquerda =
    /// próxima). Pega quem troca seção com o card fechado ou inverte o sinal.
    static func testHorizontalTrocaFaixa() {
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false)
                   == .trocarFaixa(proxima: true),
               "notch fechado com mídia: -60 lateral devia ir pra próxima faixa")
        exigir(NotchGesture.acao(deltaX: 20, deltaY: 0, accumX: 60, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false)
                   == .trocarFaixa(proxima: false),
               "notch fechado com mídia: +60 lateral devia voltar a faixa")
    }

    /// O horizontal continua engolido na zona sempre que não age: abaixo do
    /// limiar, depois de já ter agido no mesmo gesto, na inércia, e com o
    /// notch fechado sem mídia. Pega quem passou a repassar tudo que não é
    /// ação (a janela de trás rolaria de lado junto), quem age duas vezes no
    /// mesmo gesto e quem age na inércia.
    static func testHorizontalContinuaEngolido() {
        exigir(NotchGesture.acao(deltaX: -10, deltaY: 0, accumX: -30, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false) == .engolir,
               "lateral abaixo do limiar devia ser engolido")
        exigir(NotchGesture.acao(deltaX: -10, deltaY: 0, accumX: -50, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false) == .engolir,
               "50 lateral ainda não age (limite aberto) e devia ser engolido")
        exigir(NotchGesture.acao(deltaX: 10, deltaY: 0, accumX: 50, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false) == .engolir,
               "notch fechado: 50 lateral ainda não troca faixa e devia ser engolido")
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -200, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: true) == .engolir,
               "card aberto: gesto que já agiu não anda outra seção, e é engolido")
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -200, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: true) == .engolir,
               "notch fechado: gesto que já agiu não troca outra faixa, e é engolido")
        exigir(NotchGesture.acao(deltaX: -30, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: true, expandido: true, temMidia: false, jaAgiu: false) == .engolir,
               "inércia lateral não age e devia ser engolida")
        exigir(NotchGesture.acao(deltaX: -30, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: true, expandido: false, temMidia: true, jaAgiu: false) == .engolir,
               "inércia lateral com o notch fechado não troca faixa e devia ser engolida")
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: false, expandido: false, temMidia: false, jaAgiu: false) == .engolir,
               "notch fechado sem mídia: lateral não faz nada e devia ser engolido")
    }

    /// Rolando uma lista pra baixo com o gesto claramente vertical, um evento
    /// solto com deriva lateral não pode trocar de seção nem de faixa — o
    /// usuário estava lendo, não navegando. Pega quem decide a troca só pelo
    /// acumulado lateral e ignora que o gesto inteiro é vertical.
    static func testGestoVerticalNaoTrocaSecao() {
        for (expandido, temMidia) in [(true, false), (true, true), (false, true)] {
            let r = NotchGesture.acao(deltaX: -8, deltaY: 2, accumX: -60, accumY: 400,
                                      inercia: false, expandido: expandido,
                                      temMidia: temMidia, jaAgiu: false)
            exigir(r == .repassar || r == .engolir,
                   "gesto vertical (accumY 400, accumX -60) não devia trocar seção/faixa (expandido=\(expandido) mídia=\(temMidia)), deu \(r)")
        }
    }
}
