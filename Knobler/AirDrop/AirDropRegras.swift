import Foundation

enum AirDropFaseAlerta: Equatable { case recebendo, concluido }

enum AirDropFim: Equatable {
    case recebido([URL])
    /// o outro lado cancelou ou a conexão caiu: sem card de "Recebido"
    case interrompido
}

enum AirDropRegras {
    /// Nome de marca: o alerta diz "AirDrop" em qualquer idioma.
    static let marca = "airdrop"

    static func isAirDrop(appName: String?, title: String) -> Bool {
        [appName, title].contains { $0?.lowercased().contains(marca) == true }
    }

    /// O alerta "Recebendo" acompanha a transferência viva; o "Concluído" só
    /// nasce depois do fim — é o único que pode ser fechado.
    static func faseDoAlerta(appName: String?, title: String) -> AirDropFaseAlerta? {
        guard isAirDrop(appName: appName, title: title) else { return nil }
        let texto = "\(appName ?? "") \(title)".lowercased()
        // ponytail: pt/en só; outro idioma cai em .recebendo (seguro: nunca fecha)
        let fim = ["concluído", "concluido", "completed", "recebido:", "received:"]
        return fim.contains { texto.contains($0) } ? .concluido : .recebendo
    }

    /// `AXButton desc="iPhone (2), Enviando"` na janela "AirDrop".
    static func destino(deDescricao desc: String) -> (aparelho: String, enviado: Bool)? {
        guard let virgula = desc.range(of: ", ", options: .backwards) else { return nil }
        let aparelho = String(desc[..<virgula.lowerBound])
        switch desc[virgula.upperBound...].lowercased() {
        case "enviando", "sending": return (aparelho, false)
        case "enviado", "sent": return (aparelho, true)
        default: return nil
        }
    }

    static func rotulo(_ urls: [URL]) -> String {
        urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) arquivos"
    }
}

/// Progresso de recebimento agregado: o iPhone manda um álbum como N arquivos,
/// cada um com seu `NSProgress`. O notch mostra um anel só, com a média.
struct AirDropRecebimentoEstado {
    private var fracoes: [URL: Double] = [:]
    private var ordem: [URL] = []

    mutating func atualizar(_ url: URL, fracao: Double) {
        if fracoes[url] == nil { ordem.append(url) }
        fracoes[url] = fracao
    }

    mutating func encerrar(_ url: URL) -> AirDropFim? {
        guard fracoes[url] != nil else { return nil }
        let pendentes = fracoes.filter { $0.key != url && $0.value < 1 }
        guard pendentes.isEmpty else { return nil }
        let completo = fracoes.values.allSatisfy { $0 >= 1 }
        let urls = ordem
        fracoes = [:]; ordem = []
        return completo ? .recebido(urls) : .interrompido
    }

    var progresso: Double? {
        fracoes.isEmpty ? nil : fracoes.values.reduce(0, +) / Double(fracoes.count)
    }

    var rotulo: String? { ordem.isEmpty ? nil : AirDropRegras.rotulo(ordem) }
}

enum AirDropTexto {
    static func atividadeRecebendo() -> String { "Recebendo por AirDrop" }
    static func atividadeEnviando(destino: String?) -> String {
        destino.map { "Enviando pra \($0)" } ?? "Enviando por AirDrop"
    }
    static func cardEnviado(destino: String?) -> String {
        destino.map { "Enviado pra \($0)" } ?? "Enviado"
    }
    static let acoesRecebido = ["Abrir", "Mostrar no Finder", "Prateleira"]
    static let acoesEnviado = ["Mostrar no Finder"]
}
