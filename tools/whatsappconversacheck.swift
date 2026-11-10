// Gate da etapa 24 do WhatsApp: a conversa na coluna direita da seção.
// Modelo puro em Knobler/WhatsApp/WhatsAppConversaModelo.swift (linhas com
// separador de dia, remetente em grupo, quem aceita ação, cabeçalho, o que a
// mídia mostra e o que o clique nela faz) e, no WhatsAppStore, o "Marcar como
// lida" e o grupo guardado por 10 min (docs/whatsapp-ponte.md:536-561).
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift Knobler/WhatsApp/WhatsAppChave.swift \
//     Knobler/WhatsApp/WhatsAppCliente.swift Knobler/WhatsApp/WhatsAppCanal.swift \
//     Knobler/WhatsApp/WhatsAppEstado.swift Knobler/WhatsApp/WhatsAppStore.swift \
//     Knobler/WhatsApp/WhatsAppGravacao.swift Knobler/WhatsApp/CodificadorOpus.swift \
//     Knobler/WhatsApp/OggOpus.swift Knobler/WhatsApp/WhatsAppMidia.swift \
//     Knobler/NotchNotification.swift Knobler/WhatsApp/WhatsAppCartao.swift \
//     Knobler/WhatsApp/WhatsAppApresentacao.swift Knobler/WhatsApp/WhatsAppConversaModelo.swift \
//     tools/whatsappconversacheck.swift \
//     -o /tmp/whatsappconversacheck && /tmp/whatsappconversacheck
//
// Roda da raiz do repo (o check.sh faz `cd` para lá): a última parte lê as
// views e o harness de snapshot, que o check.sh não compila.
//
// Nada sai pela rede: o cliente fala com um transporte falso que responde por
// caminho e grava cada pedido; o canal é um falso. A chave mora numa pasta de
// NSTemporaryDirectory(); a chave de verdade da ponte nunca é lida.

import Foundation

private func exigir(_ cond: Bool, _ msg: String, linha: UInt = #line) {
    if !cond {
        print("FALHOU: \(msg) (tools/whatsappconversacheck.swift:\(linha))")
        exit(1)
    }
}

// MARK: - números e relógio do teste

private let A = "554791744143"                      // conta
private let EU = A + "@s.whatsapp.net"
private let X = "554799990001@s.whatsapp.net"       // conversa individual (Marina)
private let G = "120363000000000001@g.us"           // grupo
private let ANA = "554799000001@s.whatsapp.net"
private let DIEGO = "554799000002@s.whatsapp.net"
private let JULIA = "554799000003@s.whatsapp.net"

private let kX = WAChave(conta: A, jid: X)
private let kG = WAChave(conta: A, jid: G)

private let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
    return c
}()

private func data(dia: Int, hora: Int, minuto: Int = 0) -> Date {
    cal.date(from: DateComponents(year: 2026, month: 11, day: dia, hour: hora, minute: minuto))!
}

private func ts(dia: Int, hora: Int, minuto: Int = 0) -> Int {
    Int(data(dia: dia, hora: hora, minuto: minuto).timeIntervalSince1970)
}

/// "Agora" do modelo: 4 de novembro, 15:00 em São Paulo.
private let agora = data(dia: 4, hora: 15)

// MARK: - fixtures

private func midia(_ mimetype: String, nome: String = "", segundos: Int? = nil) -> WAMidia {
    WAMidia(mimetype: mimetype, nome: nome, tamanho: 840_000, segundos: segundos, miniatura: true, baixada: true)
}

private func msg(_ id: String, de remetente: String, nome: String? = nil, ts: Int,
                 tipo: WATipoMensagem = .texto, texto: String = "", midia m: WAMidia? = nil,
                 apagada: Int? = nil, status: WAStatus? = nil, conversa: String = X) -> WAMensagem {
    let deMim = remetente == EU
    return WAMensagem(id: id, conversa: conversa, remetente: remetente, remetenteNome: nome,
                      deMim: deMim, ts: ts, tipo: tipo, texto: texto, midia: m, citacao: nil,
                      reacoes: [], editada: nil, apagada: apagada,
                      status: status ?? (deMim ? .entregue : nil))
}

private func bolha(_ m: WAMensagem, envio: WAEnvio? = nil, indisponivel: Bool = false) -> WABolha {
    var b = WABolha(mensagem: m)
    b.envio = envio
    b.midiaIndisponivel = indisponivel
    return b
}

private func conversa(_ jid: String, nome: String, tipo: WATipoConversa,
                      naoLidas: Int = 0, marcada: Bool = false) -> WAConversa {
    WAConversa(jid: jid, jids: [jid], tipo: tipo, nome: nome, naoLidas: naoLidas,
               marcadaNaoLida: marcada, ts: ts(dia: 4, hora: 14), ultima: nil)
}

private func participante(_ jid: String, nome: String?, eu: Bool = false) -> WAParticipante {
    WAParticipante(jid: jid, telefone: nil, lid: nil, nome: nome, admin: false, superadmin: false, eu: eu)
}

private func grupo(_ ps: [WAParticipante]) -> WAGrupo {
    WAGrupo(jid: G, nome: "Projeto Aurora", descricao: "", criado: 1_575_256_960, dono: nil,
            soAdminsEnviam: false, participantes: ps)
}

/// Linhas de bolha achatadas: id, mostraRemetente, podeAgir.
private func bolhas(_ ls: [WALinha]) -> [(String, Bool, Bool)] {
    ls.compactMap { l in
        if case let .bolha(b, mostraRemetente: r, podeAgir: p) = l { return (b.id, r, p) }
        return nil
    }
}

/// `dia:Hoje`, `m1 rem=false agir=true`: legível na falha.
private func resumo(_ ls: [WALinha]) -> [String] {
    ls.map { l in
        switch l {
        case let .dia(t): return "dia:\(t)"
        case let .bolha(b, mostraRemetente: r, podeAgir: p): return "\(b.id) rem=\(r) agir=\(p)"
        }
    }
}

private func dias(_ ls: [WALinha]) -> [String] {
    ls.compactMap { l in
        if case let .dia(t) = l { return t }
        return nil
    }
}

// MARK: - linhas

/// Individual em dois dias: separador antes da primeira, outro na virada, e
/// remetente nunca aparece (nem depois de uma enviada).
private func linhasIndividual() {
    let b1 = bolha(msg("m1", de: X, ts: ts(dia: 3, hora: 10), texto: "Bom dia! Viu o orçamento?"))
    let b2 = bolha(msg("m2", de: X, ts: ts(dia: 4, hora: 9), texto: "Mandei a foto da sala"))
    let b3 = bolha(msg("m3", de: EU, ts: ts(dia: 4, hora: 9, minuto: 5), texto: "Vi sim", status: .lida))
    let b4 = bolha(msg("m4", de: X, ts: ts(dia: 4, hora: 9, minuto: 10), texto: "Perfeito"))

    let ls = WAConversaModelo.linhas(bolhas: [b1, b2, b3, b4], grupo: false, agora: agora, calendario: cal)
    let esperado: [WALinha] = [
        .dia("Ontem"),
        .bolha(b1, mostraRemetente: false, podeAgir: true),
        .dia("Hoje"),
        .bolha(b2, mostraRemetente: false, podeAgir: true),
        .bolha(b3, mostraRemetente: false, podeAgir: true),
        .bolha(b4, mostraRemetente: false, podeAgir: true),
    ]
    exigir(ls == esperado, "individual em dois dias: esperado \(resumo(esperado)), veio \(resumo(ls))")

    // um dia só: um separador só, e ele vem primeiro
    let hoje = WAConversaModelo.linhas(bolhas: [b2, b3, b4], grupo: false, agora: agora, calendario: cal)
    exigir(hoje.first == .dia("Hoje"), "a primeira linha tem que ser o separador \"Hoje\", veio \(String(describing: hoje.first))")
    exigir(dias(hoje) == ["Hoje"], "um dia só deveria ter um separador, veio \(dias(hoje))")

    exigir(WAConversaModelo.linhas(bolhas: [], grupo: false, agora: agora, calendario: cal).isEmpty,
           "conversa sem bolha não deveria ter linha (nem separador)")
}

/// Grupo: nome na primeira recebida da sequência, quando o remetente muda e
/// quando a recebida vem depois de uma enviada; nunca na enviada.
private func linhasGrupo() {
    let a1 = bolha(msg("g1", de: ANA, nome: "Ana Ribeiro", ts: ts(dia: 4, hora: 10), texto: "Subi o contrato", conversa: G))
    let a2 = bolha(msg("g2", de: ANA, nome: "Ana Ribeiro", ts: ts(dia: 4, hora: 10, minuto: 1), texto: "Revisem até sexta", conversa: G))
    let d1 = bolha(msg("g3", de: DIEGO, nome: "Diego Martins", ts: ts(dia: 4, hora: 10, minuto: 2), texto: "Ok", conversa: G))
    let e1 = bolha(msg("g4", de: EU, ts: ts(dia: 4, hora: 10, minuto: 3), texto: "Combinado", conversa: G))
    let d2 = bolha(msg("g5", de: DIEGO, nome: "Diego Martins", ts: ts(dia: 4, hora: 10, minuto: 4), texto: "Valeu", conversa: G))
    let d3 = bolha(msg("g6", de: DIEGO, nome: "Diego Martins", ts: ts(dia: 4, hora: 10, minuto: 5), texto: "Até", conversa: G))
    let j1 = bolha(msg("g7", de: JULIA, nome: "Júlia Souza", ts: ts(dia: 4, hora: 10, minuto: 6), texto: "Oi", conversa: G))

    let ls = WAConversaModelo.linhas(bolhas: [a1, a2, d1, e1, d2, d3, j1], grupo: true, agora: agora, calendario: cal)
    exigir(ls.first == .dia("Hoje"), "grupo: a primeira linha tem que ser o separador \"Hoje\", veio \(String(describing: ls.first))")
    exigir(dias(ls) == ["Hoje"], "grupo num dia só: um separador só, veio \(dias(ls))")
    let remetente = bolhas(ls).map { "\($0.0)=\($0.1)" }
    let esperado = ["g1=true", "g2=false", "g3=true", "g4=false", "g5=true", "g6=false", "g7=true"]
    exigir(remetente == esperado, "grupo, quem mostra o remetente: esperado \(esperado), veio \(remetente)")

    // as mesmas bolhas numa conversa individual: nenhuma mostra
    let ind = WAConversaModelo.linhas(bolhas: [a1, a2, d1, e1, d2, d3, j1], grupo: false, agora: agora, calendario: cal)
    exigir(bolhas(ind).allSatisfy { !$0.1 }, "conversa individual mostrou remetente: \(bolhas(ind).map { "\($0.0)=\($0.1)" })")
}

/// `podeAgir` é `false` só para apagada, enviando e falhou.
private func podeAgir() {
    let normal = bolha(msg("p1", de: X, ts: ts(dia: 4, hora: 11), texto: "oi"))
    let enviada = bolha(msg("p2", de: EU, ts: ts(dia: 4, hora: 11, minuto: 1), texto: "oi", status: .lida))
    let apagada = bolha(msg("p3", de: X, ts: ts(dia: 4, hora: 11, minuto: 2), apagada: ts(dia: 4, hora: 11, minuto: 3)))
    let apagadaMinha = bolha(msg("p4", de: EU, ts: ts(dia: 4, hora: 11, minuto: 4), apagada: ts(dia: 4, hora: 11, minuto: 5)))
    let enviando = bolha(msg("local-r1", de: EU, ts: ts(dia: 4, hora: 11, minuto: 6), texto: "indo", status: nil),
                         envio: .enviando(ref: "r1"))
    let falhou = bolha(msg("local-r2", de: EU, ts: ts(dia: 4, hora: 11, minuto: 7), texto: "não foi", status: nil),
                       envio: .falhou(ref: "r2"))
    let indisponivel = bolha(msg("p5", de: X, ts: ts(dia: 4, hora: 11, minuto: 8), tipo: .imagem,
                                 midia: midia("image/jpeg")), indisponivel: true)
    let foto = bolha(msg("p6", de: X, ts: ts(dia: 4, hora: 11, minuto: 9), tipo: .imagem, texto: "a sala",
                         midia: midia("image/jpeg")))

    let todas = [normal, enviada, apagada, apagadaMinha, enviando, falhou, indisponivel, foto]
    for grupo in [false, true] {
        let ls = WAConversaModelo.linhas(bolhas: todas, grupo: grupo, agora: agora, calendario: cal)
        let agir = bolhas(ls).map { "\($0.0)=\($0.2)" }
        let esperado = ["p1=true", "p2=true", "p3=false", "p4=false", "local-r1=false", "local-r2=false",
                        "p5=true", "p6=true"]
        exigir(agir == esperado, "podeAgir (grupo: \(grupo)): esperado \(esperado), veio \(agir)")
    }
}

// MARK: - cabeçalho

private func cabecalho() {
    let marina = conversa(X, nome: "Marina Costa", tipo: .individual)
    let c1 = WAConversaModelo.cabecalho(conversa: marina, grupo: nil)
    exigir(c1.titulo == "Marina Costa", "individual: título \"Marina Costa\", veio \"\(c1.titulo)\"")
    exigir(c1.subtitulo == nil, "individual: sem subtítulo, veio \(String(describing: c1.subtitulo))")
    exigir(!c1.marcarLida, "individual lida (0 não lidas, não marcada): sem \"Marcar como lida\"")

    let pendente = conversa(X, nome: "Marina Costa", tipo: .individual, naoLidas: 2)
    let c2 = WAConversaModelo.cabecalho(conversa: pendente, grupo: nil)
    exigir(c2.marcarLida, "2 não lidas: tem que mostrar \"Marcar como lida\"")
    exigir(c2.subtitulo == nil, "individual com não lidas continua sem subtítulo")

    let marcada = conversa(X, nome: "Marina Costa", tipo: .individual, naoLidas: 0, marcada: true)
    exigir(WAConversaModelo.cabecalho(conversa: marcada, grupo: nil).marcarLida,
           "marcada como não lida (0 não lidas): tem que mostrar \"Marcar como lida\"")

    let ana = participante(ANA, nome: "Ana Ribeiro")
    let diego = participante(DIEGO, nome: "Diego Martins")
    let julia = participante(JULIA, nome: "Júlia Souza")
    let esperado = "Ana Ribeiro, Diego Martins, Júlia Souza e você"

    let aurora = conversa(G, nome: "Projeto Aurora", tipo: .grupo)
    // "eu" vem primeiro na lista da ponte e com nome: vira "você", no fim
    let g1 = WAConversaModelo.cabecalho(conversa: aurora,
                                        grupo: grupo([participante(EU, nome: "Luccas Silveira", eu: true), ana, diego, julia]))
    exigir(g1.titulo == "Projeto Aurora", "grupo: título é o nome da conversa, veio \"\(g1.titulo)\"")
    exigir(g1.subtitulo == esperado, "grupo: subtítulo \"\(esperado)\", veio \(String(describing: g1.subtitulo))")
    exigir(!g1.marcarLida, "grupo lido: sem \"Marcar como lida\"")

    // "eu" no meio e sem nome: continua "você", sempre no fim
    let g2 = WAConversaModelo.cabecalho(conversa: aurora,
                                        grupo: grupo([ana, diego, participante(EU, nome: nil, eu: true), julia]))
    exigir(g2.subtitulo == esperado, "grupo com \"eu\" no meio: subtítulo \"\(esperado)\", veio \(String(describing: g2.subtitulo))")

    let auroraPendente = conversa(G, nome: "Projeto Aurora", tipo: .grupo, naoLidas: 3)
    let g3 = WAConversaModelo.cabecalho(conversa: auroraPendente,
                                        grupo: grupo([participante(EU, nome: nil, eu: true), ana, diego, julia]))
    exigir(g3.marcarLida, "grupo com 3 não lidas: tem que mostrar \"Marcar como lida\"")
}

// MARK: - mídia e clique

private func mostraMidia() {
    let t = ts(dia: 4, hora: 12)
    func ver(_ b: WABolha) -> WAMostraMidia { WAConversaModelo.mostraMidia(bolha: b) }

    let foto = msg("x1", de: X, ts: t, tipo: .imagem, texto: "legenda", midia: midia("image/jpeg"))
    let video = msg("x2", de: X, ts: t, tipo: .video, midia: midia("video/mp4", segundos: 14))
    exigir(ver(bolha(foto, indisponivel: true)) == .indisponivel, "imagem com midiaIndisponivel → .indisponivel, veio \(ver(bolha(foto, indisponivel: true)))")
    exigir(ver(bolha(video, indisponivel: true)) == .indisponivel, "vídeo com midiaIndisponivel → .indisponivel, veio \(ver(bolha(video, indisponivel: true)))")
    exigir(ver(bolha(foto)) == .imagem, "imagem → .imagem, veio \(ver(bolha(foto)))")
    exigir(ver(bolha(video)) == .video, "vídeo → .video, veio \(ver(bolha(video)))")

    let apagadaFoto = msg("x3", de: X, ts: t, tipo: .imagem, midia: midia("image/jpeg"), apagada: t + 60)
    let apagadaTexto = msg("x4", de: X, ts: t, apagada: t + 60)
    exigir(ver(bolha(apagadaFoto)) == .nenhuma, "imagem apagada → .nenhuma, veio \(ver(bolha(apagadaFoto)))")
    exigir(ver(bolha(apagadaTexto)) == .nenhuma, "texto apagado → .nenhuma, veio \(ver(bolha(apagadaTexto)))")

    let figurinha = msg("x5", de: X, ts: t, tipo: .figurinha, midia: midia("image/webp"))
    exigir(ver(bolha(figurinha)) == .figurinha, "figurinha → .figurinha, veio \(ver(bolha(figurinha)))")

    let doc = msg("x6", de: X, ts: t, tipo: .documento, midia: midia("application/pdf", nome: "contrato.pdf"))
    let voz = msg("x7", de: X, ts: t, tipo: .voz, midia: midia("audio/ogg; codecs=opus", segundos: 37))
    let texto = msg("x8", de: X, ts: t, texto: "só texto")
    exigir(ver(bolha(doc)) == .documento, "documento → .documento, veio \(ver(bolha(doc)))")
    exigir(ver(bolha(voz)) == .audio, "voz → .audio, veio \(ver(bolha(voz)))")
    exigir(ver(bolha(texto)) == .nenhuma, "texto → .nenhuma, veio \(ver(bolha(texto)))")
}

private func acaoDoClique() {
    let t = ts(dia: 4, hora: 13)
    func acao(_ b: WABolha) -> WAAcaoDaBolha { WAConversaModelo.acao(bolha: b) }

    let foto = msg("c1", de: X, ts: t, tipo: .imagem, texto: "a sala", midia: midia("image/jpeg"))
    let video = msg("c2", de: X, ts: t, tipo: .video, midia: midia("video/mp4", segundos: 14))
    let doc = msg("c3", de: X, ts: t, tipo: .documento, midia: midia("application/pdf", nome: "contrato.pdf"))
    let audio = msg("c4", de: X, ts: t, tipo: .audio, midia: midia("audio/mpeg", segundos: 95))
    let voz = msg("c5", de: X, ts: t, tipo: .voz, midia: midia("audio/ogg; codecs=opus", segundos: 37))
    let texto = msg("c6", de: X, ts: t, texto: "oi")
    let figurinha = msg("c7", de: X, ts: t, tipo: .figurinha, midia: midia("image/webp"))
    let apagada = msg("c8", de: X, ts: t, tipo: .imagem, midia: midia("image/jpeg"), apagada: t + 30)

    // foto e vídeo abrem no visualizador dentro do notch (etapa 1 do
    // visualizador; o resto do comportamento está no whatsappvisualizadorcheck)
    exigir(acao(bolha(foto)) == .verNoNotch, "clique na imagem → .verNoNotch, veio \(acao(bolha(foto)))")
    exigir(acao(bolha(video)) == .verNoNotch, "clique no vídeo → .verNoNotch, veio \(acao(bolha(video)))")
    exigir(acao(bolha(doc)) == .mostrarNoFinder, "clique no documento → .mostrarNoFinder, veio \(acao(bolha(doc)))")
    exigir(acao(bolha(audio)) == .tocarAudio, "clique no áudio → .tocarAudio, veio \(acao(bolha(audio)))")
    exigir(acao(bolha(voz)) == .tocarAudio, "clique na voz → .tocarAudio, veio \(acao(bolha(voz)))")

    exigir(acao(bolha(texto)) == .nenhuma, "texto → .nenhuma, veio \(acao(bolha(texto)))")
    exigir(acao(bolha(figurinha)) == .nenhuma, "figurinha → .nenhuma, veio \(acao(bolha(figurinha)))")
    exigir(acao(bolha(apagada)) == .nenhuma, "imagem apagada → .nenhuma, veio \(acao(bolha(apagada)))")
    exigir(acao(bolha(foto, indisponivel: true)) == .nenhuma,
           "imagem com mídia indisponível → .nenhuma, veio \(acao(bolha(foto, indisponivel: true)))")
    exigir(acao(bolha(video, indisponivel: true)) == .nenhuma,
           "vídeo com mídia indisponível → .nenhuma, veio \(acao(bolha(video, indisponivel: true)))")

    // bolha local ainda enviando: o arquivo ainda não é da ponte
    let fotoLocal = msg("local-r9", de: EU, ts: t, tipo: .imagem, midia: midia("image/jpeg"), status: nil)
    let docLocal = msg("local-r8", de: EU, ts: t, tipo: .documento, midia: midia("application/pdf", nome: "a.pdf"), status: nil)
    exigir(acao(bolha(fotoLocal, envio: .enviando(ref: "r9"))) == .nenhuma,
           "imagem local enviando → .nenhuma, veio \(acao(bolha(fotoLocal, envio: .enviando(ref: "r9"))))")
    exigir(acao(bolha(docLocal, envio: .enviando(ref: "r8"))) == .nenhuma,
           "documento local enviando → .nenhuma, veio \(acao(bolha(docLocal, envio: .enviando(ref: "r8"))))")
}

// MARK: - transporte e canal falsos

private func js(_ s: String?) -> String {
    guard let s else { return "null" }
    let d = try! JSONSerialization.data(withJSONObject: [s], options: [.fragmentsAllowed])
    let t = String(decoding: d, as: UTF8.self)
    return String(t.dropFirst().dropLast())
}

private let contaJSON =
    #"{"conta": \#(js(A)), "jid": \#(js(A + ":17@s.whatsapp.net")), "nome": null, "padrao": true, "estado": "conectada", "motivo": null, "desde": 1762270000, "nao_lidas": 0, "conversas_nao_lidas": 0}"#

private func conversaJSON(_ jid: String, tipo: String, nome: String, naoLidas: Int) -> String {
    #"{"jid": \#(js(jid)), "jids": [\#(js(jid))], "tipo": \#(js(tipo)), "nome": \#(js(nome)), "nao_lidas": \#(naoLidas), "marcada_nao_lida": false, "ts": 1762270300, "ultima": null}"#
}

private func mensagemJSON(_ id: String, conversa: String, ts: Int, texto: String) -> String {
    #"{"id": \#(js(id)), "conversa": \#(js(conversa)), "remetente": \#(js(conversa)), "remetente_nome": null, "de_mim": false, "ts": \#(ts), "tipo": "texto", "texto": \#(js(texto)), "midia": null, "citacao": null, "reacoes": [], "editada": null, "apagada": null, "status": null}"#
}

private let grupoJSON = #"""
{"jid": "\#(G)", "nome": "Projeto Aurora", "descricao": "", "criado": 1575256960, "dono": "554799000001@s.whatsapp.net", "so_admins_enviam": false, "participantes": [
  {"jid": "\#(EU)", "telefone": "554791744143", "lid": "11373408956608@lid", "nome": "Luccas Silveira", "admin": true, "superadmin": false, "eu": true},
  {"jid": "\#(ANA)", "telefone": "554799000001", "lid": null, "nome": "Ana Ribeiro", "admin": false, "superadmin": true, "eu": false},
  {"jid": "\#(DIEGO)", "telefone": null, "lid": "22222222222222@lid", "nome": "Diego Martins", "admin": false, "superadmin": false, "eu": false},
  {"jid": "\#(JULIA)", "telefone": "554799000003", "lid": null, "nome": "Júlia Souza", "admin": false, "superadmin": false, "eu": false}
]}
"""#

private func grupoEsperado() -> WAGrupo {
    do { return try WAJSON.decodificador.decode(WAGrupo.self, from: Data(grupoJSON.utf8)) } catch {
        print("FALHOU: fixture do grupo não decodifica: \(error) (tools/whatsappconversacheck.swift)")
        exit(1)
    }
}

private struct Pedido {
    let metodo: String
    let caminho: String
    let query: [String: String]
    let corpo: [String: Any]
}

private final class TransporteFalso: WATransporte {
    private let trava = NSLock()
    private var _pedidos: [Pedido] = []

    var pedidos: [Pedido] { trava.lock(); defer { trava.unlock() }; return _pedidos }
    func limpar() { trava.lock(); _pedidos = []; trava.unlock() }
    func de(_ caminho: String) -> [Pedido] { pedidos.filter { $0.caminho == caminho } }

    func enviar(_ pedido: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let comps = URLComponents(url: pedido.url!, resolvingAgainstBaseURL: false)!
        var q: [String: String] = [:]
        for item in comps.queryItems ?? [] { q[item.name] = item.value ?? "" }
        let corpo = pedido.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let p = Pedido(metodo: pedido.httpMethod ?? "GET", caminho: comps.path, query: q, corpo: corpo)
        registrar(p)

        let (status, texto) = responder(p)
        let r = HTTPURLResponse(url: pedido.url!, statusCode: status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json"])!
        return (Data(texto.utf8), r)
    }

    private func registrar(_ p: Pedido) { trava.lock(); _pedidos.append(p); trava.unlock() }

    private func responder(_ p: Pedido) -> (Int, String) {
        switch (p.metodo, p.caminho) {
        case ("GET", "/v1/contas"):
            return (200, #"{"ok": true, "contas": [\#(contaJSON)]}"#)
        case ("GET", "/v1/conversas"):
            let lista = [conversaJSON(X, tipo: "individual", nome: "Marina Costa", naoLidas: 2),
                         conversaJSON(G, tipo: "grupo", nome: "Projeto Aurora", naoLidas: 0)]
            return (200, #"{"ok": true, "conversas": [\#(lista.joined(separator: ", "))], "antes": null}"#)
        case ("GET", "/v1/pareamento"):
            return (404, #"{"ok": false, "erro": "sem_pareamento", "detalhe": "nada em andamento"}"#)
        case ("GET", "/v1/mensagens"):
            let jid = p.query["conversa"] ?? ""
            let msgs = jid == X
                ? [mensagemJSON("m1", conversa: X, ts: 1_762_270_100, texto: "Bom dia"),
                   mensagemJSON("m2", conversa: X, ts: 1_762_270_200, texto: "Viu?")]
                : []
            return (200, #"{"ok": true, "conversa": \#(js(jid)), "mensagens": [\#(msgs.joined(separator: ", "))], "antes": null}"#)
        case ("GET", "/v1/grupo"):
            guard p.query["jid"] == G else {
                return (404, #"{"ok": false, "erro": "conversa_inexistente", "detalhe": "x"}"#)
            }
            return (200, #"{"ok": true, "grupo": \#(grupoJSON)}"#)
        case ("POST", "/v1/lida"):
            return (200, #"{"ok": true, "marcadas": 2}"#)
        default:
            return (404, #"{"ok": false, "erro": "rota_inexistente", "detalhe": "x"}"#)
        }
    }
}

private final class CanalFalso: WACanalProtocolo {
    var aoEvento: ((WAEvento) -> Void)?
    var aoRessincronizar: ((String, Int) -> Void)?
    var aoMudarEstado: ((WAEstadoDoCanal) -> Void)?
    func iniciar() {}
    func parar() { aoMudarEstado?(.parado) }
    func acordou() {}
    func mudar(_ e: WAEstadoDoCanal) { aoMudarEstado?(e) }
}

/// Relógio do store, que o teste avança à mão.
private final class Relogio {
    var agora: Date
    init(_ d: Date) { agora = d }
}

// MARK: - montagem

private let pastaBase = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("whatsappconversacheck-\(getpid())", isDirectory: true)
private let arquivoDaChave: URL = {
    let u = pastaBase.appendingPathComponent("api-key")
    try! FileManager.default.createDirectory(at: pastaBase, withIntermediateDirectories: true)
    try! Data("chave-de-teste\n".utf8).write(to: u)
    return u
}()

@MainActor
private final class Montagem {
    let t = TransporteFalso()
    let relogio = Relogio(data(dia: 4, hora: 15))
    var canais: [CanalFalso] = []
    var store: WhatsAppStore!

    init() {
        let cliente = WACliente(porta: 18099, caminhoDaChave: arquivoDaChave, transporte: t)
        let r = relogio
        store = WhatsAppStore(cliente: cliente, fabricaDeCanal: { [unowned self] _ in
            let c = CanalFalso()
            self.canais.append(c)
            return c
        }, agora: { r.agora })
    }
}

@MainActor
private func esperar(_ desc: String, linha: UInt = #line, _ cond: () -> Bool) async {
    for _ in 0..<3000 {
        if cond() { return }
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
    exigir(cond(), "esperou 3 s e não aconteceu: \(desc)", linha: linha)
}

@MainActor
private func assentar() async {
    for _ in 0..<60 { try? await Task.sleep(nanoseconds: 1_000_000) }
}

/// Store com canal aberto e a primeira carga terminada; pedidos zerados.
@MainActor
private func montarPronta(linha: UInt = #line) async -> Montagem {
    let m = Montagem()
    await m.store.iniciar()
    exigir(!m.canais.isEmpty, "nenhum canal foi criado", linha: linha)
    m.canais.last!.mudar(.aberto)
    await esperar("primeira carga terminar em .pronta", linha: linha) { m.store.conexao == .pronta }
    await assentar()
    m.t.limpar()
    return m
}

// MARK: - store

/// Abrir a conversa lê as mensagens e nunca marca lida; o botão "Marcar como
/// lida" (store.marcarLida) manda um POST /v1/lida da conta e da conversa.
@MainActor
private func marcarComoLida() async {
    let m = await montarPronta()
    await m.store.abrir(kX)
    await assentar()
    exigir(!m.t.de("/v1/mensagens").isEmpty, "abrir a conversa não leu as mensagens")
    exigir(m.t.de("/v1/lida").isEmpty, "abrir a conversa marcou como lida (\(m.t.de("/v1/lida").count) POST /v1/lida)")

    await m.store.marcarLida(kX)
    let lidas = m.t.de("/v1/lida")
    exigir(lidas.count == 1, "\"Marcar como lida\" deveria mandar 1 POST /v1/lida, mandou \(lidas.count)")
    if let p = lidas.first {
        exigir(p.metodo == "POST", "/v1/lida tem que ser POST, foi \(p.metodo)")
        exigir(p.corpo["conta"] as? String == A, "/v1/lida com conta errada: \(String(describing: p.corpo["conta"]))")
        exigir(p.corpo["conversa"] as? String == X, "/v1/lida com conversa errada: \(String(describing: p.corpo["conversa"]))")
    }
    m.store.fechar(kX)
}

/// `store.grupo(k)`: grupo pede uma vez e guarda 10 min pelo relógio injetado;
/// conversa individual devolve `nil` sem pedido.
@MainActor
private func grupoGuardado() async {
    let m = await montarPronta()
    let esperado = grupoEsperado()
    let t0 = m.relogio.agora

    let g1 = await m.store.grupo(kG)
    exigir(g1 == esperado, "store.grupo(@g.us) deveria devolver o grupo da ponte, veio \(String(describing: g1))")
    var pedidos = m.t.de("/v1/grupo")
    exigir(pedidos.count == 1, "primeira chamada: 1 GET /v1/grupo, foram \(pedidos.count)")
    if let p = pedidos.first {
        exigir(p.metodo == "GET", "/v1/grupo tem que ser GET, foi \(p.metodo)")
        exigir(p.query["conta"] == A, "/v1/grupo com conta errada: \(String(describing: p.query["conta"]))")
        exigir(p.query["jid"] == G, "/v1/grupo com jid errado: \(String(describing: p.query["jid"]))")
    }

    m.relogio.agora = t0.addingTimeInterval(5 * 60)
    let g2 = await m.store.grupo(kG)
    exigir(g2 == esperado, "segunda chamada (5 min depois) deveria devolver o grupo guardado, veio \(String(describing: g2))")
    m.relogio.agora = t0.addingTimeInterval(9 * 60 + 59)
    let g3 = await m.store.grupo(kG)
    exigir(g3 == esperado, "chamada 9min59s depois deveria devolver o grupo guardado, veio \(String(describing: g3))")
    pedidos = m.t.de("/v1/grupo")
    exigir(pedidos.count == 1, "antes de 10 min o store não pede de novo; foram \(pedidos.count) GET /v1/grupo")

    m.relogio.agora = t0.addingTimeInterval(10 * 60 + 1)
    let g4 = await m.store.grupo(kG)
    exigir(g4 == esperado, "depois de 10 min deveria devolver o grupo relido, veio \(String(describing: g4))")
    pedidos = m.t.de("/v1/grupo")
    exigir(pedidos.count == 2, "depois de 10 min (contados da leitura) o store pede de novo; foram \(pedidos.count) GET /v1/grupo")

    let antes = m.t.pedidos.count
    let individual = await m.store.grupo(kX)
    await assentar()
    exigir(individual == nil, "conversa individual: store.grupo deveria ser nil, veio \(String(describing: individual))")
    exigir(m.t.pedidos.count == antes,
           "conversa individual não pede nada; pediu \(m.t.pedidos.dropFirst(antes).map { $0.metodo + " " + $0.caminho })")
}

// MARK: - ligação (views e harness de snapshot, que o check.sh não compila)

/// Linhas de código do arquivo, sem as de comentário (`//`); `nil` se falta.
private func codigo(_ caminho: String) -> [String]? {
    guard let t = try? String(contentsOfFile: caminho, encoding: .utf8) else { return nil }
    return t.components(separatedBy: "\n").filter {
        !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//")
    }
}

private func ligacao() {
    let conversaView = "Knobler/WhatsApp/WhatsAppConversaView.swift"
    let bolhaView = "Knobler/WhatsApp/WhatsAppBolhaView.swift"
    let secaoView = "Knobler/WhatsApp/WhatsAppSecaoView.swift"
    let modelo = "Knobler/WhatsApp/WhatsAppConversaModelo.swift"
    let fontes = "tools/notchview-fontes.txt"
    let harness = "tools/main.swift"

    exigir(FileManager.default.fileExists(atPath: "tools/check.sh"),
           "rode da raiz do repo (o check.sh faz isso); cwd = \(FileManager.default.currentDirectoryPath)")

    for f in [conversaView, bolhaView, secaoView, modelo, harness, fontes] {
        exigir(codigo(f) != nil, "\(f) não existe")
    }
    let conv = codigo(conversaView)!, bol = codigo(bolhaView)!, sec = codigo(secaoView)!
    let views = conv + bol
    func tem(_ ls: [String], _ s: String) -> Bool { ls.contains { $0.contains(s) } }
    func conta(_ ls: [String], _ s: String) -> Int { ls.filter { $0.contains(s) }.count }

    // a coluna direita mostra a conversa
    exigir(tem(sec, "WhatsAppConversaView("), "\(secaoView) não mostra WhatsAppConversaView( na coluna direita")

    // cabeçalho: botão "Marcar como lida" é o único caminho que marca lida
    exigir(tem(conv, "WATextos.marcarComoLida") || tem(conv, "\"Marcar como lida\""),
           "\(conversaView) sem o botão \"Marcar como lida\"")
    exigir(tem(conv, "WAConversaModelo.cabecalho("), "\(conversaView) não usa WAConversaModelo.cabecalho(")
    // uma chamada só, a do botão: abrir a conversa (.task/.onAppear) não marca
    let marcam = conta(views + sec, ".marcarLida(")
    exigir(marcam == 1, "store.marcarLida( tem que ser chamado num lugar só das views da conversa (o botão); apareceu \(marcam)")
    exigir(tem(conv, ".grupo("), "\(conversaView) não pede os participantes do grupo (store.grupo)")

    // lista: abre na mais recente, pagina pela primeira linha
    exigir(tem(conv, "WAConversaModelo.linhas("), "\(conversaView) não monta as linhas por WAConversaModelo.linhas(")
    exigir(tem(conv, ".defaultScrollAnchor(.bottom)"), "\(conversaView) sem .defaultScrollAnchor(.bottom): abriria na mais antiga")
    exigir(tem(conv, "carregarMais("), "\(conversaView) não pede a página antiga (carregarMais)")

    // clique na mídia
    exigir(tem(views, "WAConversaModelo.acao("), "o clique na mídia não segue WAConversaModelo.acao(")
    exigir(tem(views, "WAConversaModelo.mostraMidia("), "a bolha não decide a mídia por WAConversaModelo.mostraMidia(")
    exigir(tem(views, ".arquivo(chave:"), "o clique não pede o arquivo da mídia (store.midia.arquivo(chave:mensagem:))")
    // foto/vídeo: o clique abre o visualizador; o NSWorkspace.shared.open só
    // sobra no botão dele (tools/whatsappvisualizadorligacaocheck.sh)
    exigir(!tem(views, "NSWorkspace.shared.open("),
           "foto/vídeo ainda abrem no app padrão pelo clique na bolha (NSWorkspace.shared.open)")
    exigir(tem(views, "activateFileViewerSelecting("), "documento não aparece no Finder (activateFileViewerSelecting)")
    exigir(tem(views, "WAPlayer.shared.tocar("), "áudio não toca pelo WAPlayer.shared.tocar(")

    // falha: "não enviada · tentar de novo" chama retentar
    exigir(tem(views, "retentar("), "\"tentar de novo\" não chama store.retentar")
    exigir(tem(views, "WATextos.falhaAcao") || tem(views, "\"tentar de novo\""), "sem o botão \"tentar de novo\"")

    // símbolo da mídia indisponível que existe no target 14.2
    exigir(tem(views, "exclamationmark.triangle"), "mídia indisponível sem exclamationmark.triangle")
    exigir(!tem(views, "photo.badge.exclamationmark"),
           "photo.badge.exclamationmark só existe a partir do macOS 15; o target é 14.2")

    // snapshot: fontes e cenários
    let ft = codigo(fontes)!.map { $0.trimmingCharacters(in: .whitespaces) }
    for f in [modelo, conversaView, bolhaView] {
        exigir(ft.contains(f), "\(fontes) sem \(f)")
    }
    let mn = codigo(harness)!
    for c in ["whatsapp-conversa-marina", "whatsapp-conversa-entrega", "whatsapp-grupo-midia",
              "whatsapp-grupo-reacao", "whatsapp-grupo-falha"] {
        exigir(tem(mn, "\"\(c)\""), "\(harness) sem o cenário \"\(c)\"")
    }
}

// MARK: - main

@main
enum Gate {
    @MainActor
    static func main() async {
        defer { try? FileManager.default.removeItem(at: pastaBase) }
        linhasIndividual()
        linhasGrupo()
        podeAgir()
        cabecalho()
        mostraMidia()
        acaoDoClique()
        await marcarComoLida()
        await grupoGuardado()
        ligacao()
        print("whatsappconversacheck ok")
    }
}
