//
//  TokenDeAgente.swift
//  Knobler
//
//  O segredo das solicitações de agente (`/agent-requests`): nasce por sessão,
//  vive só na memória do `NotchAPIServer` e num arquivo que os adaptadores
//  locais (hooks do Claude, ponte do Codex, `tools/knobler`) leem. Nunca vai
//  pra defaults, log ou saída de CLI.
//
//  O arquivo é gravado quando o listener fica `.ready` — a porta 4477 é desta
//  instância — e não antes: uma instância antiga que ainda segure a porta
//  continua atendendo os clientes com o token que eles já leem, em vez de
//  responder 401 a toda aprovação.
//
//  Só Foundation, pra ser testado isolado: tools/tokencheck.swift.
//

import Foundation
import Security

enum TokenDeAgente {
    static let nomeDoArquivo = "agent-request-token"

    /// 32 bytes aleatórios em base64. `nil` se o gerador do sistema falhar.
    static func gerar() -> String? {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return nil }
        return Data(bytes).base64EncodedString()
    }

    /// `~/Library/Application Support/Knobler`.
    static func pastaPadrao() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Knobler", isDirectory: true)
    }

    /// Grava o token com a pasta em 0700 e o arquivo em 0600 desde o primeiro
    /// byte. A pasta é compartilhada (registro de desempenho, provas do corte,
    /// histórico) e quem chega antes a cria com o modo do umask: o 0700 é
    /// imposto aqui mesmo com ela já existindo, o que também conserta
    /// instalações antigas. O arquivo nasce num temporário aberto com 0600 e
    /// troca de nome por cima do anterior — nunca existe com outro modo.
    static func gravar(_ token: String, em pasta: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: pasta, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: pasta.path)

        let destino = pasta.appendingPathComponent(nomeDoArquivo)
        let temporario = pasta.appendingPathComponent(".\(nomeDoArquivo).\(UUID().uuidString)")
        let fd = open(temporario.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let bytes = Array(token.utf8)
        let escritos = bytes.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
        let erroDaEscrita = errno
        close(fd)
        guard escritos == bytes.count else {
            unlink(temporario.path)
            throw POSIXError(POSIXErrorCode(rawValue: erroDaEscrita) ?? .EIO)
        }
        guard rename(temporario.path, destino.path) == 0 else {
            let erro = errno
            unlink(temporario.path)
            throw POSIXError(POSIXErrorCode(rawValue: erro) ?? .EIO)
        }
    }
}
