//
//  NotchAPIGuard.swift
//  Knobler
//
//  Recusa requisições que só um navegador faria à API local (127.0.0.1:4477).
//  Escutar só no loopback não basta: uma página aberta no navegador alcança
//  o loopback com "simple requests" (CSRF) e, com DNS rebinding, até lê as
//  respostas. curl, scripts e os hooks não mandam Origin nem Sec-Fetch-Site
//  e usam Host de loopback — seguem passando sem mudar nada.
//
//  Função pura (só Foundation) pra ser testada isolada: tools/apiguardcheck.swift.
//

import Foundation

enum NotchAPIGuard {
    /// Motivo da recusa, ou nil quando a requisição pode seguir.
    /// `headers`: tudo antes do "\r\n\r\n" (linha de requisição inclusa).
    static func rejeicao(headers: String, porta: UInt16) -> String? {
        let campos = headers.components(separatedBy: "\r\n").dropFirst()

        // DNS rebinding: o domínio do atacante resolve pra 127.0.0.1, mas o
        // navegador manda o Host dele. Sem Host (nc cru) não há navegador.
        for host in valores("host", em: campos) where !hostLoopback(host, porta: porta) {
            return "host não permitido"
        }
        // CSRF: todo POST de navegador leva Origin, até em mode: "no-cors".
        for origin in valores("origin", em: campos) where !origemLoopback(origin, porta: porta) {
            return "origem não permitida"
        }
        // GET cross-site (<img src=…/ask/<id>>) não leva Origin, mas leva
        // Sec-Fetch-Site. "none" = URL digitada na barra de endereço.
        // Sec-Fetch-Mode fica de fora: o fetch do Node (undici) manda.
        for site in valores("sec-fetch-site", em: campos)
        where !["none", "same-origin"].contains(site.lowercased()) {
            return "requisição de outro site"
        }
        return nil
    }

    private static func valores<S: Sequence>(_ nome: String, em campos: S) -> [String]
    where S.Element == String {
        campos.compactMap { linha in
            let partes = linha.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            guard partes.count == 2,
                  partes[0].trimmingCharacters(in: .whitespaces).lowercased() == nome
            else { return nil }
            return partes[1].trimmingCharacters(in: .whitespaces)
        }
    }

    private static let nomesLoopback = ["127.0.0.1", "localhost"]

    private static func hostLoopback(_ host: String, porta: UInt16) -> Bool {
        let host = host.lowercased()
        return nomesLoopback.contains { host == $0 || host == "\($0):\(porta)" }
    }

    private static func origemLoopback(_ origin: String, porta: UInt16) -> Bool {
        let origin = origin.lowercased()
        return nomesLoopback.contains { origin == "http://\($0):\(porta)" }
    }
}
