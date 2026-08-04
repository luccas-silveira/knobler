//
//  tools/sharingcheck.swift — self-check do envio (Sharing) e da regra que
//  decide o que é botão de ação num alerta do sistema (NotificationInterceptor).
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/Sharing.swift Knobler/NotificationRules.swift tools/sharingcheck.swift -o /tmp/sharingcheck \
//    && /tmp/sharingcheck
//

import AppKit
import Foundation

@main
struct SharingCheck {
    static func main() {
        testExistingFilter()
        testActionTitle()
        testAirDropLabel()
        testAirDropCancel()
        testSilenciarEmReuniao()
        testMicIndicaChamada()
        print("✅ sharingcheck ok")
    }

    /// O limiar é o que separa "estou numa call" de "abri a aba e o navegador
    /// testou o microfone por um segundo".
    static func testMicIndicaChamada() {
        let acendeu = Date(timeIntervalSince1970: 2_000_000)
        func chamada(_ segundos: TimeInterval, desde: Date? = acendeu) -> Bool {
            NotificationRules.micIndicaChamada(
                desde: desde, agora: acendeu.addingTimeInterval(segundos))
        }

        assert(!chamada(0, desde: nil), "microfone apagado nunca é chamada")
        assert(!chamada(0), "acabou de acender: não é chamada")
        assert(!chamada(5), "cinco segundos é teste de microfone, não call")
        assert(chamada(20), "no limiar em ponto já conta")
        assert(chamada(600), "dez minutos de microfone é call")
    }

    /// Silenciar o notch por engano é pior que não silenciar: você perde a
    /// notificação e não sabe que perdeu.
    static func testSilenciarEmReuniao() {
        let inicio = Date(timeIntervalSince1970: 1_000_000)
        let fim = inicio.addingTimeInterval(3600)
        func silencia(
            allDay: Bool = false, call: Bool = true, agora: Date,
            de: Date = inicio, ate: Date = fim
        ) -> Bool {
            NotificationRules.silenciaOChat(
                isAllDay: allDay, start: de, end: ate, temLinkDeCall: call, agora: agora)
        }

        assert(silencia(agora: inicio.addingTimeInterval(600)), "reunião em curso silencia")
        assert(silencia(agora: inicio), "o instante do início já conta")
        assert(!silencia(agora: inicio.addingTimeInterval(-1)), "um segundo antes, não")
        assert(!silencia(agora: fim),
               "fim é exclusivo: às 15h, a reunião que ia até as 15h acabou")
        assert(!silencia(agora: fim.addingTimeInterval(600)), "depois do fim, não")

        assert(!silencia(call: false, agora: inicio.addingTimeInterval(600)),
               "evento sem link de call não silencia (almoço, aniversário)")
        assert(!silencia(allDay: true, agora: inicio.addingTimeInterval(600)),
               "evento de dia inteiro nunca silencia")

        // reunião de duração zero (convite mal formado) não pode prender o notch
        assert(!silencia(agora: inicio, de: inicio, ate: inicio),
               "evento de duração zero não silencia nada")
    }

    /// O card diz o que foi enviado: um arquivo pelo nome, vários pela contagem.
    static func testAirDropLabel() {
        let a = URL(fileURLWithPath: "/tmp/foto.png")
        let b = URL(fileURLWithPath: "/tmp/nota.txt")
        assert(Sharing.label(for: [a]) == "foto.png", "um arquivo: nome")
        assert(Sharing.label(for: [a, b]) == "2 arquivos", "vários: contagem")
    }

    /// Fechar a janela do AirDrop sem escolher destino chega no delegate como
    /// erro. Tratar isso como falha encheria o notch de card de erro toda vez
    /// que o usuário desistisse do envio.
    static func testAirDropCancel() {
        let cancelou = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        assert(AirDropSession.isCancel(cancelou), "cancelamento do usuário")

        let falhou = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError)
        assert(!AirDropSession.isCancel(falhou), "erro de escrita é falha de verdade")

        let outroDominio = NSError(domain: NSURLErrorDomain, code: NSUserCancelledError)
        assert(!AirDropSession.isCancel(outroDominio),
               "mesmo código em outro domínio não é o cancelamento do AppKit")
    }

    /// O shelf guarda caminhos, não arquivos: mandar pro AirDrop um path morto
    /// abriria a janela do sistema com nada dentro.
    static func testExistingFilter() {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sharingcheck-\(getpid())")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let vivo = dir.appendingPathComponent("vivo.txt")
        try! Data("oi".utf8).write(to: vivo)
        let morto = dir.appendingPathComponent("morto.txt")

        assert(Sharing.existing([vivo, morto]) == [vivo], "só o que existe passa")
        assert(Sharing.existing([morto]).isEmpty, "nada existe = lista vazia")
        assert(Sharing.existing([]).isEmpty)
        assert(Sharing.existing([vivo, vivo]).count == 2, "não deduplica (não é o papel dele)")
    }

    /// Espelhar o "Fechar" do alerta daria um botão inútil no card — e pior,
    /// clicar nele destruiria o alerta que estamos tentando preservar.
    static func testActionTitle() {
        assert(NotificationRules.isAirDrop(appName: "AirDrop", title: "Recebendo uma foto"),
               "o alerta real vem com appName=AirDrop")
        assert(NotificationRules.isAirDrop(appName: nil, title: "AirDrop"),
               "com um texto só, o AirDrop cai no título")
        assert(!NotificationRules.isAirDrop(appName: "WhatsApp", title: "Fulano"),
               "notificação comum não é AirDrop")

        for acao in ["Aceitar", "Recusar", "Accept", "Decline", "Responder", "Marcar como lida"] {
            assert(NotificationRules.isActionTitle(acao), "\(acao) é ação")
        }
        for fechar in ["Fechar", "Close", "Limpar", "Clear", "Clear All", "fechar"] {
            assert(!NotificationRules.isActionTitle(fechar), "\(fechar) não é ação")
        }
        assert(!NotificationRules.isActionTitle(""), "vazio não vira botão")
        assert(!NotificationRules.isActionTitle("   "), "só espaço não vira botão")
    }
}
