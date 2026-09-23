//
//  tools/sharingcheck.swift — self-check do envio (Sharing) e das regras puras
//  do interceptor (NotificationRules): botão de ação, AirDrop, silêncio, e o
//  conteúdo do banner.
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
        testLimpo()
        testAppNameDaDescricao()
        testPartesDoBanner()
        testHaQuanto()
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
        for acao in ["Aceitar", "Recusar", "Accept", "Decline", "Responder", "Marcar como lida"] {
            assert(NotificationRules.isActionTitle(acao), "\(acao) é ação")
        }
        for fechar in ["Fechar", "Close", "Limpar", "Clear", "Clear All", "fechar"] {
            assert(!NotificationRules.isActionTitle(fechar), "\(fechar) não é ação")
        }
        assert(!NotificationRules.isActionTitle(""), "vazio não vira botão")
        assert(!NotificationRules.isActionTitle("   "), "só espaço não vira botão")
    }

    /// O WhatsApp manda U+200E grudado no nome do app e no texto; sem limpar,
    /// "‎WhatsApp" nunca casa com o processo e o card perde ícone e clique.
    static func testLimpo() {
        assert(NotificationRules.limpo("\u{200E}WhatsApp") == "WhatsApp")
        assert(NotificationRules.limpo("  Mail \n") == "Mail")
        assert(NotificationRules.limpo("\u{200E}📷 \u{200E}Foto") == "📷 Foto")
        assert(NotificationRules.limpo("\u{200E}") == "")
        // emoji composto depende de ZWJ e VS16, que também são "ignoráveis"
        assert(NotificationRules.limpo("❤️ te amo") == "❤️ te amo", "coração perdeu o VS16")
        assert(NotificationRules.limpo("👨‍👩‍👧") == "👨‍👩‍👧", "família perdeu o ZWJ")
    }

    /// O banner do Tahoe não tem o app nos textos: ele vem no começo da
    /// descrição, "App, título, corpo", sem escape de vírgula.
    static func testAppNameDaDescricao() {
        assert(NotificationRules.appName(fromDescription: "WhatsApp, Ana, Oi") == "WhatsApp")
        assert(NotificationRules.appName(fromDescription: "\u{200E}WhatsApp, Ana, Grupo, Teste") == "WhatsApp",
               "formato real, lido do banner em 2026-09-23")
        assert(NotificationRules.appName(fromDescription: "AirDrop, Recebendo uma foto") == "AirDrop")
        assert(NotificationRules.appName(fromDescription: "Mail, Oi, tudo bem, e aí") == "Mail",
               "vírgula no conteúdo não muda o app")
        assert(NotificationRules.appName(fromDescription: "SemVirgula") == nil,
               "sem separador não dá pra saber o que é app")
        assert(NotificationRules.appName(fromDescription: ", corpo") == nil, "nome vazio")
        assert(NotificationRules.appName(fromDescription: "") == nil)
        assert(NotificationRules.appName(fromDescription: nil) == nil)
    }

    static func testPartesDoBanner() {
        typealias T = NotificationRules.TextoDoBanner
        func p(_ t: [T]) -> (String, String?, String)? {
            NotificationRules.partes(t).map { ($0.title, $0.subtitle, $0.body) }
        }
        // rotulado: a ordem na árvore não importa, a hora some
        let r = p([T(id: "date", valor: "agora"), T(id: "body", valor: "Oi"),
                   T(id: "subtitle", valor: "Grupo da família"), T(id: "title", valor: "Ana")])
        assert(r?.0 == "Ana" && r?.1 == "Grupo da família" && r?.2 == "Oi")
        let semSub = p([T(id: "title", valor: "Ana"), T(id: "body", valor: "Oi")])
        assert(semSub?.0 == "Ana" && semSub?.1 == nil && semSub?.2 == "Oi")
        let soSub = p([T(id: "subtitle", valor: "Grupo"), T(id: "body", valor: "oi")])
        assert(soSub?.0 == "Grupo" && soSub?.1 == nil && soSub?.2 == "oi",
               "sem título, o subtítulo sobe")
        let soCorpo = p([T(id: "body", valor: "oi"), T(id: "date", valor: "agora")])
        assert(soCorpo?.0 == "oi" && soCorpo?.2 == "", "só corpo vira título")
        assert(p([T(id: "date", valor: "agora")]) == nil, "só hora não é notificação")
        assert(p([T(id: "title", valor: "\u{200E}")]) == nil, "texto invisível é vazio")
        let limpo = p([T(id: "title", valor: "\u{200E}Ana"), T(id: "body", valor: "\u{200E}📷 Foto")])
        assert(limpo?.0 == "Ana" && limpo?.2 == "📷 Foto")
        // sem rótulo nenhum: posição
        assert(p([]) == nil)
        let um = p([T(id: nil, valor: "Só título")])
        assert(um?.0 == "Só título" && um?.1 == nil && um?.2 == "")
        let dois = p([T(id: nil, valor: "Ana"), T(id: nil, valor: "Oi")])
        assert(dois?.0 == "Ana" && dois?.1 == nil && dois?.2 == "Oi")
        // 3+ sem rótulo: macOS antigo, [app, título, corpo…] como sempre foi
        let quatro = NotificationRules.partes([T(id: nil, valor: "App"), T(id: nil, valor: "B"),
                                               T(id: nil, valor: "C"), T(id: nil, valor: "D")])
        assert(quatro?.app == "App" && quatro?.title == "B" && quatro?.subtitle == nil
               && quatro?.body == "C — D")
        assert(NotificationRules.partes([T(id: "title", valor: "x")])?.app == nil,
               "rotulado nunca tira o app dos textos")
    }

    static func testHaQuanto() {
        let t0 = Date(timeIntervalSince1970: 1_000_000)
        func h(_ s: TimeInterval) -> String { NotificationRules.haQuanto(t0, agora: t0 + s) }
        assert(h(0) == "agora")
        assert(h(59) == "agora")
        assert(h(60) == "há 1 min")
        assert(h(3599) == "há 59 min")
        assert(h(3600) == "há 1 h")
        assert(h(-30) == "agora", "relógio pra trás não vira número negativo")
    }
}
