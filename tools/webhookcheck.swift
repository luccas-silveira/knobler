//
//  tools/webhookcheck.swift — self-check da decisão de pareamento do relay.
//  NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/WebhookKeychainStore.swift Knobler/WebhookClient.swift \
//    Knobler/NotchNotification.swift tools/webhookcheck.swift \
//    -o /tmp/webhookcheck && /tmp/webhookcheck
//

import Foundation

@main
struct WebhookCheck {
    static func main() async {
        testReady()
        testLocked()
        testHalfOpen()
        testUnpaired()
        await testExclusao()
        print("✅ webhookcheck ok")
    }

    static func testExclusao() async {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RelayProtocol.self]
        var tokens = ["teste": "token-descartavel"]
        let client = WebhookClient(sessionConfiguration: config,
            loadDeviceSecret: { "segredo-descartavel" },
            deleteProfileToken: { tokens.removeValue(forKey: $0) })
        for status in [500, 401, 404, 302, 0] {
            RelayProtocol.status = status
            let deleted = await client.deleteProfile("teste")
            assert(!deleted)
            assert(tokens["teste"] != nil, "DELETE malsucedido apagou o token local: \(status)")
            let profile = await client.getProfile("teste")
            assert(profile == nil, "HTTP malsucedido não é dado válido")
        }
        for status in [200, 204] {
            tokens["teste"] = "token-descartavel"
            RelayProtocol.status = status
            let deleted = await client.deleteProfile("teste")
            assert(deleted)
            assert(tokens.isEmpty, "DELETE confirmado deve apagar o token")
        }
        client.shutdown()
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

/// Intercepta o URLSession real; nenhum request sai da máquina e nenhum Keychain é acessado.
private final class RelayProtocol: URLProtocol {
    static var status = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer segredo-descartavel")
        if Self.status == 0 {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        } else {
            let response = HTTPURLResponse(url: request.url!, statusCode: Self.status,
                                           httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if Self.status != 204 { client?.urlProtocol(self, didLoad: Data("{\"ok\":true}".utf8)) }
            client?.urlProtocolDidFinishLoading(self)
        }
    }
    override func stopLoading() {}
}
