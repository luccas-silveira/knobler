import Foundation

// Decisões puras do compositor da conversa (mockup, variante A: `.cmp`, `.qs`,
// `.recbox`) e das ações da bolha: o desenho do compositor, a faixa
// "Respondendo a …", as 6 reações e o tempo da gravação. Só Foundation.

/// O que o compositor desenha.
enum WAModoDoCompositor: Equatable {
    /// Campo, clipe e um botão à direita: avião com texto ou anexo, microfone sem.
    case normal(mostraEnviar: Bool, mostraMicrofone: Bool)
    /// Lixeira, caixa "Gravando" com tempo e nível, avião.
    case gravando
    /// Campo com "Ouvindo" à direita: o ditado escreve nele.
    case ditando
}

enum WACompositor {
    /// A barra de reações, nesta ordem.
    static let reacoes = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    /// Gravando vence o ditado; texto só com espaços conta como vazio.
    static func modo(gravando: Bool, ditando: Bool, texto: String, temAnexo: Bool) -> WAModoDoCompositor {
        if gravando { return .gravando }
        if ditando { return .ditando }
        let cheio = temAnexo || !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return .normal(mostraEnviar: cheio, mostraMicrofone: !cheio)
    }

    /// A linha de baixo da faixa de citação: o texto, ou o rótulo da mídia.
    static func textoDaCitacao(_ m: WAMensagem) -> String {
        switch m.tipo {
        case .texto: return m.texto
        case .imagem: return "Foto"
        case .video: return "Vídeo"
        case .documento:
            let nome = m.midia?.nome ?? ""
            return nome.isEmpty ? "Documento" : nome
        case .audio, .voz: return "Áudio"
        case .figurinha: return "Figurinha"
        case .outro: return "Mídia"
        }
    }

    /// "Respondendo a você" (minha), "a <remetente>" (de outro no grupo) ou
    /// "a <nome da conversa>" (individual).
    static func rotuloDaCitacao(m: WAMensagem, conversa: WAConversa) -> String {
        if m.deMim { return WATextos.citacao(nome: nil) }
        guard conversa.tipo == .grupo else { return WATextos.citacao(nome: conversa.nome) }
        if let nome = m.remetenteNome?.trimmingCharacters(in: .whitespaces), !nome.isEmpty {
            return WATextos.citacao(nome: nome)
        }
        let numero = m.remetente.split(separator: "@", maxSplits: 1).first.map(String.init) ?? m.remetente
        return WATextos.citacao(nome: numero)
    }

    /// Tocar na reação que já é minha a remove: vai emoji vazio à ponte.
    static func emojiParaEnviar(escolhido: String, atual: String?) -> String {
        escolhido == atual ? "" : escolhido
    }

    /// `"0:12"`, `"1:05"`: minutos e segundos inteiros desde o início.
    static func tempoDeGravacao(inicio: Date, agora: Date) -> String {
        let s = max(0, Int(agora.timeIntervalSince(inicio)))
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
