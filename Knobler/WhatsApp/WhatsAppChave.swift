import Foundation

// Arquivo da chave da ponte do WhatsApp, porta configurável e leitura da
// resposta de `GET /` (docs/whatsapp-ponte.md: chave em :50-66, tabela em
// :441-447). O Knobler nunca cria nem grava o arquivo da chave: quem cria é a
// ponte.

/// Chave da ponte em `~/Library/Application Support/whatsapp-bridge/api-key`.
enum WAChaveDaPonte {
    /// Calcular o caminho não mexe no disco (sem `create: true`, diferente de
    /// `TokenDeAgente.pastaPadrao`): a pasta é da ponte.
    static var caminhoPadrao: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("whatsapp-bridge", isDirectory: true)
            .appendingPathComponent("api-key", isDirectory: false)
    }

    /// `true` só se o caminho é um arquivo (pasta não conta).
    static func existe(em url: URL = caminhoPadrao) -> Bool {
        var pasta: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &pasta) && !pasta.boolValue
    }

    /// Conteúdo com espaço e quebra cortados das pontas, ou `nil` se o arquivo
    /// falta, não se lê ou só tem espaço. Não valida formato: o contrato manda
    /// só cortar e guardar.
    static func ler(em url: URL = caminhoPadrao) -> String? {
        guard existe(em: url),
              let dados = try? Data(contentsOf: url),
              let texto = String(data: dados, encoding: .utf8) else { return nil }
        let chave = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return chave.isEmpty ? nil : chave
    }
}

/// Endereço da ponte. A porta é configurável para o teste de desenvolvimento
/// com cópia do `store/` noutra porta (docs/whatsapp-ponte.md:1030-1032).
enum WAConfig {
    static let chavePorta = "whatsappPortaDaPonte"
    static let portaPadrao = 8099

    /// Porta gravada em `whatsappPortaDaPonte`, ou 8099 se ausente ou fora de 1...65535.
    static func porta(_ d: UserDefaults = .standard) -> Int {
        let p = d.integer(forKey: chavePorta)
        return (1...65535).contains(p) ? p : portaPadrao
    }

    static func base(porta: Int) -> URL {
        URL(string: "http://127.0.0.1:\(porta)")!
    }
}

/// O que o Knobler conclui da sonda de `GET /` (docs/whatsapp-ponte.md:441-447).
enum WAConclusaoDaSonda: Equatable {
    case presente(versao: String)
    case incompativel(contrato: Int)
    case chaveNaoConfere
    case foraDoAr
    case naoEAPonte
    case semChave

    /// `status` `nil` = conexão recusada ou tempo esgotado.
    static func concluir(status: Int?, corpo: Data?) -> WAConclusaoDaSonda {
        guard let status else { return .foraDoAr }
        switch status {
        case 401:
            return .chaveNaoConfere
        case 200:
            guard let corpo,
                  let id = try? WAJSON.decodificador.decode(WAIdentificacao.self, from: corpo),
                  id.servico == "whatsapp-ponte" else { return .naoEAPonte }
            return id.contrato == 1 ? .presente(versao: id.versao) : .incompativel(contrato: id.contrato)
        default:
            return .naoEAPonte
        }
    }

    var identificada: Bool {
        if case .presente = self { return true }
        return false
    }
}
