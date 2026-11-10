import Foundation

// Decisões puras do visualizador de foto e vídeo dentro do notch (mockup
// aprovado em docs/vesta/mockups/2026-11-10-whatsapp-visualizador): o estado a
// partir do que o cache respondeu, os avisos, quem mandou, a legenda e o
// subtítulo do topo. Só Foundation: nada aqui toca rede, arquivo ou tela.

/// O que o visualizador mostra na área da mídia.
enum WAEstadoDoVisualizador: Equatable {
    /// O arquivo ainda vem do celular: miniatura desfocada e spinner.
    case carregando
    case foto(URL)
    case video(URL)
    /// O celular já apagou o arquivo.
    case indisponivel
    /// Conta desconectada ou falha: não é "o celular apagou", não pede reenvio.
    case naoDeuParaAbrir
}

/// Ícone de alerta, título e a frase de apoio (que o erro não tem).
struct WAAvisoDoVisualizador: Equatable {
    let titulo: String
    let apoio: String?
}

enum WAVisualizador {
    /// O resultado de `store.midia.arquivo` no estado da tela; o tipo da
    /// mídia decide se o arquivo vira foto ou player.
    static func estado(resultado: WAResultadoMidia, midia: WAMostraMidia) -> WAEstadoDoVisualizador {
        switch resultado {
        case let .arquivo(url): return midia == .video ? .video(url) : .foto(url)
        case .aguardando: return .carregando
        case .indisponivel: return .indisponivel
        case .contaDesconectada, .falhou: return .naoDeuParaAbrir
        }
    }

    /// Indisponível pede reenvio a quem mandou (pelo primeiro nome), menos
    /// quando a mídia é minha; o erro fica só no título.
    static func aviso(_ estado: WAEstadoDoVisualizador, mensagem m: WAMensagem,
                      conversa: WAConversa) -> WAAvisoDoVisualizador? {
        let video = m.tipo == .video
        switch estado {
        case .indisponivel:
            let titulo = video ? "Esse vídeo não está mais disponível" : "Essa foto não está mais disponível"
            var apoio = "O celular já apagou o arquivo."
            if !m.deMim {
                let nome = remetente(mensagem: m, conversa: conversa)
                let primeiro = nome.split(separator: " ").first.map(String.init) ?? nome
                apoio += " Peça para \(primeiro) mandar de novo."
            }
            return WAAvisoDoVisualizador(titulo: titulo, apoio: apoio)
        case .naoDeuParaAbrir:
            return WAAvisoDoVisualizador(
                titulo: video ? "Não deu para abrir o vídeo agora" : "Não deu para abrir a foto agora",
                apoio: nil)
        case .carregando, .foto, .video:
            return nil
        }
    }

    /// Nome no topo: "Você" se é minha; senão o nome de quem mandou, o da
    /// conversa individual ou o número.
    static func remetente(mensagem m: WAMensagem, conversa: WAConversa) -> String {
        if m.deMim { return "Você" }
        if let nome = m.remetenteNome?.trimmingCharacters(in: .whitespaces), !nome.isEmpty { return nome }
        if conversa.tipo != .grupo { return conversa.nome }
        return m.remetente.split(separator: "@", maxSplits: 1).first.map(String.init) ?? m.remetente
    }

    /// O texto da mensagem, só se houver algo além de espaço.
    static func legenda(_ m: WAMensagem) -> String? {
        let t = m.texto.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }

    private static let mesesCurtos = ["jan.", "fev.", "mar.", "abr.", "maio", "jun.", "jul.",
                                      "ago.", "set.", "out.", "nov.", "dez."]

    /// `"Operacional ZOI · hoje, 14:41"`, `"… · ontem, 09:40"`,
    /// `"… · 2 de out., 18:05"`; por dia de calendário, não blocos de 24 h.
    static func subtitulo(conversa: String, ts: Int, agora: Date, calendario: Calendar) -> String {
        let data = Date(timeIntervalSince1970: TimeInterval(ts))
        let dias = calendario.dateComponents([.day], from: calendario.startOfDay(for: data),
                                             to: calendario.startOfDay(for: agora)).day ?? 0
        let c = calendario.dateComponents([.day, .month, .hour, .minute], from: data)
        let hora = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        let dia: String
        switch dias {
        case ...0: dia = "hoje"
        case 1: dia = "ontem"
        default: dia = "\(c.day ?? 0) de \(mesesCurtos[((c.month ?? 1) - 1) % 12])"
        }
        return "\(conversa) · \(dia), \(hora)"
    }
}
