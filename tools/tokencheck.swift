// Gate do arquivo do token de agente (Knobler/TokenDeAgente.swift).
//
// A pasta `Application Support/Knobler` é compartilhada, e numa instalação
// limpa quem chega antes (o registro de desempenho) a cria com o modo do
// umask, 0755. O token tem que deixar a pasta em 0700 mesmo assim, e o
// arquivo nunca existir com modo diferente de 0600 — nem com umask 0.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/TokenDeAgente.swift tools/tokencheck.swift \
//     -o /tmp/tokencheck && /tmp/tokencheck

import Foundation

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

private func modo(_ url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1
}

@main
enum Gate {
    static func main() {
        let base = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("tokencheck-\(getpid())", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }

        let token = TokenDeAgente.gerar()
        exigir(token != nil && Data(base64Encoded: token!)?.count == 32, "token não tem 32 bytes")
        exigir(TokenDeAgente.gerar() != token, "dois tokens iguais")

        // A pasta já existe com 0755 (o desempenho chegou antes) e o umask é 0:
        // o pior caso pros dois modos.
        let pasta = base.appendingPathComponent("Knobler", isDirectory: true)
        try! FileManager.default.createDirectory(at: pasta, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o755])
        exigir(modo(pasta) == 0o755, "preparo: a pasta não nasceu 0755")
        let umaskAnterior = umask(0)
        defer { umask(umaskAnterior) }

        try! TokenDeAgente.gravar(token!, em: pasta)
        let arquivo = pasta.appendingPathComponent(TokenDeAgente.nomeDoArquivo)
        exigir(modo(pasta) == 0o700, String(format: "pasta ficou %o, esperado 700", modo(pasta)))
        exigir(modo(arquivo) == 0o600, String(format: "arquivo ficou %o, esperado 600", modo(arquivo)))
        exigir((try? String(contentsOf: arquivo, encoding: .utf8)) == token, "conteúdo diferente do token")

        // Regravar (cada `.ready`) troca o conteúdo, mantém os modos e não deixa
        // temporário pra trás.
        try! TokenDeAgente.gravar("outro", em: pasta)
        exigir((try? String(contentsOf: arquivo, encoding: .utf8)) == "outro", "regravar não trocou o conteúdo")
        exigir(modo(arquivo) == 0o600, "regravar mudou o modo do arquivo")
        let sobras = (try? FileManager.default.contentsOfDirectory(atPath: pasta.path)) ?? []
        exigir(sobras == [TokenDeAgente.nomeDoArquivo], "sobrou arquivo na pasta: \(sobras)")

        // Pasta que nem existe: nasce 0700.
        let nova = base.appendingPathComponent("nova/Knobler", isDirectory: true)
        try! TokenDeAgente.gravar("x", em: nova)
        exigir(modo(nova) == 0o700, String(format: "pasta nova ficou %o", modo(nova)))

        print("tokencheck: ok")
    }
}
