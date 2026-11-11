// Gate da rolagem sobre o notch: rolar não abre nem fecha o card. O vertical
// vai sempre pro conteúdo (ou pra janela de trás, com o notch fechado); o
// horizontal continua andando uma seção ou trocando de faixa, e continua
// engolido na zona. O evento que encerra o gesto é sempre repassado: a lista
// que recebeu o começo precisa saber que os dedos saíram, senão fica presa
// esticada, com vazio embaixo.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/NotchGesture.swift tools/rolagemcheck.swift \
//     -o /tmp/rolagemcheck && /tmp/rolagemcheck
//
// Tudo puro: nenhum NSEvent, nenhuma janela.
//
// Contrato que o teste fixa (o `handleScroll` só aplica o resultado):
//
//   NotchGesture.acao(deltaX:deltaY:accumX:accumY:inercia:expandido:temMidia:jaAgiu:fim:)
//       -> AcaoDoScroll   (Equatable)
//
//   - deltaX/deltaY: o `scrollingDelta` DESTE evento — é ele que diz se o
//     evento é majoritariamente vertical.
//   - accumX/accumY: o acumulado do gesto, já com este evento somado (a
//     inércia não soma).
//   - inercia: o evento tem `momentumPhase`.
//   - expandido: o card está aberto. temMidia: há mídia tocando.
//   - jaAgiu: o gesto já trocou seção/faixa uma vez.
//   - fim: o evento encerra o gesto (`phase` ou `momentumPhase` com `.ended`
//     ou `.cancelled`). Obrigatório, sem valor padrão. Com `fim: true` o
//     resultado é sempre `.repassar`; com `fim: false` nada muda. Quem calcula
//     o `fim` é o `handleScroll` — isso é o tools/rolagemligacaocheck.swift.
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
        testFimSempreRepassa()
        testFimViraADecisao()
        testGestoQueRolouEntregaOFim()
        testGestoQueViraLateralEntregaOFim()
        testGestoLateralAgeUmaVezEEntregaOFim()
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
                            for fim in [false, true] {
                                let r = NotchGesture.acao(
                                    deltaX: 0, deltaY: y,
                                    accumX: 0, accumY: y,
                                    inercia: inercia, expandido: expandido,
                                    temMidia: temMidia, jaAgiu: jaAgiu, fim: fim)
                                exigir(r == .repassar,
                                       "vertical \(y) (expandido=\(expandido) mídia=\(temMidia) agiu=\(jaAgiu) inércia=\(inercia) fim=\(fim)) virou \(r), devia repassar")
                            }
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
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, fim: false) == .repassar,
               "card aberto: rolar pra baixo devia ir pra lista")
        exigir(NotchGesture.acao(deltaX: -3, deltaY: -15, accumX: -8, accumY: -200,
                                 inercia: false, expandido: true, temMidia: true, jaAgiu: false, fim: false) == .repassar,
               "card aberto: rolar pra cima devia ir pra lista, não fechar o card")
        // inércia vertical: o acumulado não muda (inércia não soma) e mesmo
        // assim o evento é do conteúdo
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 40, accumX: 0, accumY: 120,
                                 inercia: true, expandido: true, temMidia: false, jaAgiu: false, fim: false) == .repassar,
               "card aberto: inércia vertical devia ir pra lista")
        exigir(NotchGesture.acao(deltaX: 1, deltaY: -40, accumX: 0, accumY: -120,
                                 inercia: true, expandido: true, temMidia: false, jaAgiu: false, fim: false) == .repassar,
               "card aberto: inércia vertical pra cima devia ir pra lista")
    }

    /// Notch fechado: rolar na zona não abre o card e o evento segue pra
    /// janela de trás (a página do navegador embaixo do notch rola). Pega quem
    /// ainda abre com 25 pt pra baixo, ou quem engole o vertical "pra não
    /// rolar a janela de trás".
    static func testVerticalComNotchFechado() {
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 30, accumX: 0, accumY: 30,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false, fim: false) == .repassar,
               "notch fechado: 30 pt pra baixo devia passar adiante, sem abrir")
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 6, accumX: 0, accumY: 900,
                                 inercia: false, expandido: false, temMidia: false, jaAgiu: false, fim: false) == .repassar,
               "notch fechado: puxão gigante devia passar adiante, sem abrir")
        exigir(NotchGesture.acao(deltaX: 0, deltaY: 50, accumX: 0, accumY: 300,
                                 inercia: true, expandido: false, temMidia: false, jaAgiu: false, fim: false) == .repassar,
               "notch fechado: inércia vertical devia passar adiante")
    }

    /// Card aberto: acumulado lateral acima de 50 anda uma seção, uma vez por
    /// gesto, com o sentido pelo sinal (dedos pra esquerda = acumulado
    /// negativo = avança). O limite é aberto: 50 ainda não age.
    static func testHorizontalAndaSecao() {
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, fim: false)
                   == .trocarSecao(avancando: true),
               "card aberto: -60 lateral devia avançar uma seção")
        exigir(NotchGesture.acao(deltaX: 20, deltaY: 0, accumX: 60, accumY: 0,
                                 inercia: false, expandido: true, temMidia: true, jaAgiu: false, fim: false)
                   == .trocarSecao(avancando: false),
               "card aberto: +60 lateral devia voltar uma seção (com mídia também)")
        exigir(NotchGesture.acao(deltaX: -10, deltaY: 0, accumX: -51, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, fim: false)
                   == .trocarSecao(avancando: true),
               "card aberto: 51 lateral já devia agir")
        // diagonal puxada pro lado continua sendo horizontal, como hoje
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 4, accumX: -60, accumY: 30,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, fim: false)
                   == .trocarSecao(avancando: true),
               "card aberto: diagonal majoritariamente lateral devia andar a seção")
    }

    /// Notch fechado com mídia: o lateral troca de faixa (pra esquerda =
    /// próxima). Pega quem troca seção com o card fechado ou inverte o sinal.
    static func testHorizontalTrocaFaixa() {
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false, fim: false)
                   == .trocarFaixa(proxima: true),
               "notch fechado com mídia: -60 lateral devia ir pra próxima faixa")
        exigir(NotchGesture.acao(deltaX: 20, deltaY: 0, accumX: 60, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false, fim: false)
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
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, fim: false) == .engolir,
               "lateral abaixo do limiar devia ser engolido")
        exigir(NotchGesture.acao(deltaX: -10, deltaY: 0, accumX: -50, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, fim: false) == .engolir,
               "50 lateral ainda não age (limite aberto) e devia ser engolido")
        exigir(NotchGesture.acao(deltaX: 10, deltaY: 0, accumX: 50, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: false, fim: false) == .engolir,
               "notch fechado: 50 lateral ainda não troca faixa e devia ser engolido")
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -200, accumY: 0,
                                 inercia: false, expandido: true, temMidia: false, jaAgiu: true, fim: false) == .engolir,
               "card aberto: gesto que já agiu não anda outra seção, e é engolido")
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -200, accumY: 0,
                                 inercia: false, expandido: false, temMidia: true, jaAgiu: true, fim: false) == .engolir,
               "notch fechado: gesto que já agiu não troca outra faixa, e é engolido")
        exigir(NotchGesture.acao(deltaX: -30, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: true, expandido: true, temMidia: false, jaAgiu: false, fim: false) == .engolir,
               "inércia lateral não age e devia ser engolida")
        exigir(NotchGesture.acao(deltaX: -30, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: true, expandido: false, temMidia: true, jaAgiu: false, fim: false) == .engolir,
               "inércia lateral com o notch fechado não troca faixa e devia ser engolida")
        exigir(NotchGesture.acao(deltaX: -20, deltaY: 0, accumX: -60, accumY: 0,
                                 inercia: false, expandido: false, temMidia: false, jaAgiu: false, fim: false) == .engolir,
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
                                      temMidia: temMidia, jaAgiu: false, fim: false)
            exigir(r == .repassar || r == .engolir,
                   "gesto vertical (accumY 400, accumX -60) não devia trocar seção/faixa (expandido=\(expandido) mídia=\(temMidia)), deu \(r)")
        }
    }

    // MARK: - fim do gesto

    /// O evento que encerra o gesto é repassado SEMPRE: com qualquer delta,
    /// qualquer acumulado (abaixo, em cima e acima do limiar, pros dois lados),
    /// na inércia, com o card aberto ou fechado, com ou sem mídia, tendo o
    /// gesto agido ou não. Pega quem só repassa o fim com delta zero, quem
    /// esquece o fim da inércia, quem só troca o `.engolir` por `.repassar` e
    /// deixa o fim andar seção ou trocar faixa, e quem põe a regra depois da
    /// trava do `jaAgiu`.
    static func testFimSempreRepassa() {
        let deltas: [CGFloat] = [-40, -3, 0, 3, 40]
        let acumulados: [CGFloat] = [-900, -60, -51, -50, -10, 0, 10, 50, 51, 60, 900]
        for dx in deltas { for dy in deltas {
            for ax in acumulados { for ay in acumulados {
                for inercia in [false, true] { for expandido in [false, true] {
                    for temMidia in [false, true] { for jaAgiu in [false, true] {
                        let r = NotchGesture.acao(
                            deltaX: dx, deltaY: dy, accumX: ax, accumY: ay,
                            inercia: inercia, expandido: expandido,
                            temMidia: temMidia, jaAgiu: jaAgiu, fim: true)
                        exigir(r == .repassar,
                               "fim do gesto (delta \(dx),\(dy) acumulado \(ax),\(ay) inércia=\(inercia) expandido=\(expandido) mídia=\(temMidia) agiu=\(jaAgiu)) virou \(r), devia repassar")
                    } }
                } }
            } }
        } }
    }

    /// É o `fim` que vira a decisão, e só ele: o mesmo evento, com os mesmos
    /// números, segue como hoje com `fim: false` (engolido, ou andando seção,
    /// ou trocando faixa) e é repassado com `fim: true`. Os casos são os do
    /// defeito: o evento de fim chega com delta (0, 0) e o acumulado lateral
    /// do gesto empata ou ganha do vertical.
    /// A metade `fim: false` pega quem ignora o parâmetro e adivinha o fim
    /// pelo delta zerado (um `.changed` parado também tem delta zero, e não
    /// encerra nada); a metade `fim: true` pega quem deixou o fim como estava.
    static func testFimViraADecisao() {
        struct Caso {
            let nome: String
            let dx: CGFloat, dy: CGFloat, ax: CGFloat, ay: CGFloat
            let inercia: Bool, expandido: Bool, temMidia: Bool, jaAgiu: Bool
            let hoje: AcaoDoScroll
        }
        let casos = [
            Caso(nome: "subiu e desceu com deriva lateral pequena, card aberto",
                 dx: 0, dy: 0, ax: 6, ay: 0,
                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, hoje: .engolir),
            Caso(nome: "subiu e desceu exatamente a mesma distância, sem deriva",
                 dx: 0, dy: 0, ax: 0, ay: 0,
                 inercia: false, expandido: true, temMidia: false, jaAgiu: false, hoje: .engolir),
            Caso(nome: "lateral maior que o vertical e abaixo do limiar, card aberto",
                 dx: 0, dy: 0, ax: -30, ay: 10,
                 inercia: false, expandido: true, temMidia: true, jaAgiu: false, hoje: .engolir),
            Caso(nome: "lateral maior que o vertical e abaixo do limiar, notch fechado com mídia",
                 dx: 0, dy: 0, ax: 30, ay: -10,
                 inercia: false, expandido: false, temMidia: true, jaAgiu: false, hoje: .engolir),
            Caso(nome: "lateral acima do limiar, card aberto (dedos pra esquerda)",
                 dx: 0, dy: 0, ax: -72, ay: 0,
                 inercia: false, expandido: true, temMidia: false, jaAgiu: false,
                 hoje: .trocarSecao(avancando: true)),
            Caso(nome: "lateral acima do limiar, card aberto (dedos pra direita)",
                 dx: 0, dy: 0, ax: 72, ay: 10,
                 inercia: false, expandido: true, temMidia: true, jaAgiu: false,
                 hoje: .trocarSecao(avancando: false)),
            Caso(nome: "lateral acima do limiar, notch fechado com mídia (dedos pra esquerda)",
                 dx: 0, dy: 0, ax: -72, ay: 0,
                 inercia: false, expandido: false, temMidia: true, jaAgiu: false,
                 hoje: .trocarFaixa(proxima: true)),
            Caso(nome: "lateral acima do limiar, notch fechado com mídia (dedos pra direita)",
                 dx: 0, dy: 0, ax: 72, ay: -10,
                 inercia: false, expandido: false, temMidia: true, jaAgiu: false,
                 hoje: .trocarFaixa(proxima: false)),
            Caso(nome: "lateral acima do limiar, notch fechado sem mídia",
                 dx: 0, dy: 0, ax: -72, ay: 0,
                 inercia: false, expandido: false, temMidia: false, jaAgiu: false, hoje: .engolir),
            Caso(nome: "gesto que já andou a seção",
                 dx: 0, dy: 0, ax: -200, ay: 0,
                 inercia: false, expandido: true, temMidia: false, jaAgiu: true, hoje: .engolir),
            Caso(nome: "fim da inércia, lateral maior que o vertical",
                 dx: 0, dy: 0, ax: 12, ay: 10,
                 inercia: true, expandido: true, temMidia: false, jaAgiu: false, hoje: .engolir),
            Caso(nome: "fim da inércia, lateral acima do limiar com card aberto",
                 dx: 0, dy: 0, ax: -72, ay: 0,
                 inercia: true, expandido: true, temMidia: false, jaAgiu: false, hoje: .engolir),
            Caso(nome: "fim da inércia, lateral acima do limiar com notch fechado e mídia",
                 dx: 0, dy: 0, ax: -72, ay: 0,
                 inercia: true, expandido: false, temMidia: true, jaAgiu: false, hoje: .engolir),
            // gesto cancelado no meio do puxão: o último evento ainda traz delta
            Caso(nome: "fim com delta lateral, acima do limiar com card aberto",
                 dx: -20, dy: 0, ax: -60, ay: 0,
                 inercia: false, expandido: true, temMidia: false, jaAgiu: false,
                 hoje: .trocarSecao(avancando: true)),
        ]
        for c in casos {
            func decidir(fim: Bool) -> AcaoDoScroll {
                NotchGesture.acao(deltaX: c.dx, deltaY: c.dy, accumX: c.ax, accumY: c.ay,
                                  inercia: c.inercia, expandido: c.expandido,
                                  temMidia: c.temMidia, jaAgiu: c.jaAgiu, fim: fim)
            }
            let semFim = decidir(fim: false)
            exigir(semFim == c.hoje,
                   "\(c.nome): com fim: false devia seguir como hoje (\(c.hoje)), deu \(semFim)")
            let comFim = decidir(fim: true)
            exigir(comFim == .repassar,
                   "\(c.nome): o evento de fim devia ser repassado, deu \(comFim)")
        }
    }

    // MARK: - gesto de ponta a ponta

    /// Um evento de trackpad, do jeito que o `handleScroll` o lê.
    enum Fase {
        case comecou, mudou, terminou, cancelou
        case inercia, inerciaTerminou, inerciaCancelou

        var ehInercia: Bool {
            self == .inercia || self == .inerciaTerminou || self == .inerciaCancelou
        }
        /// `phase` ou `momentumPhase` com `.ended` / `.cancelled`
        var ehFim: Bool {
            self == .terminou || self == .cancelou
                || self == .inerciaTerminou || self == .inerciaCancelou
        }
    }

    struct Evento {
        let dx: CGFloat, dy: CGFloat
        let fase: Fase
        init(_ dx: CGFloat, _ dy: CGFloat, _ fase: Fase) {
            self.dx = dx; self.dy = dy; self.fase = fase
        }
    }

    struct Passo {
        let evento: Evento
        /// o que o `handleScroll` faz com o evento
        let acao: AcaoDoScroll
        /// o que a regra diria do mesmo evento sem saber que ele encerra o
        /// gesto — é o que mostra que o cenário reproduz o defeito
        let semFim: AcaoDoScroll

        var agiu: Bool {
            switch acao {
            case .trocarSecao, .trocarFaixa: return true
            case .repassar, .engolir: return false
            }
        }
    }

    /// O mesmo acúmulo do `handleScroll`: zera no começo do gesto (pelo
    /// `isGestureStart` de verdade), soma os deltas dos dedos, não soma a
    /// inércia, e trava o `jaAgiu` quando a decisão troca seção ou faixa.
    static func simular(_ eventos: [Evento], expandido: Bool, temMidia: Bool) -> [Passo] {
        var accumX: CGFloat = 0, accumY: CGFloat = 0
        var agiu = false, anteriorNaZona = false
        var passos: [Passo] = []
        for e in eventos {
            let inercia = e.fase.ehInercia
            if NotchGesture.isGestureStart(began: e.fase == .comecou, momentum: inercia,
                                           sinceLastEvent: 0.016,
                                           previousInZone: anteriorNaZona, hasPhase: true) {
                accumX = 0; accumY = 0; agiu = false
            }
            anteriorNaZona = true
            if !inercia { accumX += e.dx; accumY += e.dy }
            func decidir(fim: Bool) -> AcaoDoScroll {
                NotchGesture.acao(deltaX: e.dx, deltaY: e.dy, accumX: accumX, accumY: accumY,
                                  inercia: inercia, expandido: expandido,
                                  temMidia: temMidia, jaAgiu: agiu, fim: fim)
            }
            let passo = Passo(evento: e, acao: decidir(fim: e.fase.ehFim), semFim: decidir(fim: false))
            passos.append(passo)
            if passo.agiu { agiu = true }
        }
        return passos
    }

    static let estados: [(expandido: Bool, temMidia: Bool)] =
        [(true, false), (true, true), (false, true), (false, false)]

    /// A regra de ponta a ponta: se a lista recebeu algum evento do gesto, ela
    /// recebe também todo evento de fim (o dos dedos e o da inércia).
    static func exigirFimEntregue(_ passos: [Passo], _ gesto: String) {
        guard passos.contains(where: { $0.acao == .repassar && !$0.evento.fase.ehFim }) else { return }
        for (i, p) in passos.enumerated() where p.evento.fase.ehFim {
            exigir(p.acao == .repassar,
                   "\(gesto): a lista recebeu o gesto e o evento de fim (nº \(i + 1), \(p.evento.fase)) virou \(p.acao) — ela nunca sabe que os dedos saíram")
        }
    }

    /// Quem rola a lista e solta: todo evento chega nela, o de fim inclusive,
    /// e nada troca de seção nem de faixa. Em todos os gestos daqui o
    /// acumulado lateral termina maior ou igual ao vertical — é onde o fim era
    /// engolido (ou, com a deriva acima do limiar, andava uma seção ao soltar).
    /// Pega a regra de hoje, quem repassa o fim dos dedos e engole o da
    /// inércia, e quem esquece o gesto cancelado.
    static func testGestoQueRolouEntregaOFim() {
        let gestos: [(nome: String, eventos: [Evento])] = [
            ("sobe e desce a mesma distância com deriva lateral pequena", [
                Evento(0, 12, .comecou), Evento(1, 18, .mudou), Evento(1, 20, .mudou),
                Evento(1, 10, .mudou), Evento(1, -14, .mudou), Evento(1, -22, .mudou),
                Evento(1, -16, .mudou), Evento(0, -8, .mudou), Evento(0, 0, .terminou),
            ]),
            ("sobe e desce exatamente a mesma distância, sem deriva", [
                Evento(0, 25, .comecou), Evento(0, 35, .mudou), Evento(0, -35, .mudou),
                Evento(0, -25, .mudou), Evento(0, 0, .terminou),
            ]),
            ("sobe e desce com deriva lateral acima do limiar", [
                Evento(-9, 10, .comecou), Evento(-9, 10, .mudou), Evento(-9, 10, .mudou),
                Evento(-9, 10, .mudou), Evento(-9, -10, .mudou), Evento(-9, -10, .mudou),
                Evento(-9, -10, .mudou), Evento(-9, -10, .mudou), Evento(0, 0, .terminou),
            ]),
            ("sobe, volta e o gesto é cancelado", [
                Evento(0, 30, .comecou), Evento(2, -30, .mudou), Evento(0, 0, .cancelou),
            ]),
            ("sobe, volta quase tudo e solta com inércia", [
                Evento(2, 30, .comecou), Evento(4, 30, .mudou), Evento(3, -30, .mudou),
                Evento(3, -20, .mudou), Evento(0, 0, .terminou),
                Evento(0, -15, .inercia), Evento(1, -8, .inercia), Evento(0, -3, .inercia),
                Evento(0, 0, .inerciaTerminou),
            ]),
            ("sobe, volta quase tudo e os dedos voltam no meio da inércia", [
                Evento(2, 30, .comecou), Evento(4, 30, .mudou), Evento(3, -30, .mudou),
                Evento(3, -20, .mudou), Evento(0, 0, .terminou),
                Evento(0, -15, .inercia), Evento(0, 0, .inerciaCancelou),
            ]),
        ]
        for g in gestos {
            for estado in estados {
                let nome = "\(g.nome) (expandido=\(estado.expandido) mídia=\(estado.temMidia))"
                let passos = simular(g.eventos, expandido: estado.expandido, temMidia: estado.temMidia)
                let fins = passos.filter { $0.evento.fase.ehFim }
                // o cenário vale: a lista recebeu o gesto e, sem o `fim`, o
                // evento que o encerra não chegaria nela
                exigir(passos.contains { $0.acao == .repassar && !$0.evento.fase.ehFim },
                       "\(nome): nenhum evento do gesto foi repassado — o cenário não prova nada")
                exigir(!fins.isEmpty && fins.allSatisfy { $0.semFim != .repassar },
                       "\(nome): sem o fim o evento final devia seguir como hoje (engolido ou agindo), deu \(fins.map { $0.semFim })")
                exigirFimEntregue(passos, nome)
                for (i, p) in passos.enumerated() {
                    exigir(p.acao == .repassar,
                           "\(nome): o evento nº \(i + 1) (\(p.evento.dx),\(p.evento.dy) \(p.evento.fase)) virou \(p.acao); quem está rolando a lista devia ter o gesto inteiro repassado")
                }
            }
        }
    }

    /// Gesto que começa rolando a lista e vira pro lado: a lista recebeu o
    /// começo, então recebe o fim — mesmo depois de o gesto andar a seção ou
    /// trocar a faixa. O meio segue como hoje: engolido, com uma troca só.
    /// Pega quem só repassa o fim de gesto "vertical" (decidindo pelo
    /// acumulado) e quem deixa de repassar depois que o gesto agiu.
    static func testGestoQueViraLateralEntregaOFim() {
        let eventos = [
            Evento(0, 20, .comecou), Evento(-20, 2, .mudou), Evento(-20, 0, .mudou),
            Evento(-20, 0, .mudou), Evento(-20, 0, .mudou), Evento(0, 0, .terminou),
            Evento(-12, 0, .inercia), Evento(0, 0, .inerciaTerminou),
        ]
        let esperado: [(expandido: Bool, temMidia: Bool, troca: AcaoDoScroll)] = [
            (true, false, .trocarSecao(avancando: true)),
            (true, true, .trocarSecao(avancando: true)),
            (false, true, .trocarFaixa(proxima: true)),
            (false, false, .engolir),
        ]
        for e in esperado {
            let nome = "começa rolando e vira lateral (expandido=\(e.expandido) mídia=\(e.temMidia))"
            let passos = simular(eventos, expandido: e.expandido, temMidia: e.temMidia)
            let acoes = passos.map { $0.acao }
            exigirFimEntregue(passos, nome)
            exigir(acoes == [.repassar, .repassar, .engolir, e.troca, .engolir, .repassar,
                             .engolir, .repassar],
                   "\(nome): o gesto devia ser repassar, repassar, engolir, \(e.troca), engolir, repassar (fim), engolir (inércia lateral), repassar (fim da inércia); deu \(acoes)")
        }
    }

    /// O swipe lateral de sempre não muda no meio: engole abaixo do limiar,
    /// age uma vez só, engole o resto e a inércia. Só o evento que encerra
    /// (o dos dedos e o da inércia) passa adiante, sem agir de novo.
    /// Pega quem, pra repassar o fim, deixou de engolir o lateral, ou fez o
    /// fim agir uma segunda vez.
    static func testGestoLateralAgeUmaVezEEntregaOFim() {
        let eventos = [
            Evento(-20, 0, .comecou), Evento(-20, 0, .mudou), Evento(-20, 0, .mudou),
            Evento(-20, 0, .mudou), Evento(0, 0, .terminou),
            Evento(-15, 0, .inercia), Evento(-6, 0, .inercia), Evento(0, 0, .inerciaTerminou),
        ]
        let esperado: [(expandido: Bool, temMidia: Bool, troca: AcaoDoScroll)] = [
            (true, false, .trocarSecao(avancando: true)),
            (true, true, .trocarSecao(avancando: true)),
            (false, true, .trocarFaixa(proxima: true)),
            (false, false, .engolir),
        ]
        for e in esperado {
            let nome = "swipe lateral (expandido=\(e.expandido) mídia=\(e.temMidia))"
            let acoes = simular(eventos, expandido: e.expandido, temMidia: e.temMidia).map { $0.acao }
            exigir(acoes == [.engolir, .engolir, e.troca, .engolir, .repassar,
                             .engolir, .engolir, .repassar],
                   "\(nome): devia ser engolir, engolir, \(e.troca), engolir, repassar (fim), engolir, engolir, repassar (fim da inércia); deu \(acoes)")
        }
    }
}
