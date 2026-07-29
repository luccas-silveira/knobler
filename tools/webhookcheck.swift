//
//  tools/webhookcheck.swift — self-check da decisão de pareamento do relay.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookKeychainStore.swift tools/webhookcheck.swift \
//    -o /tmp/webhookcheck && /tmp/webhookcheck
//

import Foundation

@main
struct WebhookCheck {
    static func main() {
        testReady()
        testLocked()
        testHalfOpen()
        testUnpaired()
        print("✅ webhookcheck ok")
    }

    /// Os dois segredos abriram: é o caminho feliz, com o link publicável.
    static func testReady() {
        let s = WebhookKeychainStore.pairingState(
            load: { $0 == .publishToken ? "tok" : "sec" },
            exists: { _ in true })
        assert(s == .ready(publishToken: "tok"), "dois segredos abertos → ready")
    }

    /// O item está lá mas a ACL não abre: NÃO pode virar registro novo, senão o
    /// link público que o usuário já colou lá fora morre em silêncio.
    static func testLocked() {
        let s = WebhookKeychainStore.pairingState(
            load: { _ in nil },
            exists: { _ in true })
        assert(s == .locked, "existe mas não abre → locked")
    }

    /// Meio segredo não serve pra nada: sem o deviceSecret não há como autenticar.
    static func testHalfOpen() {
        let s = WebhookKeychainStore.pairingState(
            load: { $0 == .publishToken ? "tok" : nil },
            exists: { _ in true })
        assert(s == .locked, "só metade dos segredos → locked")
    }

    /// Keychain limpo: primeiro uso, pode registrar.
    static func testUnpaired() {
        let s = WebhookKeychainStore.pairingState(
            load: { _ in nil },
            exists: { _ in false })
        assert(s == .unpaired, "keychain vazio → unpaired")
    }
}
