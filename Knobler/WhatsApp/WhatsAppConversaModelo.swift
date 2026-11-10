import Foundation

// Decisões puras da conversa na coluna direita da seção do WhatsApp (mockup,
// variante A): linhas com separador de dia e remetente em grupo, quem aceita
// ação, o cabeçalho, o que a mídia mostra e o que o clique nela faz. Só
// Foundation: nada aqui toca rede, arquivo ou tela.

/// Uma linha da conversa: separador de dia ou bolha.
enum WALinha: Equatable, Identifiable {
    case dia(String)
    case bolha(WABolha, mostraRemetente: Bool, podeAgir: Bool)

    var id: String {
        switch self {
        case let .dia(t): return "dia:\(t)"
        case let .bolha(b, _, _): return b.id
        }
    }
}

/// O que a bolha desenha no lugar da mídia.
enum WAMostraMidia: Equatable {
    case nenhuma, imagem, video, audio, documento, figurinha, indisponivel
}

/// O que o clique na mídia faz.
enum WAAcaoDaBolha: Equatable {
    /// Foto e vídeo abrem no visualizador dentro do notch, por cima da conversa.
    case verNoNotch
    case mostrarNoFinder
    case tocarAudio
    case nenhuma
}

enum WAConversaModelo {
    // MARK: - linhas

    /// Separador antes da primeira bolha e a cada virada de dia. Em grupo, o
    /// nome de quem mandou aparece na primeira recebida de uma sequência: de
    /// novo quando o remetente muda, depois de uma enviada ou de um separador.
    static func linhas(bolhas: [WABolha], grupo: Bool, agora: Date, calendario: Calendar) -> [WALinha] {
        let estado = WAEstado()
        var saida: [WALinha] = []
        var diaAtual: Date?
        var anterior: WAMensagem?
        for b in bolhas {
            let m = b.mensagem
            let dia = calendario.startOfDay(for: Date(timeIntervalSince1970: TimeInterval(m.ts)))
            if dia != diaAtual {
                saida.append(.dia(WAApresentacao.separadorDeDia(ts: m.ts, agora: agora, calendario: calendario)))
                diaAtual = dia
                anterior = nil
            }
            let mostra = grupo && !m.deMim
                && (anterior == nil || anterior!.deMim || anterior!.remetente != m.remetente)
            saida.append(.bolha(b, mostraRemetente: mostra, podeAgir: podeAgir(b, estado: estado)))
            anterior = m
        }
        return saida
    }

    /// Apagada, enviando e falhou não aceitam reagir nem citar.
    private static func podeAgir(_ b: WABolha, estado: WAEstado) -> Bool {
        guard b.mensagem.apagada == nil else { return false }
        switch estado.estadoDaBolha(b) {
        case .enviando, .falhou: return false
        case .enviada, .entregue, .lida, .recebida: return true
        }
    }

    // MARK: - cabeçalho

    /// Individual: só o nome. Grupo: o nome e quem está nele, com "você" no
    /// fim. "Marcar como lida" só quando há o que marcar.
    static func cabecalho(conversa: WAConversa, grupo: WAGrupo?)
        -> (titulo: String, subtitulo: String?, marcarLida: Bool) {
        let marcar = conversa.naoLidas > 0 || conversa.marcadaNaoLida
        return (conversa.nome, grupo.flatMap(participantes), marcar)
    }

    /// `"Ana Ribeiro, Diego Martins, Júlia Souza e você"`; sem nome, o número.
    private static func participantes(_ g: WAGrupo) -> String? {
        var nomes = g.participantes.filter { !$0.eu }.map(nomeDoParticipante)
        if g.participantes.contains(where: \.eu) { nomes.append("você") }
        guard let ultimo = nomes.last else { return nil }
        guard nomes.count > 1 else { return ultimo }
        return nomes.dropLast().joined(separator: ", ") + " e " + ultimo
    }

    private static func nomeDoParticipante(_ p: WAParticipante) -> String {
        if let nome = p.nome?.trimmingCharacters(in: .whitespaces), !nome.isEmpty { return nome }
        if let tel = p.telefone, !tel.isEmpty { return tel }
        return p.jid.split(separator: "@", maxSplits: 1).first.map(String.init) ?? p.jid
    }

    // MARK: - mídia

    static func mostraMidia(bolha b: WABolha) -> WAMostraMidia {
        let m = b.mensagem
        guard m.apagada == nil else { return .nenhuma }
        let tipo: WAMostraMidia
        switch m.tipo {
        case .imagem: tipo = .imagem
        case .video: tipo = .video
        case .audio, .voz: tipo = .audio
        case .documento: tipo = .documento
        case .figurinha: tipo = .figurinha
        case .texto, .outro: return .nenhuma
        }
        return b.midiaIndisponivel ? .indisponivel : tipo
    }

    /// Bolha local (enviando ou que falhou) não tem arquivo na ponte ainda.
    static func acao(bolha b: WABolha) -> WAAcaoDaBolha {
        guard b.envio == nil else { return .nenhuma }
        switch mostraMidia(bolha: b) {
        case .imagem, .video: return .verNoNotch
        case .documento: return .mostrarNoFinder
        case .audio: return .tocarAudio
        case .figurinha, .indisponivel, .nenhuma: return .nenhuma
        }
    }

    // MARK: - textos da bolha

    /// `"14:32"`: a hora da bolha, sempre em horas (o dia está no separador).
    static func hora(ts: Int, calendario: Calendar) -> String {
        let c = calendario.dateComponents([.hour, .minute], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    /// Quem escreveu a mensagem citada: "Você" se é minha; senão o nome da
    /// bolha citada, o da conversa individual ou o número.
    static func nomeDaCitacao(_ c: WACitacao, conta: String, bolhas: [WABolha], conversa: WAConversa?) -> String {
        let numero = c.remetente.split(separator: "@", maxSplits: 1).first
            .map { String($0.split(separator: ":", maxSplits: 1).first ?? $0) } ?? c.remetente
        if numero == conta { return "Você" }
        if let citada = bolhas.first(where: { $0.id == c.id })?.mensagem {
            if citada.deMim { return "Você" }
            if let nome = citada.remetenteNome, !nome.isEmpty { return nome }
        }
        if let conversa, conversa.tipo != .grupo { return conversa.nome }
        return numero
    }
}
