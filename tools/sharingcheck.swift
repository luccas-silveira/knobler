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
        print("✅ sharingcheck ok")
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
