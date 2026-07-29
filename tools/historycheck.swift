//
//  tools/historycheck.swift — self-check do histórico de notificações.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/NotchNotification.swift Knobler/NotificationHistory.swift \
//    tools/historycheck.swift -o /tmp/historycheck && /tmp/historycheck
//

import AppKit

@main
struct HistoryCheck {
    static func main() {
        testOrdem()
        testPoda()
        testWebhookSubstitui()
        testMesmoIDUmaVez()
        testTetoDeLinhas()
        testPersistencia()
        testGesto()
        testZonaDoGesto()
        testInicioDeGesto()
        print("✅ historycheck ok")
    }

    /// Mais recente primeiro — a lista é lida de cima pra baixo.
    static func testOrdem() {
        let h = NotificationHistory()
        h.record(NotchNotification(appName: "A", title: "primeira", body: ""))
        h.record(NotchNotification(appName: "B", title: "segunda", body: ""))
        assert(h.items.map(\.title) == ["segunda", "primeira"], "ordem invertida")
    }

    /// Poda por idade: 23 h fica, 25 h sai. `prune(now:)` recebe o agora pra
    /// não precisar esperar um dia dentro do teste.
    static func testPoda() {
        let h = NotificationHistory()
        h.record(NotchNotification(appName: "A", title: "velha", body: ""))
        h.record(NotchNotification(appName: "B", title: "nova", body: ""))
        h.prune(now: Date().addingTimeInterval(24 * 3600 + 60))
        assert(h.items.isEmpty, "tudo com mais de 24 h devia sair")

        let h2 = NotificationHistory()
        h2.record(NotchNotification(appName: "A", title: "recente", body: ""))
        h2.prune(now: Date().addingTimeInterval(23 * 3600))
        assert(h2.items.count == 1, "23 h ainda está dentro da janela")
    }

    /// Barra de progresso que atualiza 40 vezes é UMA linha, não 40.
    static func testWebhookSubstitui() {
        let h = NotificationHistory()
        h.record(NotchNotification(appName: "Deploy", title: "10%", body: "", webhookID: "d1"))
        h.record(NotchNotification(appName: "Deploy", title: "90%", body: "", webhookID: "d1"))
        h.record(NotchNotification(appName: "Outro", title: "x", body: "", webhookID: "d2"))
        assert(h.items.count == 2, "mesmo webhookID devia substituir")
        assert(h.items.first?.title == "x", "mais recente primeiro")

        // Interleaved: plain + webhook + webhook. O mais recente deve estar no topo.
        let h2 = NotificationHistory()
        h2.record(NotchNotification(appName: "A", title: "plain", body: ""))
        h2.record(NotchNotification(appName: "B", title: "w1", body: "", webhookID: "w1"))
        h2.record(NotchNotification(appName: "C", title: "w2", body: "", webhookID: "w2"))
        assert(h2.items[0].title == "w2", "mais recente primeiro em interlacing")
    }

    /// Multi-monitor: o enqueue roda uma vez por tela com a MESMA notificação.
    static func testMesmoIDUmaVez() {
        let h = NotificationHistory()
        let n = NotchNotification(appName: "A", title: "única", body: "")
        h.record(n)
        h.record(n)
        assert(h.items.count == 1, "mesmo id não pode duplicar")
    }

    /// Teto de linhas: a poda por idade não segura uma rajada de webhookIDs
    /// distintos dentro da mesma janela de 24 h. O que sobra é o mais recente.
    static func testTetoDeLinhas() {
        let h = NotificationHistory()
        for i in 0..<400 {
            h.record(NotchNotification(appName: "Rajada", title: "\(i)", body: "",
                                       webhookID: "w\(i)"))
        }
        assert(h.items.count == 300, "teto de 300 linhas, veio \(h.items.count)")
        assert(h.items.first?.title == "399", "o topo continua sendo o mais recente")
        assert(h.items.last?.title == "100", "quem cai é o mais antigo")
    }

    /// O histórico virou o único destino de uma notificação silenciada em
    /// reunião: perder no restart é perder a notificação inteira.
    static func testPersistencia() {
        let arquivo = FileManager.default.temporaryDirectory
            .appendingPathComponent("historycheck-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: arquivo) }

        // arquivo que ainda não existe = primeira execução
        assert(NotificationHistory(arquivo: arquivo).items.isEmpty,
               "sem arquivo, histórico nasce vazio")

        let h = NotificationHistory(arquivo: arquivo)
        h.record(NotchNotification(appName: "A", title: "primeira", body: "corpo 1"))
        h.record(NotchNotification(appName: "B", title: "segunda", body: "",
                                   openURL: "https://exemplo.com",
                                   iconColor: .systemRed,
                                   actionTitles: ["Responder"], actionToken: UUID()))
        h.flush()

        let lido = NotificationHistory(arquivo: arquivo)
        assert(lido.items.map(\.title) == ["segunda", "primeira"],
               "round-trip preserva conteúdo e ordem, veio \(lido.items.map(\.title))")

        // o id é a chave do dedupe: sem ele, a mesma notificação voltaria a
        // entrar quando o webhook reenviasse
        assert(lido.items[0].id == h.items[0].id, "id sobrevive ao disco")
        let antes = lido.items.count
        lido.record(h.items[0])
        assert(lido.items.count == antes, "item restaurado não duplica no record")

        // a poda por idade lê esta data — carimbar uma nova no load daria 24 h
        // extras de vida a cada restart
        assert(abs(lido.items[0].date.timeIntervalSince(h.items[0].date)) < 0.001,
               "date sobrevive ao disco")

        assert(lido.items[0].openURL == "https://exemplo.com",
               "openURL sobrevive: é dado, e o clique continua valendo")
        let cor = lido.items[0].iconColor?.usingColorSpace(.sRGB)
        assert(cor != nil, "iconColor volta do disco")
        assert(abs((cor?.redComponent ?? 0) - (NSColor.systemRed.usingColorSpace(.sRGB)?.redComponent ?? -1)) < 0.01,
               "a cor volta igual")

        // o token aponta pra AXUIElement do processo anterior: restaurar o botão
        // daria um botão que não faz nada
        assert(lido.items[0].actionTitles.isEmpty, "ação não volta do disco")
        assert(lido.items[0].actionToken == nil, "token não volta do disco")

        // arquivo de ontem não pode ressuscitar item vencido
        let velho = NotchNotification(appName: nil, title: "ontem", body: "",
                                      date: Date().addingTimeInterval(-25 * 3600))
        let novo = NotchNotification(appName: nil, title: "agora", body: "")
        try? JSONEncoder().encode([velho, novo]).write(to: arquivo)
        let podado = NotificationHistory(arquivo: arquivo)
        assert(podado.items.map(\.title) == ["agora"],
               "a poda de 24 h roda no load, veio \(podado.items.map(\.title))")

        // disco corrompido não pode derrubar o app nem travar o histórico
        try? Data("{lixo".utf8).write(to: arquivo)
        let corrompido = NotificationHistory(arquivo: arquivo)
        assert(corrompido.items.isEmpty, "arquivo corrompido carrega vazio")
        corrompido.record(NotchNotification(appName: nil, title: "depois", body: ""))
        corrompido.flush()
        assert(NotificationHistory(arquivo: arquivo).items.map(\.title) == ["depois"],
               "arquivo ruim é sobrescrito pela próxima escrita")

        // nil = harness (gate e snapshot): não toca disco nenhum
        let semDisco = NotificationHistory()
        semDisco.record(NotchNotification(appName: nil, title: "memória", body: ""))
        semDisco.flush()
        assert(semDisco.items.count == 1, "sem arquivo o histórico funciona igual")
    }

    /// Puxão pra baixo numa passada só: 24 pt abre o card e é só isso — o
    /// histórico virou uma seção da faixa, então não há mais degrau de 120 pt.
    /// Como o alvo é função pura do acumulado, recuar os dedos dentro do mesmo
    /// gesto desfaz sem precisar de máquina de estados.
    static func testGesto() {
        assert(NotchGesture.verticalTarget(accumY: 10, accumX: 0) == nil, "ruído não age")
        assert(NotchGesture.verticalTarget(accumY: -10, accumX: 0) == nil, "ruído não age")
        assert(NotchGesture.verticalTarget(accumY: 30, accumX: 0) == .expanded, "30 pt abre o card")
        assert(NotchGesture.verticalTarget(accumY: 25, accumX: 0) == .expanded, "25 pt já abre")
        // a cortina do histórico foi aposentada: o histórico virou uma seção
        // como as outras, e um segundo caminho pra ele seria redundante
        assert(NotchGesture.verticalTarget(accumY: 130, accumX: 0) == .expanded,
               "puxão longo não é mais cortina")
        // puxão gigante também: não há mais degrau nenhum acima do card
        assert(NotchGesture.verticalTarget(accumY: 900, accumX: 0) == .expanded,
               "puxão gigante continua sendo só o card")
        assert(NotchGesture.verticalTarget(accumY: -30, accumX: 0) == .closed, "pra cima fecha")
        // limiares exatos: o limite é aberto (>), não fechado (>=)
        assert(NotchGesture.verticalTarget(accumY: 24, accumX: 0) == nil, "24 pt ainda é ruído")
        assert(NotchGesture.verticalTarget(accumY: 120, accumX: 0) == .expanded, "120 pt ainda é card")
        // guarda de diagonal: swipe quase horizontal não mexe no card
        assert(NotchGesture.verticalTarget(accumY: 30, accumX: 60) == nil, "diagonal não abre")
        assert(NotchGesture.verticalTarget(accumY: -30, accumX: 60) == nil, "diagonal não fecha")
    }

    /// A zona vertical do gesto. É o que decide se o scroll sobre aquele ponto
    /// da tela é do notch ou da janela de trás, e por isso um erro aqui não
    /// aparece como bug de gesto: aparece como "o scroll simplesmente não
    /// responde nessa tira". Os números vêm de um notch de 32 pt.
    static func testZonaDoGesto() {
        let topo: CGFloat = 1000 // screen.frame.maxY

        // card fechado: a zona é o notch mais 10 pt de folga
        assert(NotchGesture.inZone(mouseY: 995, screenMaxY: topo, expanded: false,
                                   alturaAtual: 32, notchHeight: 32),
               "dentro do notch fechado")
        assert(NotchGesture.inZone(mouseY: 959, screenMaxY: topo, expanded: false,
                                   alturaAtual: 32, notchHeight: 32),
               "os 10 pt de folga do notch fechado contam")
        assert(!NotchGesture.inZone(mouseY: 957, screenMaxY: topo, expanded: false,
                                    alturaAtual: 32, notchHeight: 32),
               "abaixo do notch + folga já é da janela de trás")

        // card aberto: a zona tem que cobrir a folga de hover, senão a tira
        // final responde ao hover mas não ao scroll — foi o bug desta task
        assert(NotchGesture.inZone(mouseY: topo - 272, screenMaxY: topo, expanded: true,
                                   alturaAtual: 272, notchHeight: 32),
               "a base desenhada do card está na zona")
        assert(NotchGesture.inZone(mouseY: topo - 272 - NotchGesture.folgaDeHover + 1,
                                   screenMaxY: topo, expanded: true,
                                   alturaAtual: 272, notchHeight: 32),
               "a folga de hover do card também está na zona")
        assert(!NotchGesture.inZone(mouseY: topo - 272 - NotchGesture.folgaDeHover - 1,
                                    screenMaxY: topo, expanded: true,
                                    alturaAtual: 272, notchHeight: 32),
               "abaixo da folga o card acabou")

        // a altura vem do VM, então cada seção move a zona junto
        assert(NotchGesture.inZone(mouseY: topo - 260, screenMaxY: topo, expanded: true,
                                   alturaAtual: 272, notchHeight: 32),
               "seção alta: a zona acompanha")
        assert(!NotchGesture.inZone(mouseY: topo - 260, screenMaxY: topo, expanded: true,
                                    alturaAtual: 202, notchHeight: 32),
               "seção baixa: a zona encolhe junto")

        // eixo horizontal: aberto, a zona tem que cobrir a largura desenhada do
        // card MAIS a folga de hover dos dois lados — o mesmo modo de falha do
        // eixo vertical, e por isso derivada das mesmas constantes.
        let meia = NotchGesture.zoneWidth(expanded: true) / 2
        assert(NotchGesture.zoneWidth(expanded: true)
                == NotchGesture.larguraDoCard + 2 * NotchGesture.folgaDeHover,
               "a zona horizontal do card aberto não cobre a folga de hover")
        assert(NotchGesture.naZonaHorizontal(mouseX: 500 + meia - 1, screenMidX: 500,
                                             expanded: true),
               "a borda do card aberto está na zona")
        assert(!NotchGesture.naZonaHorizontal(mouseX: 500 + meia + 1, screenMidX: 500,
                                              expanded: true),
               "fora da borda do card já é da janela de trás")
        assert(NotchGesture.naZonaHorizontal(mouseX: 500 - meia + 1, screenMidX: 500,
                                             expanded: true),
               "a zona é simétrica em volta do meio da tela")
        assert(!NotchGesture.naZonaHorizontal(mouseX: 500 + 201, screenMidX: 500,
                                              expanded: false),
               "fechado a zona é bem mais estreita que o card")

        // altura ainda não publicada: a zona encolhe, mas não vira negativa —
        // o topo continua respondendo em vez de o gesto morrer
        assert(NotchGesture.inZone(mouseY: 995, screenMaxY: topo, expanded: true,
                                   alturaAtual: 0, notchHeight: 32),
               "altura zero não degenera a zona")
    }

    /// Reconhecer o começo do gesto é o que zera o acumulador e a flag da
    /// cortina. Fora do trackpad não existe `.began`, então o resto da tabela
    /// é o que impede o acumulador de crescer pra sempre.
    static func testInicioDeGesto() {
        let g = NotchGesture.gestureGap
        // trackpad: .began sempre começa
        assert(NotchGesture.isGestureStart(
            began: true, momentum: false, sinceLastEvent: 0, previousInZone: true,
            hasPhase: true),
            ".began começa gesto")
        // inércia NUNCA começa: ela chega depois dos dedos saírem
        assert(!NotchGesture.isGestureStart(
            began: false, momentum: true, sinceLastEvent: 99, previousInZone: true,
            hasPhase: true),
            "inércia não começa gesto")
        // rodinha: sem fase nenhuma, só a pausa separa dois gestos
        assert(NotchGesture.isGestureStart(
            began: false, momentum: false, sinceLastEvent: g + 0.01, previousInZone: true,
            hasPhase: false),
            "pausa longa começa gesto novo (mouse de rodinha)")
        assert(!NotchGesture.isGestureStart(
            began: false, momentum: false, sinceLastEvent: g / 2, previousInZone: true,
            hasPhase: false),
            "rolagem contínua é o MESMO gesto — é o puxão longo")
        // trackpad com os dedos PARADOS na superfície: o macOS não manda evento
        // enquanto ninguém se mexe, então o `.changed` que retoma o puxão vem
        // depois de uma pausa maior que o gap. Ainda é o MESMO gesto — o
        // relógio não pode valer pra quem tem fase, senão o "numa passada só"
        // perde o acumulado e os 120 pt do histórico viram card.
        assert(!NotchGesture.isGestureStart(
            began: false, momentum: false, sinceLastEvent: g + 0.1, previousInZone: true,
            hasPhase: true),
            "hesitar sem soltar os dedos NÃO começa gesto novo")
        // gesto que começou fora da zona e entrou arrastando: o .began dele foi
        // descartado, então o primeiro evento dentro conta como começo
        assert(NotchGesture.isGestureStart(
            began: false, momentum: false, sinceLastEvent: 0, previousInZone: false,
            hasPhase: true),
            "entrar na zona no meio do gesto conta como começo")
    }
}
