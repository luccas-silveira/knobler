// Gate da etapa 11 do WhatsApp: montagem do card de chegada
// (Knobler/WhatsApp/WhatsAppCartao.swift). Texto, conta, grupo, mídia,
// agrupamento por conversa (WARajada) e idade máxima (a mensagem que chega
// depois de a ponte ficar fora, docs/whatsapp-ponte.md:838-842).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/NotchNotification.swift \
//     Knobler/WhatsApp/WhatsAppCartao.swift tools/whatsappcartaocheck.swift \
//     -o /tmp/whatsappcartaocheck && /tmp/whatsappcartaocheck
//
// Tudo em memória: nenhuma rede, nenhum arquivo, nenhum UserDefaults.

import AppKit

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappcartaocheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - fábricas

private let N4143 = "554791744143"
private let N8292 = "554792508292"
private let PEDRO = "554799990001@s.whatsapp.net"
private let GRUPO = "120363000000000001@g.us"
private let DIEGO = "5547999990000@s.whatsapp.net"
private let AGORA = Date(timeIntervalSince1970: 1_762_270_500)
private let T = 1_762_270_500

private func mensagem(id: String = "3EB0A1B2", conversa: String = PEDRO,
                      remetente: String? = nil, remetenteNome: String? = nil,
                      deMim: Bool = false, ts: Int = T - 5,
                      tipo: WATipoMensagem = .texto, texto: String = "Bora pedalar sábado cedo?",
                      midia: WAMidia? = nil, apagada: Int? = nil) -> WAMensagem {
    WAMensagem(id: id, conversa: conversa, remetente: remetente ?? conversa,
               remetenteNome: remetenteNome, deMim: deMim, ts: ts, tipo: tipo,
               texto: texto, midia: midia, citacao: nil, reacoes: [],
               editada: nil, apagada: apagada, status: deMim ? .enviada : nil)
}

private func individual(_ jid: String = PEDRO, nome: String = "Pedro Alves") -> WAConversa {
    WAConversa(jid: jid, jids: [jid], tipo: .individual, nome: nome,
               naoLidas: 1, marcadaNaoLida: false, ts: T - 5, ultima: nil)
}

private func grupo(nome: String = "Operacional ZOI") -> WAConversa {
    WAConversa(jid: GRUPO, jids: [GRUPO], tipo: .grupo, nome: nome,
               naoLidas: 1, marcadaNaoLida: false, ts: T - 5, ultima: nil)
}

private func conta(_ numero: String, nome: String?) -> WAConta {
    WAConta(conta: numero, jid: "\(numero)@s.whatsapp.net", nome: nome, padrao: false,
            estado: .conectada, motivo: nil, desde: 1_762_000_000,
            naoLidas: 0, conversasNaoLidas: 0)
}

private func midia(_ nome: String, miniatura: Bool = true, mime: String = "image/jpeg") -> WAMidia {
    WAMidia(mimetype: mime, nome: nome, tamanho: 1234, segundos: nil,
            miniatura: miniatura, baixada: false)
}

private let LUCCAS = conta(N4143, nome: "Luccas Silveira")

private func montar(_ m: WAMensagem, _ c: WAConversa, conta: WAConta? = LUCCAS,
                    numero: String = N4143, contagem: Int = 1,
                    agora: Date = AGORA) -> NotchNotification {
    WACartao.montar(mensagem: m, conversa: c, conta: conta, numero: numero,
                    contagem: contagem, agora: agora)
}

private func temEmoji(_ s: String) -> Bool {
    s.unicodeScalars.contains { $0.properties.isEmojiPresentation }
}

// MARK: - casos

/// A que chega 2 min depois (ponte que voltou) não vira card; a minha e a
/// apagada também não.
private func idadeMaxima() {
    exigir(WACartao.idadeMaxima == 120, "idade máxima é 120 s, veio \(WACartao.idadeMaxima)")
    exigir(WACartao.vale(mensagem: mensagem(ts: T - 30), agora: AGORA),
           "recebida com 30 s de idade tem que valer card")
    exigir(WACartao.vale(mensagem: mensagem(ts: T), agora: AGORA),
           "recebida agora tem que valer card")
    exigir(!WACartao.vale(mensagem: mensagem(ts: T - 121), agora: AGORA),
           "recebida com 121 s de idade (ponte voltando) não vale card")
    exigir(!WACartao.vale(mensagem: mensagem(ts: T - 3600), agora: AGORA),
           "mensagem de 1 h atrás não vale card")
    exigir(!WACartao.vale(mensagem: mensagem(deMim: true, ts: T - 5), agora: AGORA),
           "mensagem minha (de_mim) não vale card")
    exigir(!WACartao.vale(mensagem: mensagem(ts: T - 5, apagada: T - 2), agora: AGORA),
           "mensagem apagada não vale card")
    // o `agora` passado é o relógio: a mesma mensagem vale e deixa de valer
    let m = mensagem(ts: T - 30)
    exigir(!WACartao.vale(mensagem: m, agora: AGORA.addingTimeInterval(200)),
           "vale tem que medir a idade pelo agora passado, não pelo relógio do sistema")
}

private func individualTexto() {
    let n = montar(mensagem(texto: "Bora pedalar sábado cedo?"), individual())
    exigir(n.appName == "WhatsApp", "appName é \"WhatsApp\", veio \(String(describing: n.appName))")
    exigir(n.title == "Pedro Alves", "title é o nome da conversa, veio \(n.title)")
    exigir(n.body == "Bora pedalar sábado cedo?", "body é o texto, veio \(n.body)")
    exigir(n.subtitle == "Luccas Silveira · 4143",
           "subtitle é o rótulo da conta, veio \(String(describing: n.subtitle))")
    exigir(n.webhookID == nil, "webhookID nil: com ele o histórico apagaria as linhas anteriores")
    exigir(n.doBanner == false, "card do WhatsApp não é banner do sistema")
    exigir(n.date == AGORA, "date é o agora passado, veio \(n.date)")
    guard let w = n.whatsapp else { exigir(false, "card sem campo whatsapp"); return }
    exigir(w.chave == "554791744143|554799990001@s.whatsapp.net", "chave conta|jid, veio \(w.chave)")
    exigir(w.chave == WAChave(conta: N4143, jid: PEDRO).texto, "chave no formato do WAChave.texto")
    exigir(w.conta == N4143, "whatsapp.conta é o número da conta, veio \(w.conta)")
    exigir(w.jid == PEDRO, "whatsapp.jid é o jid da conversa, veio \(w.jid)")
    exigir(w.rotuloDaConta == "Luccas Silveira · 4143", "rotuloDaConta, veio \(w.rotuloDaConta)")
    exigir(w.grupo == nil, "individual não tem grupo, veio \(String(describing: w.grupo))")
    exigir(w.contagem == 1, "contagem 1, veio \(w.contagem)")
    exigir(w.temMiniatura == false, "texto não tem miniatura")
    exigir(w.mensagemID == "3EB0A1B2", "mensagemID é o id da mensagem, veio \(w.mensagemID)")

    // outra conta: chave e rótulo seguem o número passado
    let o = montar(mensagem(), individual(), conta: conta(N8292, nome: nil), numero: N8292)
    exigir(o.whatsapp?.chave == "554792508292|554799990001@s.whatsapp.net",
           "chave da outra conta, veio \(String(describing: o.whatsapp?.chave))")
    exigir(o.subtitle == "WhatsApp · 8292", "conta sem nome: subtitle \"WhatsApp · 8292\", veio \(String(describing: o.subtitle))")
}

private func grupoComRemetente() {
    let m = mensagem(id: "G1", conversa: GRUPO, remetente: DIEGO, remetenteNome: "Diego Martins",
                     texto: "Subi o corte de 15 s no drive.")
    let n = montar(m, grupo())
    exigir(n.title == "Operacional ZOI", "title de grupo é o nome do grupo, veio \(n.title)")
    exigir(n.body == "Diego Martins: Subi o corte de 15 s no drive.",
           "body de grupo prefixa o remetente, veio \(n.body)")
    exigir(n.whatsapp?.grupo == "Operacional ZOI",
           "whatsapp.grupo é o nome do grupo, veio \(String(describing: n.whatsapp?.grupo))")
    exigir(n.whatsapp?.chave == "554791744143|\(GRUPO)", "chave do grupo é conta|jid do grupo")
    exigir(n.whatsapp?.jid == GRUPO, "whatsapp.jid do grupo é o jid do grupo, não o do remetente")
    exigir(n.webhookID == nil, "grupo também sem webhookID")

    // sem remetenteNome: o número do remetente, sem o sufixo do jid
    let s = montar(mensagem(conversa: GRUPO, remetente: DIEGO, remetenteNome: nil,
                            texto: "Subi o corte de 15 s no drive."), grupo())
    let sufixo = ": Subi o corte de 15 s no drive."
    exigir(s.body.hasSuffix(sufixo), "grupo sem nome do remetente ainda prefixa algo, veio \(s.body)")
    let prefixo = String(s.body.dropLast(sufixo.count))
    exigir(!prefixo.contains("@"), "prefixo não mostra o jid cru, veio \(prefixo)")
    exigir(!prefixo.contains("null") && !prefixo.contains("nil") && !prefixo.isEmpty,
           "prefixo não pode ser vazio nem nil, veio \(prefixo)")
    exigir(prefixo.filter(\.isNumber) == "5547999990000",
           "prefixo é o número do remetente, veio \(prefixo)")
}

private func midiaSemLegenda() {
    let casos: [(WATipoMensagem, WAMidia, String)] = [
        (.imagem, midia("IMG-001.jpg"), "Foto"),
        (.video, midia("VID-001.mp4", mime: "video/mp4"), "Vídeo"),
        (.audio, midia("musica.mp3", miniatura: false, mime: "audio/mpeg"), "Áudio"),
        (.voz, midia("ptt.ogg", miniatura: false, mime: "audio/ogg"), "Mensagem de voz"),
        (.documento, midia("proposta.pdf", miniatura: false, mime: "application/pdf"),
         "Documento: proposta.pdf"),
        (.figurinha, midia("sticker.webp", miniatura: false, mime: "image/webp"), "Figurinha"),
    ]
    for (tipo, md, esperado) in casos {
        let m = mensagem(tipo: tipo, texto: "", midia: md)
        exigir(WACartao.corpo(m) == esperado, "corpo de \(tipo) sem legenda é \"\(esperado)\", veio \"\(WACartao.corpo(m))\"")
        let n = montar(m, individual())
        exigir(n.body == esperado, "body do card de \(tipo) sem legenda é \"\(esperado)\", veio \"\(n.body)\"")
        exigir(!temEmoji(n.body), "body de \(tipo) sem emoji, veio \"\(n.body)\"")
    }

    // com legenda, a legenda
    let legendada = mensagem(tipo: .imagem, texto: "Olha o pôr do sol", midia: midia("IMG-002.jpg"))
    exigir(WACartao.corpo(legendada) == "Olha o pôr do sol", "imagem com legenda mostra a legenda, veio \"\(WACartao.corpo(legendada))\"")
    let doc = mensagem(tipo: .documento, texto: "Segue a proposta",
                       midia: midia("proposta.pdf", miniatura: false, mime: "application/pdf"))
    exigir(WACartao.corpo(doc) == "Segue a proposta", "documento com legenda mostra a legenda, veio \"\(WACartao.corpo(doc))\"")
    exigir(WACartao.corpo(mensagem(texto: "oi")) == "oi", "texto puro: corpo é o texto")

    // grupo com mídia: o rótulo entra depois do remetente
    let g = montar(mensagem(conversa: GRUPO, remetente: DIEGO, remetenteNome: "Diego Martins",
                            tipo: .voz, texto: "", midia: midia("ptt.ogg", miniatura: false)), grupo())
    exigir(g.body == "Diego Martins: Mensagem de voz", "voz em grupo, veio \(g.body)")

    // miniatura: só imagem/vídeo com midia.miniatura == true
    func mini(_ tipo: WATipoMensagem, _ md: WAMidia?) -> Bool {
        montar(mensagem(tipo: tipo, texto: "", midia: md), individual()).whatsapp?.temMiniatura ?? false
    }
    exigir(mini(.imagem, midia("a.jpg", miniatura: true)), "imagem com miniatura: temMiniatura")
    exigir(mini(.video, midia("a.mp4", miniatura: true, mime: "video/mp4")), "vídeo com miniatura: temMiniatura")
    exigir(!mini(.imagem, midia("a.jpg", miniatura: false)), "imagem sem miniatura: sem temMiniatura")
    exigir(!mini(.video, midia("a.mp4", miniatura: false, mime: "video/mp4")), "vídeo sem miniatura: sem temMiniatura")
    exigir(!mini(.documento, midia("a.pdf", miniatura: true, mime: "application/pdf")),
           "documento com miniatura não desenha miniatura")
    exigir(!mini(.figurinha, midia("a.webp", miniatura: true, mime: "image/webp")),
           "figurinha com miniatura não desenha miniatura")
    exigir(!mini(.imagem, nil), "imagem sem objeto midia: sem temMiniatura")
}

private func rajada() {
    let A = "554791744143|554799990001@s.whatsapp.net"
    let B = "554791744143|554799990002@s.whatsapp.net"
    let t0 = AGORA
    var r = WARajada()
    exigir(r.registrar(chave: A, agora: t0) == 1, "primeira da conversa conta 1")
    exigir(r.registrar(chave: A, agora: t0.addingTimeInterval(30)) == 2, "segunda em 30 s conta 2")
    // janela entre mensagens, não desde a primeira: 50 s depois da anterior,
    // 80 s depois da primeira
    exigir(r.registrar(chave: A, agora: t0.addingTimeInterval(80)) == 3,
           "terceira com 50 s de intervalo conta 3 (janela é entre mensagens)")
    exigir(r.registrar(chave: A, agora: t0.addingTimeInterval(80 + 61)) == 1,
           "depois de 61 s de silêncio volta a 1")
    exigir(r.registrar(chave: A, agora: t0.addingTimeInterval(80 + 61 + 59)) == 2,
           "59 s depois ainda junta")

    // conversas separadas não se misturam
    var s = WARajada()
    exigir(s.registrar(chave: A, agora: t0) == 1, "A conta 1")
    exigir(s.registrar(chave: B, agora: t0.addingTimeInterval(5)) == 1, "B não herda a contagem de A")
    exigir(s.registrar(chave: A, agora: t0.addingTimeInterval(10)) == 2, "A segue em 2 com B no meio")
    exigir(s.registrar(chave: B, agora: t0.addingTimeInterval(15)) == 2, "B segue em 2")
    exigir(s.registrar(chave: A, agora: t0.addingTimeInterval(20)) == 3, "A em 3")

    // zerar uma conversa não mexe na outra
    s.zerar(chave: A)
    exigir(s.registrar(chave: A, agora: t0.addingTimeInterval(25)) == 1, "zerar(A) recomeça A em 1")
    exigir(s.registrar(chave: B, agora: t0.addingTimeInterval(30)) == 3, "zerar(A) não zera B")

    // corpo agrupado
    let n = montar(mensagem(texto: "Bora pedalar sábado cedo?"), individual(), contagem: 3)
    exigir(n.body == "3 mensagens novas · Bora pedalar sábado cedo?",
           "body com contagem 3, veio \(n.body)")
    exigir(n.whatsapp?.contagem == 3, "whatsapp.contagem 3, veio \(String(describing: n.whatsapp?.contagem))")
    exigir(n.title == "Pedro Alves", "agrupado mantém o title da conversa")
    let dois = montar(mensagem(texto: "Bora pedalar sábado cedo?"), individual(), contagem: 2)
    exigir(dois.body == "2 mensagens novas · Bora pedalar sábado cedo?", "contagem 2, veio \(dois.body)")
    let um = montar(mensagem(texto: "Bora pedalar sábado cedo?"), individual(), contagem: 1)
    exigir(um.body == "Bora pedalar sábado cedo?", "contagem 1 não prefixa contagem, veio \(um.body)")
}

private func rotulo() {
    exigir(WACartao.rotuloDaConta(conta: conta(N8292, nome: nil), numero: N8292) == "WhatsApp · 8292",
           "conta sem nome: \"WhatsApp · 8292\", veio \(WACartao.rotuloDaConta(conta: conta(N8292, nome: nil), numero: N8292))")
    exigir(WACartao.rotuloDaConta(conta: nil, numero: N8292) == "WhatsApp · 8292",
           "conta desconhecida: \"WhatsApp · 8292\", veio \(WACartao.rotuloDaConta(conta: nil, numero: N8292))")
    exigir(WACartao.rotuloDaConta(conta: LUCCAS, numero: N4143) == "Luccas Silveira · 4143",
           "com nome: \"Luccas Silveira · 4143\", veio \(WACartao.rotuloDaConta(conta: LUCCAS, numero: N4143))")
    exigir(WACartao.rotuloDaConta(conta: conta(N8292, nome: "ZOI Suporte"), numero: N8292) == "ZOI Suporte · 8292",
           "com nome da outra conta, veio \(WACartao.rotuloDaConta(conta: conta(N8292, nome: "ZOI Suporte"), numero: N8292))")
}

private func identidade() {
    let m = mensagem()
    let a = montar(m, individual())
    let b = montar(m, individual())
    exigir(a.id != b.id, "cada montagem gera um id novo (cada mensagem é uma linha do histórico)")
    exigir(a.webhookID == nil && b.webhookID == nil, "webhookID sempre nil")
    let depois = AGORA.addingTimeInterval(42)
    let c = montar(m, individual(), contagem: 2, agora: depois)
    exigir(c.date == depois, "date é o agora passado, veio \(c.date)")
    exigir(c.webhookID == nil, "webhookID nil também agrupado")
    exigir(a.whatsapp?.chave == c.whatsapp?.chave, "mesma conversa, mesma chave: é ela que junta na tela")
}

@main
enum Gate {
    static func main() {
        idadeMaxima()
        individualTexto()
        grupoComRemetente()
        midiaSemLegenda()
        rajada()
        rotulo()
        identidade()
        print("whatsappcartaocheck: ok")
    }
}
