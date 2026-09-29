//
//  tools/apiguardcheck.swift — self-check do guarda da API local contra
//  requisições de navegador (CSRF e DNS rebinding). NÃO faz parte do alvo do app.
//
//  Rodar:
//  xcrun swiftc -parse-as-library -swift-version 5 \
//    Knobler/NotchAPIGuard.swift tools/apiguardcheck.swift \
//    -o /tmp/apiguardcheck && /tmp/apiguardcheck
//

import Foundation

@main
struct APIGuardCheck {
    static let porta: UInt16 = 4477

    static func main() {
        // curl, scripts e hooks: passam
        passa("POST /notify HTTP/1.1\r\nHost: localhost:4477\r\nUser-Agent: curl/8.7.1\r\nContent-Type: application/x-www-form-urlencoded", "curl em localhost")
        passa("GET /status HTTP/1.1\r\nHost: 127.0.0.1:4477", "curl em 127.0.0.1")
        passa("GET /status HTTP/1.1\r\nHost: 127.0.0.1", "Host sem porta")
        passa("GET /status HTTP/1.1\r\nhost: LOCALHOST:4477", "nome e valor sem diferenciar caixa")
        passa("GET /status HTTP/1.1", "sem Host (nc cru)")
        passa("GET /status HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nSec-Fetch-Site: none\r\nSec-Fetch-Mode: navigate", "URL digitada no navegador")
        passa("POST /agent-requests HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nSec-Fetch-Mode: cors\r\nAuthorization: Bearer x", "fetch do Node (ponte do Codex)")

        // DNS rebinding (#15)
        recusa("GET /status HTTP/1.1\r\nHost: evil.com:4477", "Host de outro domínio")
        recusa("GET /status HTTP/1.1\r\nHost: 127.0.0.1.evil.com:4477", "Host com prefixo de loopback")
        recusa("GET /status HTTP/1.1\r\nHost: localhost:4478", "porta errada")
        recusa("GET /status HTTP/1.1\r\nHost: localhost:4477\r\nHost: evil.com", "Host duplicado")

        // CSRF (#14)
        recusa("POST /keyboard/lock HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nOrigin: https://evil.com", "Origin de outro site")
        recusa("POST /keyboard/lock HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nOrigin: null", "Origin null (sandbox/file)")
        recusa("POST /mirror HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nOrigin: http://localhost:4478", "Origin de outra porta local")
        passa("POST /notify HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nOrigin: http://127.0.0.1:4477", "Origin da própria API")
        recusa("GET /ask/x HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nSec-Fetch-Site: cross-site", "GET cross-site (<img>)")
        recusa("GET /ask/x HTTP/1.1\r\nHost: 127.0.0.1:4477\r\nSec-Fetch-Site: same-site", "GET same-site")

        print("✅ apiguardcheck ok")
    }

    static func passa(_ headers: String, _ caso: String) {
        let motivo = NotchAPIGuard.rejeicao(headers: headers, porta: porta)
        precondition(motivo == nil, "deveria passar: \(caso) (recusou: \(motivo ?? ""))")
    }

    static func recusa(_ headers: String, _ caso: String) {
        precondition(NotchAPIGuard.rejeicao(headers: headers, porta: porta) != nil,
                     "deveria recusar: \(caso)")
    }
}
