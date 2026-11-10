import Foundation

// Textos e decisões puras de apresentação da seção do WhatsApp: prévia da
// linha da lista, hora, separador de dia, duração, tamanho de arquivo, tique
// do status e estado da conta. Só Foundation: nada aqui toca rede, arquivo ou
// UserDefaults. Textos tirados do mockup
// (docs/vesta/mockups/2026-11-04-whatsapp/index.html).

/// O que a linha da lista mostra abaixo do nome da conversa.
struct WAPrevia: Equatable {
    /// Nome de SF Symbol, ou `nil` para texto puro.
    let icone: String?
    /// `"Rascunho:"` ou `"Diego:"` (grupo); `nil` sem prefixo.
    let prefixo: String?
    let texto: String
    let rascunho: Bool
    let apagada: Bool
}

/// Forma do tique de status: cada estado tem um desenho próprio, não só uma
/// cor (DESIGN.md §2).
enum WATique: Equatable {
    case relogio, um, dois, doisLida, nenhum
}

/// O que o seletor de contas mostra para o estado de uma conta.
struct WAEstadoDaContaNaTela: Equatable {
    /// `nil` quando a conta está conectada (nada a dizer).
    let rotulo: String?
    let precisaQR: Bool
}

enum WAApresentacao {
    // MARK: - prévia

    static func previa(ultima: WAUltima?, grupo: Bool, rascunho: String?) -> WAPrevia {
        if let rascunho, !rascunho.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return WAPrevia(icone: nil, prefixo: "Rascunho:", texto: rascunho, rascunho: true, apagada: false)
        }
        guard let u = ultima else {
            return WAPrevia(icone: nil, prefixo: nil, texto: "", rascunho: false, apagada: false)
        }
        if u.apagada != nil {
            return WAPrevia(icone: "nosign", prefixo: nil, texto: WATextos.apagada, rascunho: false, apagada: true)
        }
        let prefixo = grupo ? prefixoDoGrupo(u) : nil
        let (icone, texto) = corpo(u)
        return WAPrevia(icone: icone, prefixo: prefixo, texto: texto, rascunho: false, apagada: false)
    }

    /// Ícone e texto da última mensagem pelo tipo; mídia sem legenda vira o
    /// rótulo do tipo.
    private static func corpo(_ u: WAUltima) -> (String?, String) {
        switch u.tipo {
        case .texto, .outro:
            return (nil, u.previa)
        case .imagem:
            return ("camera", u.previa.isEmpty ? "Foto" : u.previa)
        case .video:
            return ("video", u.previa.isEmpty ? comDuracao("Vídeo", u.segundos) : u.previa)
        case .audio, .voz:
            return ("mic", comDuracao("Áudio", u.segundos))
        case .documento:
            return ("doc.text", u.previa.isEmpty ? "Documento" : u.previa)
        case .figurinha:
            return ("face.smiling", "Figurinha")
        }
    }

    private static func comDuracao(_ rotulo: String, _ segundos: Int?) -> String {
        guard let segundos else { return rotulo }
        return "\(rotulo) · \(duracao(segundos))"
    }

    /// Primeiro nome de quem mandou, com dois-pontos; sem nome, o número.
    private static func prefixoDoGrupo(_ u: WAUltima) -> String {
        if u.deMim { return "Você:" }
        if let nome = u.remetenteNome?.trimmingCharacters(in: .whitespaces), !nome.isEmpty {
            let primeiro = nome.split(separator: " ", maxSplits: 1).first.map(String.init) ?? nome
            return "\(primeiro):"
        }
        let numero = u.remetente.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        return "\(numero.isEmpty ? u.remetente : numero):"
    }

    // MARK: - hora e dia

    private static let diasDaSemana = ["dom", "seg", "ter", "qua", "qui", "sex", "sáb"]
    private static let meses = ["janeiro", "fevereiro", "março", "abril", "maio", "junho", "julho",
                                "agosto", "setembro", "outubro", "novembro", "dezembro"]

    /// Dias de calendário entre a data de `ts` e a de `agora`, no fuso do
    /// calendário (não blocos de 24 h).
    private static func diasAtras(_ data: Date, agora: Date, calendario: Calendar) -> Int {
        let de = calendario.startOfDay(for: data)
        let ate = calendario.startOfDay(for: agora)
        return calendario.dateComponents([.day], from: de, to: ate).day ?? 0
    }

    /// Hora da linha da lista: `"14:32"` hoje, `"Ontem"`, dia da semana
    /// abreviado até 6 dias, `"03/11/26"` antes disso.
    static func hora(ts: Int, agora: Date, calendario: Calendar) -> String {
        let data = Date(timeIntervalSince1970: TimeInterval(ts))
        let dias = diasAtras(data, agora: agora, calendario: calendario)
        let c = calendario.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: data)
        switch dias {
        case ...0:
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        case 1:
            return "Ontem"
        case 2...6:
            return diasDaSemana[((c.weekday ?? 1) - 1) % 7]
        default:
            return String(format: "%02d/%02d/%02d", c.day ?? 0, c.month ?? 0, (c.year ?? 0) % 100)
        }
    }

    /// Separador entre dias na conversa: `"Hoje"`, `"Ontem"`, `"3 de novembro"`.
    static func separadorDeDia(ts: Int, agora: Date, calendario: Calendar) -> String {
        let data = Date(timeIntervalSince1970: TimeInterval(ts))
        switch diasAtras(data, agora: agora, calendario: calendario) {
        case ...0: return "Hoje"
        case 1: return "Ontem"
        default:
            let c = calendario.dateComponents([.day, .month], from: data)
            return "\(c.day ?? 0) de \(meses[((c.month ?? 1) - 1) % 12])"
        }
    }

    // MARK: - duração e tamanho

    /// `"0:37"`, `"1:05"`, `"1:02:03"`.
    static func duracao(_ segundos: Int) -> String {
        let s = max(0, segundos)
        let h = s / 3600, m = (s % 3600) / 60, seg = s % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, seg) }
        return String(format: "%d:%02d", m, seg)
    }

    private static let tiposConhecidos: [String: String] = [
        "application/pdf": "PDF",
        "application/zip": "ZIP",
        "text/plain": "TXT",
        "text/csv": "CSV",
    ]

    /// `"PDF · 820 KB"`; tipo sem nome conhecido mostra só o tamanho.
    static func tamanho(mimetype: String, bytes: Int) -> String {
        let medida = tamanhoEmTexto(bytes)
        let tipo = mimetype.split(separator: ";", maxSplits: 1).first
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
        guard let nome = tiposConhecidos[tipo] else { return medida }
        return "\(nome) · \(medida)"
    }

    private static func tamanhoEmTexto(_ bytes: Int) -> String {
        let b = Double(max(0, bytes))
        if b < 1024 { return "\(Int(b)) B" }
        if b < 1024 * 1024 { return "\(numero(b / 1024, casas: 0)) KB" }
        if b < 1024 * 1024 * 1024 { return "\(numero(b / (1024 * 1024), casas: 1)) MB" }
        return "\(numero(b / (1024 * 1024 * 1024), casas: 1)) GB"
    }

    private static func numero(_ valor: Double, casas: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "pt_BR")
        f.numberStyle = .decimal
        f.minimumFractionDigits = casas
        f.maximumFractionDigits = casas
        return f.string(from: NSNumber(value: valor)) ?? String(valor)
    }

    // MARK: - status e conta

    static func tique(_ estado: WAEstadoDaBolha) -> WATique {
        switch estado {
        case .enviando: return .relogio
        case .enviada: return .um
        case .entregue: return .dois
        case .lida: return .doisLida
        case .falhou, .recebida: return .nenhum
        }
    }

    static func estadoDaConta(_ estado: WAEstadoConta) -> WAEstadoDaContaNaTela {
        switch estado {
        case .conectada: return WAEstadoDaContaNaTela(rotulo: nil, precisaQR: false)
        case .deslogada: return WAEstadoDaContaNaTela(rotulo: "desconectada", precisaQR: true)
        case .desconectada, .conectando: return WAEstadoDaContaNaTela(rotulo: "reconectando", precisaQR: false)
        case .substituida: return WAEstadoDaContaNaTela(rotulo: "em uso noutro processo", precisaQR: false)
        case .suspensa: return WAEstadoDaContaNaTela(rotulo: "suspensa", precisaQR: false)
        // ponytail: estado que a ponte inventar depois aparece cru, sem QR.
        case .outro(let bruto): return WAEstadoDaContaNaTela(rotulo: bruto, precisaQR: false)
        }
    }
}

/// Textos fixos dos estados da seção, exatos como no mockup.
enum WATextos {
    // ponte fora
    static let ponteForaTitulo = "A ponte do WhatsApp não está respondendo."
    static let ponteForaApoio = "O Knobler tenta de novo sozinho. Para religar agora, rode no Terminal:"
    static let ponteForaComando = "~/Code/whatsapp-mcp/whatsapp-bridge/servico.sh"
    static let ponteForaRodape = "Enquanto isso, os cards voltam a vir do WhatsApp Desktop."

    // chave recusada ou ausente: mesmo título e botão, apoio diferente
    static let chaveTitulo = "A chave da ponte não confere."
    static let chaveApoio = "A ponte recusou a chave que o Knobler leu. Os dois precisam ler o mesmo arquivo de chave; confira o arquivo e tente de novo."
    static let chaveAusenteApoio = "O Knobler não achou o arquivo de chave da ponte em ~/Library/Application Support/whatsapp-bridge/api-key. A ponte cria esse arquivo quando sobe; confira se ela está rodando e tente de novo."
    static let tentarDeNovo = "Tentar de novo"

    static func apoioDaChave(ausente: Bool) -> String {
        ausente ? chaveAusenteApoio : chaveApoio
    }

    // versão incompatível
    static let incompativelTitulo = "A ponte do WhatsApp é de outra versão."
    static let incompativelApoio = "Atualize a ponte ou o Knobler para a mesma versão do contrato."

    // QR
    static func qrTitulo(rotulo: String) -> String {
        "\(rotulo) desconectada — escaneie o QR no celular: WhatsApp › Aparelhos conectados › Conectar aparelho"
    }

    static func qrApoio(outra: String) -> String {
        "O código troca sozinho enquanto espera. \(outra) segue funcionando."
    }

    static let qrExpiradoTitulo = "QR expirado"
    static let qrGerarOutro = "Gerar outro"
    static let qrExpiradoApoio = "O código vale por cerca de 160 s. Gere outro e escaneie de novo."

    // lista
    static let carregando = "Carregando conversas…"
    static let vazioTitulo = "Nenhuma conversa ainda"
    static let vazioApoio = "A primeira mensagem que chegar nesta conta aparece aqui."
    static let semPareamento = "As conversas desta conta voltam depois de parear."

    // bolha
    static let falhaTitulo = "não enviada"
    static let falhaAcao = "tentar de novo"
    static let midiaIndisponivel = "mídia indisponível"
    static let apagada = "Mensagem apagada"

    // compositor
    static let placeholderConversa = "Mensagem"
    static let placeholderResposta = "Responder…"
    static let gravando = "Gravando"
    static let ouvindo = "Ouvindo"
    static let marcarComoLida = "Marcar como lida"

    // visualizador de foto e vídeo
    static let abrirNoPreVisualizacao = "Abrir no Pré-Visualização"
    static let mostrarNoFinder = "Mostrar no Finder"
    static let fechar = "Fechar"

    static func buscandoNoCelular(video: Bool) -> String {
        video ? "Buscando o vídeo no celular…" : "Buscando a foto no celular…"
    }

    /// Faixa da citação; `nil` é mensagem minha.
    static func citacao(nome: String?) -> String {
        "Respondendo a \(nome ?? "você")"
    }
}
