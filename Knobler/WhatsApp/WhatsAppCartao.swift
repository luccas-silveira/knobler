import AppKit

// Montagem do card de chegada do WhatsApp: texto, rótulo da conta, grupo,
// contagem de mensagens seguidas da mesma conversa e idade máxima. Nada aqui
// toca rede.
//
// O `webhookID` fica sempre `nil`: `NotificationHistory.record` apaga do
// histórico toda linha com o mesmo `webhookID`, e cada mensagem tem que ficar
// guardada como uma linha. Quem junta o card na tela é a `whatsapp.chave`
// (o `enqueue` do `NotchViewModel` substitui o card com a mesma chave).

/// Contagem de mensagens seguidas por conversa: a janela vale entre uma
/// mensagem e a anterior, não desde a primeira.
struct WARajada {
    private var ultimas: [String: (agora: Date, contagem: Int)] = [:]

    mutating func registrar(chave: String, agora: Date, janela: TimeInterval = 60) -> Int {
        var contagem = 1
        if let anterior = ultimas[chave], agora.timeIntervalSince(anterior.agora) < janela {
            contagem = anterior.contagem + 1
        }
        ultimas[chave] = (agora, contagem)
        return contagem
    }

    mutating func zerar(chave: String) {
        ultimas[chave] = nil
    }
}

enum WACartao {
    /// Mensagem mais velha que isso (a que chega quando a ponte volta depois
    /// de um tempo fora, docs/whatsapp-ponte.md:838-842) não vira card.
    static let idadeMaxima: TimeInterval = 120

    /// Recebida, não apagada e com no máximo `idadeMaxima` de idade.
    static func vale(mensagem: WAMensagem, agora: Date) -> Bool {
        guard !mensagem.deMim, mensagem.apagada == nil else { return false }
        let idade = agora.timeIntervalSince1970 - TimeInterval(mensagem.ts)
        return idade <= idadeMaxima
    }

    /// `"<nome> · <últimos 4 dígitos>"`; sem nome, `"WhatsApp · <4 dígitos>"`.
    static func rotuloDaConta(conta: WAConta?, numero: String) -> String {
        let final = String(numero.suffix(4))
        if let nome = conta?.nome, !nome.isEmpty {
            return "\(nome) · \(final)"
        }
        return "WhatsApp · \(final)"
    }

    /// Texto da mensagem; mídia sem legenda vira um rótulo do tipo.
    static func corpo(_ m: WAMensagem) -> String {
        guard m.texto.isEmpty else { return m.texto }
        switch m.tipo {
        case .imagem: return "Foto"
        case .video: return "Vídeo"
        case .audio: return "Áudio"
        case .voz: return "Mensagem de voz"
        case .figurinha: return "Figurinha"
        case .documento:
            if let nome = m.midia?.nome, !nome.isEmpty { return "Documento: \(nome)" }
            return "Documento"
        case .texto, .outro: return m.texto
        }
    }

    static func montar(mensagem: WAMensagem, conversa: WAConversa, conta: WAConta?,
                       numero: String, contagem: Int, agora: Date) -> NotchNotification {
        let rotulo = rotuloDaConta(conta: conta, numero: numero)
        let ehGrupo = conversa.tipo == .grupo

        var body = corpo(mensagem)
        if ehGrupo {
            body = "\(remetente(mensagem)): \(body)"
        }
        if contagem > 1 {
            body = "\(contagem) mensagens novas · \(body)"
        }

        let temMiniatura: Bool
        switch mensagem.tipo {
        case .imagem, .video: temMiniatura = mensagem.midia?.miniatura == true
        default: temMiniatura = false
        }

        let cartao = CartaoWhatsApp(
            chave: WAChave(conta: numero, jid: conversa.jid).texto,
            conta: numero,
            jid: conversa.jid,
            rotuloDaConta: rotulo,
            grupo: ehGrupo ? conversa.nome : nil,
            contagem: contagem,
            temMiniatura: temMiniatura,
            mensagemID: mensagem.id
        )
        return NotchNotification(
            appName: "WhatsApp",
            title: conversa.nome,
            body: body,
            subtitle: rotulo,
            webhookID: nil,
            date: agora,
            whatsapp: cartao
        )
    }

    /// Nome do remetente; sem nome, o número (o jid sem o sufixo `@…`).
    private static func remetente(_ m: WAMensagem) -> String {
        if let nome = m.remetenteNome, !nome.isEmpty { return nome }
        let numero = m.remetente.split(separator: "@", maxSplits: 1).first.map(String.init) ?? ""
        return numero.isEmpty ? m.remetente : numero
    }
}
