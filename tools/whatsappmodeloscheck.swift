// Gate da etapa 1 do WhatsApp: tipos do contrato da ponte e decodificação
// (Knobler/WhatsApp/WhatsAppModelos.swift). Os JSON de exemplo são os do
// contrato, docs/whatsapp-ponte.md, copiados para cá.
//
//   xcrun swiftc -parse-as-library -swift-version 5 \
//     Knobler/WhatsApp/WhatsAppModelos.swift tools/whatsappmodeloscheck.swift \
//     -o /tmp/whatsappmodeloscheck && /tmp/whatsappmodeloscheck

import Foundation

private func exigir(_ cond: Bool, _ msg: String) {
    if !cond {
        print("FALHOU: \(msg)")
        exit(1)
    }
}

/// Decodifica com o decodificador do app; erro de decodificação reprova com a causa.
private func ler<T: Decodable>(_ tipo: T.Type, _ json: String, _ contexto: String) -> T {
    do {
        return try WAJSON.decodificador.decode(T.self, from: Data(json.utf8))
    } catch {
        print("FALHOU: \(contexto) não decodificou: \(error)")
        exit(1)
    }
}

private func evento(_ texto: String, _ contexto: String) -> WAEvento {
    guard let e = WAEvento.decodificar(texto) else {
        print("FALHOU: \(contexto): WAEvento.decodificar devolveu nil")
        exit(1)
    }
    return e
}

/// Só para provar o codificador sem depender de qual tipo do app é Encodable.
private struct AmostraCodificavel: Encodable {
    let deMim: Bool
    let qrExpiraEm: Int
    let remetenteNome: String?
}

// MARK: - JSON do contrato

// docs/whatsapp-ponte.md:297-309
private let contaJSON = #"""
{
  "conta": "554791744143",
  "jid": "554791744143:17@s.whatsapp.net",
  "nome": "Luccas Silveira",
  "padrao": true,
  "estado": "conectada",
  "motivo": null,
  "desde": 1762270000,
  "nao_lidas": 12,
  "conversas_nao_lidas": 3
}
"""#

private let contaDeslogadaJSON = #"""
{"conta": "554792508292", "jid": null, "nome": null, "padrao": false, "estado": "deslogada",
 "motivo": "logout", "desde": 1762270100, "nao_lidas": 0, "conversas_nao_lidas": 0}
"""#

private let contaHibernandoJSON = #"""
{"conta": "554792508292", "jid": null, "nome": null, "padrao": false, "estado": "hibernando",
 "motivo": null, "desde": 1762270100, "nao_lidas": 0, "conversas_nao_lidas": 0}
"""#

// docs/whatsapp-ponte.md:317-338
private let ultimaImagemJSON = #"""
{
  "id": "3EB0A1B2C3D4E5F6",
  "de_mim": false,
  "remetente": "5547999990000@s.whatsapp.net",
  "remetente_nome": "Fulano",
  "tipo": "imagem",
  "previa": "olha isso",
  "ts": 1762270500,
  "segundos": null,
  "apagada": null
}
"""#

private func conversaJSON(ultima: String, tipo: String = "individual") -> String {
    """
    {
      "jid": "5547999990000@s.whatsapp.net",
      "jids": ["5547999990000@s.whatsapp.net", "157192044961796@lid"],
      "tipo": "\(tipo)",
      "nome": "Fulano",
      "nao_lidas": 2,
      "marcada_nao_lida": false,
      "ts": 1762270500,
      "ultima": \(ultima)
    }
    """
}

private let conversaDocJSON = conversaJSON(ultima: ultimaImagemJSON)

private let ultimaVideoJSON = #"""
{"id": "3EB0V1", "de_mim": true, "remetente": "554791744143@s.whatsapp.net", "remetente_nome": null,
 "tipo": "video", "previa": "", "ts": 1762270600, "segundos": 18, "apagada": null}
"""#

private let ultimaApagadaJSON = #"""
{"id": "3EB0A2", "de_mim": false, "remetente": "5547999990000@s.whatsapp.net", "remetente_nome": "Fulano",
 "tipo": "texto", "previa": "", "ts": 1762270600, "segundos": null, "apagada": 1762270630}
"""#

// ponte mais velha: sem as chaves `segundos` e `apagada`
private let ultimaSemChavesJSON = #"""
{"id": "3EB0A3", "de_mim": false, "remetente": "5547999990000@s.whatsapp.net", "remetente_nome": "Fulano",
 "tipo": "texto", "previa": "oi", "ts": 1762270600}
"""#

// docs/whatsapp-ponte.md:355-379
private let mensagemDocJSON = #"""
{
  "id": "3EB0A1B2C3D4E5F6",
  "conversa": "120363406741729308@g.us",
  "remetente": "5547999990000@s.whatsapp.net",
  "remetente_nome": "Fulano",
  "de_mim": false,
  "ts": 1762270500,
  "tipo": "imagem",
  "texto": "olha isso",
  "midia": {
    "mimetype": "image/jpeg",
    "nome": "3EB0A1B2C3D4E5F6.jpg",
    "tamanho": 183422,
    "segundos": null,
    "miniatura": true,
    "baixada": false
  },
  "citacao": {"id": "3EB0FFEE", "remetente": "554791744143@s.whatsapp.net", "texto": "e aí?"},
  "reacoes": [{"remetente": "554792508292@s.whatsapp.net", "de_mim": false, "emoji": "❤️", "ts": 1762270510}],
  "editada": null,
  "apagada": null,
  "status": null
}
"""#

/// Mensagem de texto simples; `reacoes: nil` tira a chave do JSON.
private func mensagemJSON(tipo: String = "texto", deMim: Bool = false, status: String = "null",
                          reacoes: String? = "[]") -> String {
    let chaveReacoes = reacoes.map { "\"reacoes\": \($0)," } ?? ""
    return """
    {"id": "3EB0B0B0", "conversa": "5547999990000@s.whatsapp.net",
     "remetente": "\(deMim ? "554791744143@s.whatsapp.net" : "5547999990000@s.whatsapp.net")",
     "remetente_nome": null, "de_mim": \(deMim), "ts": 1762270700, "tipo": "\(tipo)",
     "texto": "oi", "midia": null, "citacao": null, \(chaveReacoes)
     "editada": null, "apagada": null, "status": \(status)}
    """
}

// docs/whatsapp-ponte.md:398-408
private let pareamentoQRJSON = #"""
{
  "id": "p-7f3a9c",
  "estado": "qr",
  "qr": "2@AbCdEf…,…,…",
  "qr_expira_em": 1762270620,
  "fim": 1762270720,
  "conta": null,
  "motivo": null
}
"""#

// `qr` e `qr_expira_em` só existem em estado = qr
private let pareamentoExpiradoJSON = #"""
{"id": "p-7f3a9c", "estado": "expirado", "fim": 1762270720, "conta": null, "motivo": null}
"""#

// docs/whatsapp-ponte.md:541-555, com um segundo participante sem telefone nem lid
private let grupoJSON = #"""
{
  "jid": "120363406741729308@g.us",
  "nome": "COISAS",
  "descricao": "",
  "criado": 1575256960,
  "dono": "554792508292@s.whatsapp.net",
  "so_admins_enviam": false,
  "participantes": [
    {"jid": "554791744143@s.whatsapp.net", "telefone": "554791744143", "lid": "11373408956608@lid", "nome": "Luccas Silveira", "admin": true, "superadmin": false, "eu": true},
    {"jid": "99887766554433@lid", "telefone": null, "lid": null, "nome": null, "admin": false, "superadmin": false, "eu": false}
  ]
}
"""#

private func numerado(seq: Int, tipo: String, ts: Int = 1762270601, dados: String) -> String {
    #"{"seq": \#(seq), "tipo": "\#(tipo)", "conta": "554791744143", "ts": \#(ts), "dados": \#(dados)}"#
}

@main
enum WhatsAppModelosCheck {
    static func main() {
        conta()
        conversa()
        mensagem()
        status()
        pareamentoEGrupo()
        eventos()
        respostas()
        chave()
        codificador()
        print("ok")
    }

    // MARK: Conta

    static func conta() {
        let c = ler(WAConta.self, contaJSON, "conta do contrato")
        exigir(c.conta == "554791744143", "conta: número '\(c.conta)'")
        exigir(c.jid == "554791744143:17@s.whatsapp.net", "conta: jid \(String(describing: c.jid))")
        exigir(c.nome == "Luccas Silveira", "conta: nome \(String(describing: c.nome))")
        exigir(c.padrao == true, "conta: padrao deveria ser true")
        exigir(c.estado == .conectada, "conta: estado \(c.estado), esperado .conectada")
        exigir(c.motivo == nil, "conta: motivo null deveria ser nil")
        exigir(c.desde == 1762270000, "conta: desde \(c.desde)")
        exigir(c.naoLidas == 12, "conta: nao_lidas \(c.naoLidas), esperado 12")
        exigir(c.conversasNaoLidas == 3, "conta: conversas_nao_lidas \(c.conversasNaoLidas), esperado 3")

        let d = ler(WAConta.self, contaDeslogadaJSON, "conta deslogada")
        exigir(d.jid == nil, "conta deslogada: jid null deveria ser nil")
        exigir(d.estado == .deslogada, "conta deslogada: estado \(d.estado), esperado .deslogada")
        exigir(d.motivo == "logout", "conta deslogada: motivo \(String(describing: d.motivo))")
        exigir(d.padrao == false, "conta deslogada: padrao deveria ser false")

        let h = ler(WAConta.self, contaHibernandoJSON, "conta com estado desconhecido")
        exigir(h.estado == .outro("hibernando"),
               "estado desconhecido: \(h.estado), esperado .outro(\"hibernando\")")
        exigir(h.estado != .deslogada && h.estado != .conectada, "estado desconhecido caiu num caso conhecido")
    }

    // MARK: Conversa

    static func conversa() {
        let c = ler(WAConversa.self, conversaDocJSON, "conversa do contrato")
        exigir(c.jid == "5547999990000@s.whatsapp.net", "conversa: jid \(c.jid)")
        exigir(c.jids == ["5547999990000@s.whatsapp.net", "157192044961796@lid"],
               "conversa: jids \(c.jids), esperado os dois apelidos")
        exigir(c.tipo == .individual, "conversa: tipo \(c.tipo), esperado .individual")
        exigir(c.nome == "Fulano", "conversa: nome \(c.nome)")
        exigir(c.naoLidas == 2, "conversa: nao_lidas \(c.naoLidas)")
        exigir(c.marcadaNaoLida == false, "conversa: marcada_nao_lida deveria ser false")
        exigir(c.ts == 1762270500, "conversa: ts \(c.ts)")
        guard let u = c.ultima else { exigir(false, "conversa: ultima veio nil"); return }
        exigir(u.id == "3EB0A1B2C3D4E5F6", "ultima: id \(u.id)")
        exigir(u.deMim == false, "ultima: de_mim deveria ser false")
        exigir(u.remetente == "5547999990000@s.whatsapp.net", "ultima: remetente \(u.remetente)")
        exigir(u.remetenteNome == "Fulano", "ultima: remetente_nome \(String(describing: u.remetenteNome))")
        exigir(u.tipo == .imagem, "ultima: tipo \(u.tipo), esperado .imagem")
        exigir(u.previa == "olha isso", "ultima: previa '\(u.previa)'")
        exigir(u.ts == 1762270500, "ultima: ts \(u.ts)")
        exigir(u.segundos == nil, "ultima: segundos null deveria ser nil")
        exigir(u.apagada == nil, "ultima: apagada null deveria ser nil")

        let semUltima = ler(WAConversa.self, conversaJSON(ultima: "null"), "conversa com ultima null")
        exigir(semUltima.ultima == nil, "conversa: \"ultima\": null deveria virar nil")

        let grupo = ler(WAConversa.self, conversaJSON(ultima: "null", tipo: "grupo"), "conversa de grupo")
        exigir(grupo.tipo == .grupo, "conversa: tipo \(grupo.tipo), esperado .grupo")
        let outra = ler(WAConversa.self, conversaJSON(ultima: "null", tipo: "comunidade"), "conversa de tipo novo")
        exigir(outra.tipo == .outro("comunidade"), "conversa: tipo novo \(outra.tipo), esperado .outro")

        let video = ler(WAConversa.self, conversaJSON(ultima: ultimaVideoJSON), "ultima de vídeo")
        exigir(video.ultima?.tipo == .video, "ultima de vídeo: tipo \(String(describing: video.ultima?.tipo))")
        exigir(video.ultima?.segundos == 18, "ultima de vídeo: segundos \(String(describing: video.ultima?.segundos)), esperado 18")
        exigir(video.ultima?.apagada == nil, "ultima de vídeo: apagada deveria ser nil")
        exigir(video.ultima?.remetenteNome == nil, "ultima de vídeo: remetente_nome null deveria ser nil")
        exigir(video.ultima?.deMim == true, "ultima de vídeo: de_mim deveria ser true")

        let apagada = ler(WAConversa.self, conversaJSON(ultima: ultimaApagadaJSON), "ultima apagada")
        exigir(apagada.ultima?.apagada == 1762270630,
               "ultima apagada: apagada \(String(describing: apagada.ultima?.apagada)), esperado 1762270630")
        exigir(apagada.ultima?.segundos == nil, "ultima apagada: segundos deveria ser nil")
        exigir(apagada.ultima?.previa == "", "ultima apagada: previa deveria ser vazia")

        let velha = ler(WAConversa.self, conversaJSON(ultima: ultimaSemChavesJSON),
                        "ultima sem as chaves segundos/apagada (ponte mais velha)")
        exigir(velha.ultima != nil, "ponte mais velha: ultima sumiu")
        exigir(velha.ultima?.segundos == nil, "ponte mais velha: segundos ausente deveria ser nil")
        exigir(velha.ultima?.apagada == nil, "ponte mais velha: apagada ausente deveria ser nil")
        exigir(velha.ultima?.previa == "oi", "ponte mais velha: previa '\(velha.ultima?.previa ?? "nil")'")

        // a lista não cai inteira por uma conversa de ponte mais velha
        let lista = ler([WAConversa].self, "[\(conversaDocJSON), \(conversaJSON(ultima: ultimaSemChavesJSON))]",
                        "lista com conversa de ponte mais velha")
        exigir(lista.count == 2, "lista de conversas: \(lista.count) itens, esperado 2")
    }

    // MARK: Mensagem

    static func mensagem() {
        let m = ler(WAMensagem.self, mensagemDocJSON, "mensagem do contrato")
        exigir(m.id == "3EB0A1B2C3D4E5F6", "mensagem: id \(m.id)")
        exigir(m.conversa == "120363406741729308@g.us", "mensagem: conversa \(m.conversa)")
        exigir(m.remetente == "5547999990000@s.whatsapp.net", "mensagem: remetente \(m.remetente)")
        exigir(m.remetenteNome == "Fulano", "mensagem: remetente_nome \(String(describing: m.remetenteNome))")
        exigir(m.deMim == false, "mensagem: de_mim deveria ser false")
        exigir(m.ts == 1762270500, "mensagem: ts \(m.ts)")
        exigir(m.tipo == .imagem, "mensagem: tipo \(m.tipo), esperado .imagem")
        exigir(m.texto == "olha isso", "mensagem: texto '\(m.texto)'")

        guard let midia = m.midia else { exigir(false, "mensagem: midia veio nil"); return }
        exigir(midia.mimetype == "image/jpeg", "midia: mimetype \(midia.mimetype)")
        exigir(midia.nome == "3EB0A1B2C3D4E5F6.jpg", "midia: nome \(midia.nome)")
        exigir(midia.tamanho == 183422, "midia: tamanho \(midia.tamanho)")
        exigir(midia.segundos == nil, "midia: segundos null deveria ser nil")
        exigir(midia.miniatura == true, "midia: miniatura deveria ser true")
        exigir(midia.baixada == false, "midia: baixada deveria ser false")

        guard let cit = m.citacao else { exigir(false, "mensagem: citacao veio nil"); return }
        exigir(cit.id == "3EB0FFEE", "citacao: id \(cit.id)")
        exigir(cit.remetente == "554791744143@s.whatsapp.net", "citacao: remetente \(cit.remetente)")
        exigir(cit.texto == "e aí?", "citacao: texto '\(cit.texto)'")

        exigir(m.reacoes.count == 1, "mensagem: \(m.reacoes.count) reações, esperado 1")
        if let r = m.reacoes.first {
            exigir(r.remetente == "554792508292@s.whatsapp.net", "reacao: remetente \(r.remetente)")
            exigir(r.deMim == false, "reacao: de_mim deveria ser false")
            exigir(r.emoji == "❤️", "reacao: emoji '\(r.emoji)'")
            exigir(r.ts == 1762270510, "reacao: ts \(r.ts)")
        }
        exigir(m.editada == nil, "mensagem: editada null deveria ser nil")
        exigir(m.apagada == nil, "mensagem: apagada null deveria ser nil")
        exigir(m.status == nil, "mensagem: status null deveria ser nil")

        let semReacoes = ler(WAMensagem.self, mensagemJSON(reacoes: nil), "mensagem sem a chave reacoes")
        exigir(semReacoes.reacoes.isEmpty, "mensagem sem reacoes: lista deveria ser vazia")
        exigir(semReacoes.midia == nil && semReacoes.citacao == nil, "mensagem de texto: midia/citacao deveriam ser nil")

        let lida = ler(WAMensagem.self, mensagemJSON(deMim: true, status: "\"lida\""), "mensagem com status lida")
        exigir(lida.status == .lida, "mensagem: status \(String(describing: lida.status)), esperado .lida")
        exigir(lida.deMim == true, "mensagem com status: de_mim deveria ser true")

        let entregue = ler(WAMensagem.self, mensagemJSON(deMim: true, status: "\"entregue\""), "mensagem entregue")
        exigir(entregue.status == .entregue, "mensagem: status \(String(describing: entregue.status)), esperado .entregue")

        let tipos: [(String, WATipoMensagem)] = [
            ("texto", .texto), ("imagem", .imagem), ("video", .video), ("audio", .audio),
            ("voz", .voz), ("documento", .documento), ("figurinha", .figurinha),
        ]
        for (bruto, esperado) in tipos {
            let t = ler(WAMensagem.self, mensagemJSON(tipo: bruto), "mensagem de tipo \(bruto)")
            exigir(t.tipo == esperado, "tipo \"\(bruto)\" virou \(t.tipo), esperado \(esperado)")
        }
        // os sete são distintos entre si
        for (i, a) in tipos.enumerated() {
            for b in tipos[(i + 1)...] {
                exigir(a.1 != b.1, "tipos \(a.0) e \(b.0) decodificam igual")
            }
        }
        let nova = ler(WAMensagem.self, mensagemJSON(tipo: "enquete"), "mensagem de tipo novo")
        exigir(nova.tipo == .outro("enquete"), "tipo novo virou \(nova.tipo), esperado .outro(\"enquete\")")

        // o estado cria bolha local com o init memberwise e muda os campos variáveis
        var bolha = WAMensagem(id: "local-1", conversa: "5547999990000@s.whatsapp.net",
                               remetente: "554791744143@s.whatsapp.net", remetenteNome: nil,
                               deMim: true, ts: 1762270800, tipo: .texto, texto: "oi",
                               midia: nil, citacao: nil, reacoes: [], editada: nil,
                               apagada: nil, status: .enviada)
        exigir(bolha.status == .enviada && bolha.texto == "oi", "init memberwise da WAMensagem")
        bolha.texto = "oi de novo"
        bolha.status = .entregue
        bolha.editada = 1762270810
        bolha.apagada = 1762270820
        bolha.midia = nil
        bolha.reacoes = m.reacoes
        exigir(bolha.texto == "oi de novo" && bolha.status == .entregue && bolha.reacoes.count == 1
               && bolha.editada == 1762270810 && bolha.apagada == 1762270820,
               "campos variáveis da WAMensagem não mudaram")
        exigir(bolha != lida, "WAMensagem: mensagens diferentes comparam iguais")
        exigir(m == ler(WAMensagem.self, mensagemDocJSON, "mensagem do contrato de novo"),
               "WAMensagem: a mesma mensagem não compara igual")
    }

    // MARK: Status

    static func status() {
        exigir(WAStatus.enviada < WAStatus.entregue, "WAStatus: enviada < entregue")
        exigir(WAStatus.entregue < WAStatus.lida, "WAStatus: entregue < lida")
        exigir(WAStatus.enviada < WAStatus.lida, "WAStatus: enviada < lida")
        exigir(!(WAStatus.lida < WAStatus.enviada), "WAStatus: lida não é menor que enviada")
        exigir(!(WAStatus.lida < WAStatus.lida), "WAStatus: lida não é menor que ela mesma")
        exigir([WAStatus.lida, .enviada, .entregue].sorted() == [.enviada, .entregue, .lida],
               "WAStatus: ordenação")
        exigir([WAStatus.entregue, .lida, .enviada].max() == .lida, "WAStatus: max")
        exigir(WAStatus(rawValue: "entregue") == .entregue, "WAStatus: rawValue entregue")
        exigir(WAStatus.lida.rawValue == "lida", "WAStatus: rawValue de .lida")
    }

    // MARK: Pareamento e grupo

    static func pareamentoEGrupo() {
        let p = ler(WAPareamento.self, pareamentoQRJSON, "pareamento em qr")
        exigir(p.id == "p-7f3a9c", "pareamento: id \(p.id)")
        exigir(p.estado == .qr, "pareamento: estado \(p.estado), esperado .qr")
        exigir(p.qr == "2@AbCdEf…,…,…", "pareamento: qr \(String(describing: p.qr))")
        exigir(p.qrExpiraEm == 1762270620, "pareamento: qr_expira_em \(String(describing: p.qrExpiraEm))")
        exigir(p.fim == 1762270720, "pareamento: fim \(String(describing: p.fim))")
        exigir(p.conta == nil && p.motivo == nil, "pareamento: conta/motivo null deveriam ser nil")

        let e = ler(WAPareamento.self, pareamentoExpiradoJSON, "pareamento expirado")
        exigir(e.estado == .expirado, "pareamento: estado \(e.estado), esperado .expirado")
        exigir(e.qr == nil, "pareamento expirado: qr deveria ser nil")
        exigir(e.qrExpiraEm == nil, "pareamento expirado: qr_expira_em deveria ser nil")

        let g = ler(WAGrupo.self, grupoJSON, "grupo")
        exigir(g.jid == "120363406741729308@g.us", "grupo: jid \(g.jid)")
        exigir(g.nome == "COISAS", "grupo: nome \(g.nome)")
        exigir(g.descricao == "", "grupo: descricao '\(g.descricao)'")
        exigir(g.criado == 1575256960, "grupo: criado \(g.criado)")
        exigir(g.dono == "554792508292@s.whatsapp.net", "grupo: dono \(String(describing: g.dono))")
        exigir(g.soAdminsEnviam == false, "grupo: so_admins_enviam deveria ser false")
        exigir(g.participantes.count == 2, "grupo: \(g.participantes.count) participantes, esperado 2")
        guard g.participantes.count == 2 else { return }
        let eu = g.participantes[0], outro = g.participantes[1]
        exigir(eu.jid == "554791744143@s.whatsapp.net", "participante: jid \(eu.jid)")
        exigir(eu.telefone == "554791744143", "participante: telefone \(String(describing: eu.telefone))")
        exigir(eu.lid == "11373408956608@lid", "participante: lid \(String(describing: eu.lid))")
        exigir(eu.nome == "Luccas Silveira", "participante: nome \(String(describing: eu.nome))")
        exigir(eu.admin && !eu.superadmin && eu.eu, "participante: admin/superadmin/eu")
        exigir(outro.telefone == nil, "participante: telefone null deveria ser nil")
        exigir(outro.lid == nil, "participante: lid null deveria ser nil")
        exigir(outro.nome == nil, "participante: nome null deveria ser nil")
        exigir(!outro.admin && !outro.eu, "participante 2: admin/eu deveriam ser false")
    }

    // MARK: Eventos

    static func eventos() {
        let m = ler(WAMensagem.self, mensagemDocJSON, "mensagem do evento")
        let c = ler(WAConversa.self, conversaDocJSON, "conversa do evento")
        let jid = "5547999990000@s.whatsapp.net"

        // docs/whatsapp-ponte.md:754
        let ola = evento(#"{"tipo": "ola", "contrato": 1, "jornal": "6f0c2d1e-…", "seq_atual": 4190, "seq_minimo": 1022}"#, "ola")
        exigir(ola == .ola(contrato: 1, jornal: "6f0c2d1e-…", seqAtual: 4190, seqMinimo: 1022),
               "ola virou \(ola)")

        // docs/whatsapp-ponte.md:765
        let ress = evento(#"{"tipo": "ressincronize", "jornal": "6f0c2d1e-…", "seq_atual": 4190}"#, "ressincronize")
        exigir(ress == .ressincronize(jornal: "6f0c2d1e-…", seqAtual: 4190), "ressincronize virou \(ress)")

        // docs/whatsapp-ponte.md:829 e :848
        let comRef = evento(numerado(seq: 4191, tipo: "mensagem", ts: 1762270500,
                                     dados: #"{"mensagem": \#(mensagemDocJSON), "conversa": \#(conversaDocJSON), "ref": "k-41"}"#),
                            "mensagem com ref")
        exigir(comRef == .numerado(seq: 4191, conta: "554791744143", ts: 1762270500, .mensagem(m, c, ref: "k-41")),
               "mensagem com ref virou \(comRef)")

        let semRef = evento(numerado(seq: 4191, tipo: "mensagem", ts: 1762270500,
                                     dados: #"{"mensagem": \#(mensagemDocJSON), "conversa": \#(conversaDocJSON)}"#),
                            "mensagem sem ref")
        exigir(semRef == .numerado(seq: 4191, conta: "554791744143", ts: 1762270500, .mensagem(m, c, ref: nil)),
               "mensagem sem ref virou \(semRef)")

        // `ts` do envelope (1762270601) é outro que o `ts` dos dados (1762270600)
        let reciboDados = { (r: String) in
            #"{"conversa": "\#(jid)", "ids": ["3EB0A1B2", "3EB0C3D4"], "recibo": "\#(r)", "de": "554791744143@s.whatsapp.net", "ts": 1762270600}"#
        }
        let porMim = evento(numerado(seq: 4192, tipo: "recibo", dados: reciboDados("lida_por_mim")), "recibo lida_por_mim")
        exigir(porMim == .numerado(seq: 4192, conta: "554791744143", ts: 1762270601,
                                   .recibo(conversa: jid, ids: ["3EB0A1B2", "3EB0C3D4"], recibo: .lidaPorMim,
                                           de: "554791744143@s.whatsapp.net", ts: 1762270600)),
               "recibo lida_por_mim virou \(porMim)")
        let reciboLida = evento(numerado(seq: 4193, tipo: "recibo", dados: reciboDados("lida")), "recibo lida")
        if case .numerado(_, _, _, .recibo(_, _, let r, _, _)) = reciboLida {
            exigir(r == .lida, "recibo \"lida\" virou \(r)")
        } else { exigir(false, "recibo lida virou \(reciboLida)") }
        let reciboEntregue = evento(numerado(seq: 4194, tipo: "recibo", dados: reciboDados("entregue")), "recibo entregue")
        if case .numerado(_, _, _, .recibo(_, _, let r, _, _)) = reciboEntregue {
            exigir(r == .entregue, "recibo \"entregue\" virou \(r)")
        } else { exigir(false, "recibo entregue virou \(reciboEntregue)") }
        let reciboNovo = evento(numerado(seq: 4195, tipo: "recibo", dados: reciboDados("tocada")), "recibo novo")
        if case .numerado(_, _, _, .recibo(_, _, let r, _, _)) = reciboNovo {
            exigir(r == .outro("tocada"), "recibo desconhecido virou \(r), esperado .outro")
        } else { exigir(false, "recibo desconhecido virou \(reciboNovo)") }

        let reacao = evento(numerado(seq: 4196, tipo: "reacao",
                                     dados: #"{"conversa": "\#(jid)", "alvo": "3EB0A1B2", "remetente": "\#(jid)", "de_mim": false, "emoji": "", "ts": 1762270610}"#),
                            "reacao removida")
        exigir(reacao == .numerado(seq: 4196, conta: "554791744143", ts: 1762270601,
                                   .reacao(conversa: jid, alvo: "3EB0A1B2", remetente: jid, deMim: false, emoji: "", ts: 1762270610)),
               "reacao com emoji vazio virou \(reacao)")

        let edicao = evento(numerado(seq: 4197, tipo: "edicao",
                                     dados: #"{"conversa": "\#(jid)", "alvo": "3EB0A1B2", "texto": "texto novo", "ts": 1762270620}"#),
                            "edicao")
        exigir(edicao == .numerado(seq: 4197, conta: "554791744143", ts: 1762270601,
                                   .edicao(conversa: jid, alvo: "3EB0A1B2", texto: "texto novo", ts: 1762270620)),
               "edicao virou \(edicao)")

        let apagamento = evento(numerado(seq: 4198, tipo: "apagamento",
                                         dados: #"{"conversa": "\#(jid)", "alvo": "3EB0A1B2", "por": "\#(jid)", "ts": 1762270630}"#),
                                "apagamento")
        exigir(apagamento == .numerado(seq: 4198, conta: "554791744143", ts: 1762270601,
                                       .apagamento(conversa: jid, alvo: "3EB0A1B2", por: jid, ts: 1762270630)),
               "apagamento virou \(apagamento)")

        let leitura = evento(numerado(seq: 4199, tipo: "leitura",
                                      dados: #"{"conversa": "\#(jid)", "nao_lidas": 0, "marcada_nao_lida": true}"#),
                             "leitura")
        exigir(leitura == .numerado(seq: 4199, conta: "554791744143", ts: 1762270601,
                                    .leitura(conversa: jid, naoLidas: 0, marcadaNaoLida: true)),
               "leitura virou \(leitura)")

        let midia = evento(numerado(seq: 4200, tipo: "midia",
                                    dados: #"{"conversa": "\#(jid)", "alvo": "3EB0A1B2", "ok": true}"#),
                           "midia")
        exigir(midia == .numerado(seq: 4200, conta: "554791744143", ts: 1762270601,
                                  .midia(conversa: jid, alvo: "3EB0A1B2", ok: true)),
               "midia virou \(midia)")

        let sinc = evento(numerado(seq: 4201, tipo: "sincronizacao", dados: #"{"conversas": 37}"#), "sincronizacao")
        exigir(sinc == .numerado(seq: 4201, conta: "554791744143", ts: 1762270601, .sincronizacao(conversas: 37)),
               "sincronizacao virou \(sinc)")

        // eventos de estado: sem `seq`
        let conta = ler(WAConta.self, contaJSON, "conta do evento")
        let ev = evento(#"{"tipo": "conta", "conta": "554791744143", "ts": 1762270700, "dados": \#(contaJSON)}"#, "evento conta")
        exigir(ev == .conta(conta), "evento conta virou \(ev)")

        let par = ler(WAPareamento.self, pareamentoQRJSON, "pareamento do evento")
        let evp = evento(#"{"tipo": "pareamento", "conta": "", "ts": 1762270700, "dados": \#(pareamentoQRJSON)}"#, "evento pareamento")
        exigir(evp == .pareamento(par), "evento pareamento virou \(evp)")

        // tipo desconhecido: com seq continua numerado (o seq conta), sem seq não
        let novoNum = evento(numerado(seq: 4300, tipo: "enquete", ts: 1762270800, dados: #"{"x": 1}"#), "tipo novo com seq")
        exigir(novoNum == .numerado(seq: 4300, conta: "554791744143", ts: 1762270800, .desconhecido(tipo: "enquete")),
               "tipo novo com seq virou \(novoNum)")
        let novo = evento(#"{"tipo": "enquete", "conta": "554791744143", "ts": 1762270800, "dados": {}}"#, "tipo novo sem seq")
        exigir(novo == .desconhecido(tipo: "enquete"), "tipo novo sem seq virou \(novo)")

        exigir(WAEvento.decodificar("isso não é json") == nil, "texto que não é JSON deveria dar nil")
        exigir(WAEvento.decodificar(#"{"seq": 1, "conta": "554791744143", "ts": 1, "dados": {}}"#) == nil,
               "JSON sem tipo deveria dar nil")
        exigir(WAEvento.decodificar("") == nil, "string vazia deveria dar nil")
    }

    // MARK: Respostas

    static func respostas() {
        let conta = ler(WAConta.self, contaJSON, "conta")
        let contas = ler(WARespostaContas.self, #"{"ok": true, "contas": [\#(contaJSON), \#(contaDeslogadaJSON)]}"#, "resposta contas")
        exigir(contas.contas.count == 2, "resposta contas: \(contas.contas.count) contas")
        exigir(contas.contas.first == conta, "resposta contas: primeira conta difere")
        exigir(contas.contas.last?.estado == .deslogada, "resposta contas: segunda conta deveria estar deslogada")

        let conv = ler(WAConversa.self, conversaDocJSON, "conversa")
        let r1 = ler(WARespostaConversas.self, #"{"ok": true, "conversas": [\#(conversaDocJSON)], "antes": null}"#, "resposta conversas")
        exigir(r1.conversas == [conv], "resposta conversas: lista difere")
        exigir(r1.antes == nil, "resposta conversas: \"antes\": null deveria ser nil")
        let r2 = ler(WARespostaConversas.self, #"{"ok": true, "conversas": [], "antes": "abc"}"#, "resposta conversas vazia")
        exigir(r2.conversas.isEmpty, "resposta conversas vazia: lista deveria ser vazia")
        exigir(r2.antes == "abc", "resposta conversas: antes \(String(describing: r2.antes)), esperado abc")

        let r3 = ler(WARespostaConversa.self, #"{"ok": true, "conversa": \#(conversaDocJSON)}"#, "resposta conversa")
        exigir(r3.conversa == conv, "resposta conversa difere")

        let m = ler(WAMensagem.self, mensagemDocJSON, "mensagem")
        let r4 = ler(WARespostaMensagens.self,
                     #"{"ok": true, "conversa": "120363406741729308@g.us", "mensagens": [\#(mensagemDocJSON)], "antes": "xyz"}"#,
                     "resposta mensagens")
        exigir(r4.conversa == "120363406741729308@g.us", "resposta mensagens: conversa \(r4.conversa)")
        exigir(r4.mensagens == [m], "resposta mensagens: lista difere")
        exigir(r4.antes == "xyz", "resposta mensagens: antes \(String(describing: r4.antes))")
        let r4b = ler(WARespostaMensagens.self,
                      #"{"ok": true, "conversa": "120363406741729308@g.us", "mensagens": [], "antes": null}"#,
                      "resposta mensagens vazia")
        exigir(r4b.mensagens.isEmpty && r4b.antes == nil, "resposta mensagens vazia: lista/antes")

        let enviada = mensagemJSON(deMim: true, status: "\"enviada\"")
        let r5 = ler(WARespostaEnvio.self, #"{"ok": true, "ref": "k-41", "mensagem": \#(enviada)}"#, "resposta envio")
        exigir(r5.ref == "k-41", "resposta envio: ref \(String(describing: r5.ref))")
        exigir(r5.mensagem.status == .enviada, "resposta envio: status \(String(describing: r5.mensagem.status))")
        exigir(r5.mensagem.deMim, "resposta envio: de_mim deveria ser true")
        let r5b = ler(WARespostaEnvio.self, #"{"ok": true, "mensagem": \#(enviada)}"#, "resposta envio sem ref")
        exigir(r5b.ref == nil, "resposta envio sem ref: ref deveria ser nil")

        let r6 = ler(WARespostaLida.self, #"{"ok":true,"marcadas":3}"#, "resposta lida")
        exigir(r6.marcadas == 3, "resposta lida: marcadas \(r6.marcadas)")

        let p = ler(WAPareamento.self, pareamentoQRJSON, "pareamento")
        let r7 = ler(WARespostaPareamento.self, #"{"ok": true, "pareamento": \#(pareamentoQRJSON)}"#, "resposta pareamento")
        exigir(r7.pareamento == p, "resposta pareamento difere")

        let g = ler(WAGrupo.self, grupoJSON, "grupo")
        let r8 = ler(WARespostaGrupo.self, #"{"ok": true, "grupo": \#(grupoJSON)}"#, "resposta grupo")
        exigir(r8.grupo == g, "resposta grupo difere")
        exigir(r8.grupo.participantes.count == 2, "resposta grupo: participantes")

        let id = ler(WAIdentificacao.self, #"{"ok": true, "servico": "whatsapp-ponte", "contrato": 1, "versao": "a1b2c3d"}"#,
                     "identificação da ponte")
        exigir(id.servico == "whatsapp-ponte" && id.contrato == 1 && id.versao == "a1b2c3d",
               "identificação da ponte: \(id)")

        let erro = ler(WAErroDaPonte.self,
                       #"{"ok":false,"erro":"conta_desconectada","detalhe":"a conta 554792508292 está deslogada"}"#,
                       "erro da ponte")
        exigir(erro.erro == "conta_desconectada", "erro da ponte: erro \(erro.erro)")
        exigir(erro.detalhe == "a conta 554792508292 está deslogada", "erro da ponte: detalhe \(String(describing: erro.detalhe))")
        let erroSemDetalhe = ler(WAErroDaPonte.self, #"{"ok":false,"erro":"ocupada"}"#, "erro sem detalhe")
        exigir(erroSemDetalhe.erro == "ocupada" && erroSemDetalhe.detalhe == nil, "erro sem detalhe")
    }

    // MARK: Chave

    static func chave() {
        let k = WAChave(conta: "554791744143", jid: "120363@g.us")
        exigir(k.conta == "554791744143" && k.jid == "120363@g.us", "WAChave: campos")
        exigir(k.texto == "554791744143|120363@g.us", "WAChave.texto: '\(k.texto)'")
        exigir(WAChave(texto: k.texto) == k, "WAChave(texto:) não devolve a mesma chave")
        exigir(WAChave(texto: "554791744143120363@g.us") == nil, "WAChave(texto:) sem '|' deveria ser nil")
        exigir(WAChave(texto: "|120363@g.us") == nil, "WAChave(texto:) com conta vazia deveria ser nil")
        exigir(WAChave(texto: "554791744143|") == nil, "WAChave(texto:) com jid vazio deveria ser nil")
        exigir(WAChave(texto: "") == nil, "WAChave(texto:) vazio deveria ser nil")
        let corte = WAChave(texto: "554791744143|a|b")
        exigir(corte?.conta == "554791744143" && corte?.jid == "a|b", "WAChave(texto:) corta no primeiro '|'")
        exigir(WAChave(conta: "1", jid: "a") != WAChave(conta: "2", jid: "a"), "WAChave: contas diferentes comparam iguais")
        exigir(Set([k, WAChave(conta: "554791744143", jid: "120363@g.us")]).count == 1, "WAChave: Hashable")
    }

    // MARK: Codificador

    static func codificador() {
        func texto(_ a: AmostraCodificavel) -> String {
            guard let d = try? WAJSON.codificador.encode(a), let s = String(data: d, encoding: .utf8) else {
                exigir(false, "WAJSON.codificador não codificou")
                return ""
            }
            return s
        }
        let semNome = texto(AmostraCodificavel(deMim: true, qrExpiraEm: 1762270620, remetenteNome: nil))
        exigir(semNome == #"{"de_mim":true,"qr_expira_em":1762270620}"#,
               "codificador: \(semNome), esperado snake_case, chaves em ordem e sem chave nil")
        exigir(!semNome.contains("null") && !semNome.contains("remetente"), "codificador gravou chave nil: \(semNome)")
        let comNome = texto(AmostraCodificavel(deMim: false, qrExpiraEm: 1, remetenteNome: "Fulano"))
        exigir(comNome == #"{"de_mim":false,"qr_expira_em":1,"remetente_nome":"Fulano"}"#,
               "codificador com remetente: \(comNome)")
    }
}
