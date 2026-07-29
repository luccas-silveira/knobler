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
        testGesto()
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

    /// Puxão longo numa passada só: 24 pt abre o card, 120 pt segue pro
    /// histórico. Como o alvo é função pura do acumulado, recuar os dedos
    /// dentro do mesmo gesto desfaz sem precisar de máquina de estados.
    static func testGesto() {
        assert(NotchGesture.verticalTarget(accumY: 10, accumX: 0) == nil, "ruído não age")
        assert(NotchGesture.verticalTarget(accumY: -10, accumX: 0) == nil, "ruído não age")
        assert(NotchGesture.verticalTarget(accumY: 30, accumX: 0) == .expanded, "30 pt abre o card")
        assert(NotchGesture.verticalTarget(accumY: 130, accumX: 0) == .history, "130 pt vai ao histórico")
        // mesmo gesto, dedos recuando: 130 → 30 volta ao card
        assert(NotchGesture.verticalTarget(accumY: 30, accumX: 0) == .expanded, "recuo volta ao card")
        assert(NotchGesture.verticalTarget(accumY: -30, accumX: 0) == .closed, "pra cima fecha")
        // limiares exatos: o limite é aberto (>), não fechado (>=)
        assert(NotchGesture.verticalTarget(accumY: 24, accumX: 0) == nil, "24 pt ainda é ruído")
        assert(NotchGesture.verticalTarget(accumY: 120, accumX: 0) == .expanded, "120 pt ainda é card")
        // guarda de diagonal: swipe quase horizontal não mexe no card
        assert(NotchGesture.verticalTarget(accumY: 30, accumX: 60) == nil, "diagonal não abre")
        assert(NotchGesture.verticalTarget(accumY: -30, accumX: 60) == nil, "diagonal não fecha")
    }

    /// Reconhecer o começo do gesto é o que zera o acumulador e a flag da
    /// cortina. Fora do trackpad não existe `.began`, então o resto da tabela
    /// é o que impede o acumulador de crescer pra sempre.
    static func testInicioDeGesto() {
        let g = NotchGesture.gestureGap
        // trackpad: .began sempre começa
        assert(NotchGesture.isGestureStart(
            began: true, momentum: false, sinceLastEvent: 0, previousInZone: true),
            ".began começa gesto")
        // inércia NUNCA começa: ela chega depois dos dedos saírem
        assert(!NotchGesture.isGestureStart(
            began: false, momentum: true, sinceLastEvent: 99, previousInZone: true),
            "inércia não começa gesto")
        // rodinha: sem fase nenhuma, só a pausa separa dois gestos
        assert(NotchGesture.isGestureStart(
            began: false, momentum: false, sinceLastEvent: g + 0.01, previousInZone: true),
            "pausa longa começa gesto novo (mouse de rodinha)")
        assert(!NotchGesture.isGestureStart(
            began: false, momentum: false, sinceLastEvent: g / 2, previousInZone: true),
            "rolagem contínua é o MESMO gesto — é o puxão longo")
        // gesto que começou fora da zona e entrou arrastando: o .began dele foi
        // descartado, então o primeiro evento dentro conta como começo
        assert(NotchGesture.isGestureStart(
            began: false, momentum: false, sinceLastEvent: 0, previousInZone: false),
            "entrar na zona no meio do gesto conta como começo")
    }
}
